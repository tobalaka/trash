--!strict
--[[
	Drops - items that fall into the world as pickups (vault: Item-Drops; tuning in
	Config.Drops). Smoglings, Apex Smoglings, the Junk Ram, rivals on a claimed bounty and
	smashed walls drop little part-built bundles (the same 3D icons as the Inventory) with a
	glow in the item's rarity colour, a name tag and a "Pick up" prompt (E).

	  - For OWNER_TIME only the owners may take a drop (the top damager, everyone who fought the
	    Ram, the bounty claimer); then anyone can. After LIFETIME it crumbles.
	  - The server checks every pickup: the prompt's own range, the player's distance, ownership
	    and a rate limit. Then the item goes into the inventory and the feed says so.
	  - At most MAX drops at once; the oldest go first.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared:WaitForChild("Config"):WaitForChild("Drops"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local FOLDER = "Drops"
local ICON_SIZE = 1.6 -- studs the item icon is scaled to
local HOVER = 1.4 -- studs above the ground
local GROUND_PROBE = 30
local SWEEP = 2 -- seconds between expiry checks
local RARITY_COLOR: { [string]: Color3 } = {
	Common = Color3.fromRGB(178, 178, 170),
	Uncommon = Color3.fromRGB(118, 206, 88),
	Rare = Color3.fromRGB(76, 152, 242),
	Epic = Color3.fromRGB(176, 92, 236),
	Legendary = Color3.fromRGB(255, 192, 48),
}

type Drop = { model: Model, item: string, count: number, owners: { [Player]: boolean }?, born: number }

local Drops = {}

local live: { Drop } = {}
local byPrompt: { [ProximityPrompt]: Drop } = {}
local rng = Random.new()
local Models: any = nil -- ReplicatedStorage.UI.Models (TRASH-UI), the part-built item icons

local function folder(): Folder
	local f = workspace:FindFirstChild(FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = workspace
	end
	return f :: Folder
end

local function remove(drop: Drop)
	local i = table.find(live, drop)
	if i then
		table.remove(live, i)
	end
	for prompt, d in byPrompt do
		if d == drop then
			byPrompt[prompt] = nil
		end
	end
	drop.model:Destroy()
end

-- where a drop rests: the first thing under it that isn't a body, a mob or another drop
local function restingPoint(at: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, name in { "Smoglings", "Mobs", "DestructionDebris" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(at + Vector3.new(0, GROUND_PROBE / 2, 0), Vector3.new(0, -GROUND_PROBE, 0), params)
	return (if hit then hit.Position else at) + Vector3.new(0, HOVER, 0)
end

local function build(itemId: string, count: number, at: Vector3): (Model, ProximityPrompt)
	local item = Items.get(itemId)
	local color = RARITY_COLOR[if item then item.rarity else "Common"] or RARITY_COLOR.Common
	local model = Instance.new("Model")
	model.Name = "Drop_" .. itemId
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	root.Parent = model
	model.PrimaryPart = root
	if Models and item then
		local ok, icon = pcall(Models.make, item.model)
		if ok and icon then
			local size = icon:GetExtentsSize()
			local biggest = math.max(size.X, size.Y, size.Z)
			if biggest > 0 then
				icon:ScaleTo(ICON_SIZE / biggest)
			end
			icon:PivotTo(root.CFrame)
			for _, d in icon:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
					d.CanQuery = false
				end
			end
			icon.Parent = model
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 8
	glow.Brightness = 1.4
	glow.Parent = root
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(color)
	sparkle.Size = NumberSequence.new(0.35)
	sparkle.Lifetime = NumberRange.new(0.8, 1.2)
	sparkle.Rate = 3
	sparkle.Speed = NumberRange.new(0.5, 1)
	sparkle.LightEmission = 0.6
	sparkle.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Pickup"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = string.format("%s x%d", if item then item.name else itemId, count)
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = D.PICKUP_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	return model, prompt
end

--[[
	Drops each item stack in `items` near `at`. `owners` (players) may pick them up first;
	nil means anyone at once.
]]
function Drops.spawn(at: Vector3, items: { [string]: number }, owners: { Player }?)
	local ownerSet: { [Player]: boolean }? = nil
	if owners and #owners > 0 then
		ownerSet = {}
		for _, p in owners do
			(ownerSet :: any)[p] = true
		end
	end
	for itemId, count in items do
		if count > 0 and Items.get(itemId) then
			local scatter = Vector3.new(rng:NextNumber(-D.SCATTER, D.SCATTER), 0, rng:NextNumber(-D.SCATTER, D.SCATTER))
			local model, prompt = build(itemId, count, restingPoint(at + scatter))
			local drop: Drop = { model = model, item = itemId, count = count, owners = ownerSet, born = os.clock() }
			table.insert(live, drop)
			byPrompt[prompt] = drop
			model.Parent = folder()
			while #live > D.MAX do
				remove(live[1])
			end
		end
	end
end

-- Rolls a drop table: { [item] = count } for every entry that hits.
function Drops.roll(rolls: { D.Roll }): { [string]: number }
	local out: { [string]: number } = {}
	for _, r in rolls do
		if rng:NextNumber() < r.chance then
			out[r.item] = (out[r.item] or 0) + rng:NextInteger(r.min or 1, r.max or 1)
		end
	end
	return out
end

local function pickUp(prompt: ProximityPrompt, player: Player)
	local drop = byPrompt[prompt]
	if not drop or not drop.model.Parent then
		return
	end
	if not Guard.allow(player, "Pickup", D.PICKUP_RATE) then
		return
	end
	local root = Regions.rootOf(player)
	local at = drop.model:GetPivot().Position
	if not root or (root.Position - at).Magnitude > D.PICKUP_RANGE + 2 then
		return
	end
	local owners = drop.owners
	local left = D.OWNER_TIME - (os.clock() - drop.born)
	if owners and not owners[player] and left > 0 then
		Sync.notify(player, "Toast", { text = string.format("Not yours yet (%ds).", math.ceil(left)), color = "Red" })
		return
	end
	remove(drop)
	Inventory.give(player, drop.item, drop.count)
	local item = Items.get(drop.item)
	Sync.notify(player, "Salvage", { method = "Pickup", lines = { string.format("%s x%d", if item then item.name else drop.item, drop.count) } })
	Bus.emit(player, "Pickup", { item = drop.item, count = drop.count })
end

function Drops.start()
	task.spawn(function()
		local ui = ReplicatedStorage:WaitForChild("UI", 30)
		local module = ui and ui:WaitForChild("Models", 10)
		if module and module:IsA("ModuleScript") then
			local ok, m = pcall(require, module)
			if ok then
				Models = m
			end
		end
	end)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, player)
		if byPrompt[prompt] then
			pickUp(prompt, player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SWEEP)
			local t = os.clock()
			for i = #live, 1, -1 do
				local d = live[i]
				if t - d.born > D.LIFETIME or not d.model.Parent then
					remove(d)
				end
			end
		end
	end)
end

return Drops
