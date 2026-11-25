--!strict
--[[
	Salvage - junk piles you hold E on to recover materials (vault: Salvage). The heart of the
	"waste becomes value" loop.

	Piles are the trash already lying around the world (bags, sacks, scrap heaps, tyres, washing
	machines, drums in Patchwork Town; antennas, signs and sofas too in the Wastezone) plus fresh
	piles from each Sky Dump. Each prop name maps to a loot table (Config.Environment.PILES).

	How you salvage depends on your faction (Config.Environment.METHOD):
	  Sort   (Menders)  3.0 s  every material, cleans the air most
	  Strip  (Scrappers)   1.8 s  more Scrap and some Dollars, fewer materials, cleans the air least
	  Salvage (no faction) 2.5 s
	The prompt's hold time and label are set per player on their client; the server times the
	hold itself (PromptButtonHoldBegan to Triggered) and refuses early triggers.
	A salvaged world pile vanishes and comes back after PILE_RESPAWN; a dump pile is gone for good.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Environment = require(Config:WaitForChild("Environment"))
local Factions = require(Config:WaitForChild("Factions"))
local Levels = require(Config:WaitForChild("Levels"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Pollution = require(script.Parent:WaitForChild("Pollution"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local TAG = "SalvagePile"
local HOLD_TOLERANCE = 0.3
local MAX_CHANCE = 0.95
local DUMP_FOLDER = "SkyDumpPiles"

local KIND_LABEL = {
	Bags = "Trash Bags",
	Scrap = "Scrap Heap",
	Tyre = "Old Tyres",
	Washer = "Dead Machine",
	Drum = "Rusty Drum",
	Antenna = "Fallen Antenna",
	Sign = "Broken Sign",
	Sofa = "Ruined Sofa",
	Dump = "Sky Dump",
}

export type Pile = {
	id: number,
	model: Model,
	kind: string,
	prompt: ProximityPrompt,
	active: boolean,
	site: string?, -- Sky Dump site, for dump piles
	region: string?,
	hidden: { [BasePart]: { number } }?, -- original Transparency, CanCollide, CanQuery
}

local Salvage = {}

local piles: { [ProximityPrompt]: Pile } = {}
local holds: { [Player]: { [ProximityPrompt]: number } } = {}
local buffs: { [string]: number } = {} -- faction -> server time the Scrap buff ends
local rng = Random.new()
local nextId = 0
local onSalvaged: ((Player, Pile, string) -> ())? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

function Salvage.methodOf(player: Player): string
	local p = Profiles.get(player)
	if p and p.faction then
		return Factions.INFO[p.faction].method
	end
	return Factions.UNALIGNED_METHOD
end

-- a faction's salvage Scrap bonus (from winning a Sky Dump), for `seconds`
function Salvage.setBuff(faction: string, seconds: number)
	buffs[faction] = now() + seconds
	workspace:SetAttribute("SalvageBuff_" .. faction, buffs[faction])
end

local function largestPart(model: Model): BasePart?
	local best, size = nil, -1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local s = d.Size.X * d.Size.Y * d.Size.Z
			if s > size then
				best, size = d, s
			end
		end
	end
	return best
end

local function setVisible(pile: Pile, visible: boolean)
	if visible then
		for part, v in pile.hidden or {} do
			if part.Parent then
				part.Transparency = v[1]
				part.CanCollide = v[2] == 1
				part.CanQuery = v[3] == 1
			end
		end
		pile.hidden = nil
	else
		local hidden = {}
		for _, d in pile.model:GetDescendants() do
			if d:IsA("BasePart") then
				hidden[d] = { d.Transparency, if d.CanCollide then 1 else 0, if d.CanQuery then 1 else 0 }
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		pile.hidden = hidden
	end
end

local function addPrompt(model: Model, kind: string): ProximityPrompt?
	local part = largestPart(model)
	if not part then
		return nil
	end
	local cf, size = model:GetBoundingBox()
	local attachment = Instance.new("Attachment")
	attachment.Name = "SalvagePoint"
	attachment.WorldPosition = cf.Position + Vector3.new(0, size.Y / 2 + 0.5, 0)
	attachment.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Salvage"
	prompt.ActionText = "Salvage"
	prompt.ObjectText = KIND_LABEL[kind] or kind
	prompt.HoldDuration = Environment.HOLD.Salvage
	prompt.MaxActivationDistance = Environment.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("SalvageKind", kind)
	prompt.Parent = attachment
	return prompt
end

function Salvage.register(model: Model, kind: string, site: string?): Pile?
	local prompt = addPrompt(model, kind)
	if not prompt then
		return nil
	end
	nextId += 1
	local cf = model:GetPivot()
	local pile: Pile = {
		id = nextId,
		model = model,
		kind = kind,
		prompt = prompt,
		active = true,
		site = site,
		region = Regions.at(cf.Position),
		hidden = nil,
	}
	piles[prompt] = pile
	CollectionService:AddTag(model, TAG)
	model.Destroying:Connect(function()
		Salvage.unregister(pile)
	end)
	return pile
end

function Salvage.unregister(pile: Pile)
	piles[pile.prompt] = nil
	pile.active = false
end

-- the loot one salvage gives (not yet granted)
local function roll(player: Player, pile: Pile, method: string): (number, number, number, { [string]: number })
	local def = Environment.PILES[pile.kind] or Environment.PILES.Bags
	local m = Environment.METHOD[method] or Environment.METHOD.Salvage
	local fx = Progress.effects(player)
	local mult = 1 + (fx.yield or 0)
	if Pollution.isLow() then
		mult += Environment.CLEAR_SKIES_YIELD
	end
	if pile.region == "Wasteland" then
		mult += Environment.WASTELAND_BONUS
	end
	local p = Profiles.get(player)
	local buffed = p and p.faction and (buffs[p.faction] or 0) > now()
	local scrap = math.floor(rng:NextInteger(def.scrap[1], def.scrap[2]) * m.scrap * mult * (if buffed then 1 + Environment.CONTEST_BUFF else 1) + 0.5)
	local dollars = if m.dollars[2] > 0 then rng:NextInteger(m.dollars[1], m.dollars[2]) else 0
	local residue = if def.residue and rng:NextNumber() < def.residue then 1 else 0
	local items: { [string]: number } = {}
	for _, l in def.loot do
		if rng:NextNumber() < math.min(MAX_CHANCE, l.chance * m.items * mult) then
			items[l.item] = (items[l.item] or 0) + rng:NextInteger(l.min, l.max)
		end
	end
	return scrap, dollars, residue, items
end

-- Processes `pile` for `player` with their faction's method. Used by prompts and Tidy Up.
function Salvage.process(player: Player, pile: Pile): boolean
	if not pile.active then
		return false
	end
	local p = Profiles.get(player)
	if not p then
		return false
	end
	pile.active = false
	pile.prompt.Enabled = false
	local method = Salvage.methodOf(player)
	local scrap, dollars, residue, items = roll(player, pile, method)
	Inventory.earn(player, { scrap = scrap, dollars = dollars, residue = residue })
	local lines = { string.format("+%d Scrap", scrap) }
	if dollars > 0 then
		table.insert(lines, string.format("+$%d", dollars))
	end
	if residue > 0 then
		table.insert(lines, "+1 Anima Residue")
	end
	for id, n in items do
		Inventory.give(player, id, n)
		local item = Items.get(id)
		table.insert(lines, string.format("%s x%d", if item then item.name else id, n))
	end
	Sync.notify(player, "Salvage", { method = method, lines = lines })
	Pollution.apply(method)
	Progress.addExp(player, Levels.EXP.SALVAGE)
	if p.faction then
		Progress.addStanding(player, Factions.STANDING.SALVAGE)
	end
	p.stats.piles = (p.stats.piles or 0) + 1
	Bus.emit(player, "Salvage", { method = method, region = pile.region, kind = pile.kind, site = pile.site })
	if onSalvaged then
		onSalvaged(player, pile, method)
	end
	if pile.site then
		-- dump piles are gone for good
		Salvage.unregister(pile)
		pile.model:Destroy()
	else
		setVisible(pile, false)
		task.delay(Environment.PILE_RESPAWN, function()
			if pile.model.Parent then
				setVisible(pile, true)
				pile.active = true
				pile.prompt.Enabled = true
			end
		end)
	end
	return true
end

-- the nearest active pile within `radius` of a point
function Salvage.nearest(position: Vector3, radius: number): Pile?
	local best, bestDist = nil, radius
	for _, pile in piles do
		if pile.active then
			local d = (pile.model:GetPivot().Position - position).Magnitude
			if d <= bestDist then
				best, bestDist = pile, d
			end
		end
	end
	return best
end

function Salvage.onSalvaged(fn: (Player, Pile, string) -> ())
	onSalvaged = fn
end

-- every active dump pile of a site
function Salvage.pilesAt(site: string): { Pile }
	local out = {}
	for _, pile in piles do
		if pile.site == site and pile.active then
			table.insert(out, pile)
		end
	end
	return out
end

-- ── Sky Dump piles: a part-built heap of fresh trash ──

local HEAP_COLORS = {
	Color3.fromRGB(40, 40, 44), -- black bags
	Color3.fromRGB(60, 70, 64),
	Color3.fromRGB(120, 96, 64),
	Color3.fromRGB(150, 150, 146),
	Color3.fromRGB(196, 92, 52),
	Color3.fromRGB(90, 140, 150),
	Color3.fromRGB(214, 200, 160),
}

function Salvage.buildHeap(position: Vector3, seed: number): Model
	local r = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "DumpHeap"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(r:NextNumber(5, 7), 1.2, r:NextNumber(5, 7))
	base.Color = Color3.fromRGB(70, 62, 52)
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.CanCollide = true
	base.CFrame = CFrame.new(position + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, r:NextNumber(0, math.pi), 0)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model
	for i = 1, r:NextInteger(6, 9) do
		local p = Instance.new("Part")
		p.Name = "Junk" .. i
		local s = r:NextNumber(1, 2.4)
		p.Size = Vector3.new(s, s * r:NextNumber(0.5, 1.1), s * r:NextNumber(0.6, 1.2))
		p.Color = HEAP_COLORS[r:NextInteger(1, #HEAP_COLORS)]
		p.Material = if r:NextNumber() < 0.5 then Enum.Material.Fabric else Enum.Material.CorrodedMetal
		p.Anchored = true
		p.CanCollide = false
		local offset = Vector3.new(r:NextNumber(-2, 2), 0.8 + r:NextNumber(0, 1.6), r:NextNumber(-2, 2))
		p.CFrame = base.CFrame * CFrame.new(offset) * CFrame.Angles(r:NextNumber(-0.6, 0.6), r:NextNumber(0, math.pi), r:NextNumber(-0.6, 0.6))
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
	end
	model.PrimaryPart = base
	local folder = workspace:FindFirstChild(DUMP_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = DUMP_FOLDER
		folder.Parent = workspace
	end
	model.Parent = folder
	return model
end

-- ── prompts ──

local function onHoldBegan(prompt: ProximityPrompt, player: Player)
	if not piles[prompt] then
		return
	end
	holds[player] = holds[player] or {}
	holds[player][prompt] = os.clock()
end

local function onTriggered(prompt: ProximityPrompt, player: Player)
	local pile = piles[prompt]
	if not pile then
		return
	end
	local started = holds[player] and holds[player][prompt]
	if holds[player] then
		holds[player][prompt] = nil
	end
	-- Fleetfoot's Quick Hands shortens the hold (the client shows the same, via SalvageSpeed)
	local need = (Environment.HOLD[Salvage.methodOf(player)] or Environment.HOLD.Salvage) * (1 - (Progress.effects(player).salvageSpeed or 0))
	if not started or os.clock() - started < need - HOLD_TOLERANCE then
		return
	end
	local root = Regions.rootOf(player)
	if not root or (root.Position - pile.model:GetPivot().Position).Magnitude > Environment.PROMPT_DISTANCE + 8 then
		return
	end
	Salvage.process(player, pile)
end

function Salvage.start()
	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptButtonHoldBegan:Connect(onHoldBegan)
	ProximityPromptService.PromptTriggered:Connect(onTriggered)
	Players.PlayerRemoving:Connect(function(player)
		holds[player] = nil
	end)
	-- world piles: the junk props MapGen scattered
	local count, seen = 0, 0
	for _, path in Environment.PILE_FOLDERS do
		local folder: Instance? = workspace
		for _, name in path do
			folder = folder and folder:FindFirstChild(name)
		end
		if folder then
			for _, child in folder:GetChildren() do
				local kind = Environment.PROP_KINDS[child.Name]
				if kind and child:IsA("Model") and not child:FindFirstChild("SalvagePoint", true) then
					if Salvage.register(child, kind) then
						count += 1
					end
				end
				seen += 1
				if seen % 200 == 0 then
					task.wait()
				end
			end
		end
	end
	workspace:SetAttribute("SalvagePiles", count)
end

return Salvage
