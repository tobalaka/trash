--!strict
--[[
	Fighters - server-side combat state for every living Humanoid model that fights or gets hit
	(player characters and NPC dummies alike). Created on first use, dropped on death or removal.
	Times are workspace:GetServerTimeNow() values.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))

export type Fighter = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,

	posture: number,
	postureHitAt: number,
	broken: boolean,

	blocking: boolean,
	parryArmed: boolean, -- the current F press still holds an unused parry
	blockPressAt: number,
	parryCooldownEnd: number,

	stunEnd: number,
	iframeStart: number,
	iframeEnd: number,

	actionEnd: number, -- swinging until
	combo: number, -- last accepted hit of the current chain, 0 = none
	chainUntil: number,
	nextAttackAt: number,
	attackSerial: number, -- bumped on interrupt so a pending hit is dropped
	pendingHitAt: number, -- when the swing in progress lands, 0 = none (feints cancel before this)
	armorUntil: number, -- hyper-armor: hits deal damage but do not interrupt
	uppercutCooldownEnd: number,
	aerialCooldownEnd: number,
	feintCooldownEnd: number,
	grabCooldownEnd: number,
	rollCooldownEnd: number,
	landedAt: number, -- when this fighter's last M1 connected (launcher cancel)
	landedCombo: number, -- which hit of the chain that was

	ragdollEnd: number,
	heldBy: Fighter?, -- the grabber holding this fighter
	hold: { Instance }?, -- the constraints of that hold
	freeParryUntil: number, -- after a bury, the next hit before this is parried

	-- air combo: a launched body floats until juggleUntil (the "Juggle" mover on its root)
	juggleUntil: number,
	juggleSerial: number,
	critCooldownEnd: number,

	-- knocked (Knock): down at 0 health; gripped (executed) or carried by another fighter
	knocked: boolean,
	knockUntil: number,
	grippedBy: Fighter?,
	carriedBy: Fighter?,
	gripping: Fighter?,
	carrying: Fighter?,

	-- anti-gank: who hit this fighter recently, and the buff's end
	recentAttackers: { [Fighter]: number },
	gankUntil: number,
	lastPlayerHitAt: number, -- a player's blow last landed (Knock: only those knock instead of kill)

	shownState: string,
	shownPosture: number,
	shownArmor: boolean,
}

local Fighters = {}

local list: { [Model]: Fighter } = {}

function Fighters.get(model: Model): Fighter?
	local existing = list[model]
	if existing then
		return existing
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	local f: Fighter = {
		model = model,
		humanoid = humanoid,
		root = root,
		player = Players:GetPlayerFromCharacter(model),
		posture = Config.POSTURE_MAX,
		postureHitAt = 0,
		broken = false,
		blocking = false,
		parryArmed = false,
		blockPressAt = 0,
		parryCooldownEnd = 0,
		stunEnd = 0,
		iframeStart = 0,
		iframeEnd = 0,
		actionEnd = 0,
		combo = 0,
		chainUntil = 0,
		nextAttackAt = 0,
		attackSerial = 0,
		pendingHitAt = 0,
		armorUntil = 0,
		uppercutCooldownEnd = 0,
		aerialCooldownEnd = 0,
		feintCooldownEnd = 0,
		grabCooldownEnd = 0,
		rollCooldownEnd = 0,
		landedAt = 0,
		landedCombo = 0,
		ragdollEnd = 0,
		heldBy = nil,
		hold = nil,
		freeParryUntil = 0,
		juggleUntil = 0,
		juggleSerial = 0,
		critCooldownEnd = 0,
		knocked = false,
		knockUntil = 0,
		grippedBy = nil,
		carriedBy = nil,
		gripping = nil,
		carrying = nil,
		recentAttackers = {},
		gankUntil = 0,
		lastPlayerHitAt = 0,
		shownState = "",
		shownPosture = -1,
		shownArmor = false,
	}
	list[model] = f
	humanoid.Died:Once(function()
		Fighters.remove(model)
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Fighters.remove(model)
		end
	end)
	return f
end

local removed: { (Fighter) -> () } = {}

-- `fn(f)` runs when a fighter is forgotten (it died or left the world), before its state is cleared.
function Fighters.onRemove(fn: (Fighter) -> ())
	table.insert(removed, fn)
end

function Fighters.remove(model: Model)
	local f = list[model]
	if not f then
		return
	end
	list[model] = nil
	for _, fn in removed do
		task.spawn(fn, f)
	end
	f.attackSerial += 1
	for _, part in f.hold or {} do
		part:Destroy()
	end
	f.hold = nil
	f.heldBy = nil
	if model.Parent then
		model:SetAttribute("CombatState", nil)
	end
end

function Fighters.all(): { [Model]: Fighter }
	return list
end

-- The fighter whose model contains `part`, if any (accessory handles included).
function Fighters.fromPart(part: BasePart): Fighter?
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return if model then Fighters.get(model) else nil
end

return Fighters
