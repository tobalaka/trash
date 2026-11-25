--!strict
-- HQWaterFlow (StarterPlayerScripts) - scrolls the water surface textures that HQArt.Water tags.
--   "HQWaterFlow" Textures: OffsetStudsU/V = BaseU/V (world anchor, so neighbouring strips stay continuous)
--   + SpeedU/V studs per second; foam strips (attribute Foam = lapping rate) creep along the shore and lap in and
--   out across it.
-- 30 Hz is plenty for slow water; only textures that exist on this client are touched (works with streaming), and
-- only those within NEAR studs of the camera (the far ones keep their last offset; nobody can tell from there).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

type Entry = { bu: number, bv: number, u: number, v: number, su: number, sv: number, foam: number?, corner: boolean, tr: number, at: Vector3 }
local NEAR = 450
local live: { [Texture]: Entry } = {}

local function add(t: Instance)
	if t:IsA("Texture") then
		live[t] = {
			bu = (t:GetAttribute("BaseU") :: number?) or 0,
			bv = (t:GetAttribute("BaseV") :: number?) or 0,
			u = (t:GetAttribute("SpeedU") :: number?) or 0,
			v = (t:GetAttribute("SpeedV") :: number?) or 0,
			su = t.StudsPerTileU,
			sv = t.StudsPerTileV,
			foam = t:GetAttribute("Foam") :: number?,
			corner = t:GetAttribute("Corner") == true, -- shore corner pieces pulse with their body but never slide
			tr = t.Transparency,
			at = if t.Parent and t.Parent:IsA("BasePart") then t.Parent.Position else Vector3.zero,
		}
	end
end

for _, t in CollectionService:GetTagged("HQWaterFlow") do
	add(t)
end
CollectionService:GetInstanceAddedSignal("HQWaterFlow"):Connect(add)
CollectionService:GetInstanceRemovedSignal("HQWaterFlow"):Connect(function(t)
	live[t :: Texture] = nil
end)

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < 1 / 30 then
		return
	end
	acc = 0
	-- world-synced clock: every strip of a body reads the same time, so the pattern never tears at a seam
	local now = workspace:GetServerTimeNow()
	local cam = workspace.CurrentCamera
	local eye = if cam then cam.CFrame.Position else Vector3.zero
	for t, e in live do
		-- water sheets are big: measure to the nearest point of the part, not its centre
		local p = t.Parent
		local d = (e.at - eye).Magnitude
		if p and p:IsA("BasePart") then
			d -= math.max(p.Size.X, p.Size.Z) / 2
		end
		if d > NEAR then
			continue
		end
		t.OffsetStudsU = (e.bu + now * e.u) % e.su
		if e.foam then
			if not e.corner then
				t.OffsetStudsV = math.sin(now * e.foam) * 0.35
			end
			t.Transparency = e.tr + 0.2 * (0.5 + 0.5 * math.sin(now * e.foam * 0.5))
		else
			t.OffsetStudsV = (e.bv + now * e.v) % e.sv
		end
	end
end)
