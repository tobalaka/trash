--!strict
--[[
	MapGen.ZFight - finds Z-fighting: two visible faces that lie in the same plane, point the
	same way and overlap. The user's rule is "no Z-fighting anywhere", so every build ends with
	this scan (Build.job("zfight")).

	Scope: box faces of Parts (Shape = Block) and the flat faces of WedgeParts (bottom, back).
	MeshParts and unions are skipped here (their faces are not boxes); the kit meshes are
	audited separately in Blender (tools/zfight/mesh_zfight.py). Invisible parts (collision
	proxies, Transparency 1) never render, so they are ignored.

	Method: every face becomes (normal, plane offset, rectangle in the plane). Faces are bucketed
	by quantised normal + offset (with a neighbouring-offset check, so planes 0.01 apart still
	meet), then by a coarse 2D grid inside each plane so a plane holding thousands of ground
	caps never compares every pair. A candidate pair must also be coplanar where the faces are:
	each face's centre within PLANE_TOL of the other's plane (offsets measured from the world
	origin alone would let two faces 0.15 apart look level when their normals differ by 1e-5
	thousands of studs out). Two faces fight when their rectangles overlap by more than
	MIN_OVERLAP on every separating axis (touching edges do not count).
]]

local ZFight = {}

ZFight.PLANE_TOL = 0.02 -- studs: offsets closer than this count as the same plane
ZFight.MIN_OVERLAP = 0.05 -- studs of overlap needed on every axis to count as a fight
local CELL = 64

export type Face = { part: BasePart, n: Vector3, d: number, p: Vector3, c: Vector2, ax: Vector2, ay: Vector2, hx: number, hy: number }
export type Report = { faces: number, pairs: number, examples: { string } }

local function basis(n: Vector3): (Vector3, Vector3)
	local ref = math.abs(n.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
	local u = n:Cross(ref).Unit
	return u, n:Cross(u)
end

local function addFace(out: { Face }, part: BasePart, centre: Vector3, n: Vector3, a: Vector3, ha: number, b: Vector3, hb: number)
	local u, v = basis(n)
	table.insert(out, {
		part = part,
		n = n,
		d = n:Dot(centre),
		p = centre,
		c = Vector2.new(centre:Dot(u), centre:Dot(v)),
		ax = Vector2.new(a:Dot(u), a:Dot(v)),
		ay = Vector2.new(b:Dot(u), b:Dot(v)),
		hx = ha,
		hy = hb,
	})
end

local function facesOf(part: BasePart, out: { Face })
	local cf, s = part.CFrame, part.Size / 2
	local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
	if part:IsA("WedgePart") then
		-- flat faces only: bottom and the tall back face (+Z in part space is -LookVector)
		addFace(out, part, cf.Position - U * s.Y, -U, R, s.X, L, s.Z)
		addFace(out, part, cf.Position - L * s.Z, -L, R, s.X, U, s.Y)
		return
	end
	addFace(out, part, cf.Position + R * s.X, R, U, s.Y, L, s.Z)
	addFace(out, part, cf.Position - R * s.X, -R, U, s.Y, L, s.Z)
	addFace(out, part, cf.Position + U * s.Y, U, R, s.X, L, s.Z)
	addFace(out, part, cf.Position - U * s.Y, -U, R, s.X, L, s.Z)
	addFace(out, part, cf.Position + L * s.Z, L, R, s.X, U, s.Y)
	addFace(out, part, cf.Position - L * s.Z, -L, R, s.X, U, s.Y)
end

local function visible(p: Instance): boolean
	if not p:IsA("BasePart") or p.Transparency >= 0.99 then
		return false
	end
	if p:IsA("Part") then
		return p.Shape == Enum.PartType.Block
	end
	return p:IsA("WedgePart")
end

-- Overlap of two rectangles in the plane: separating-axis test on the four edge normals.
local function overlaps(a: Face, b: Face): boolean
	for _, axis in { a.ax, a.ay, b.ax, b.ay } do
		local ca, cb = a.c:Dot(axis), b.c:Dot(axis)
		local ra = math.abs(a.ax:Dot(axis)) * a.hx + math.abs(a.ay:Dot(axis)) * a.hy
		local rb = math.abs(b.ax:Dot(axis)) * b.hx + math.abs(b.ay:Dot(axis)) * b.hy
		if math.abs(ca - cb) > ra + rb - ZFight.MIN_OVERLAP then
			return false
		end
	end
	return true
end

local function nkey(n: Vector3): string
	return string.format("%.3f,%.3f,%.3f", n.X, n.Y, n.Z)
end

function ZFight.scan(roots: { Instance }, maxExamples: number?): Report
	local faces: { Face } = {}
	local n = 0
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if visible(d) then
				facesOf(d :: BasePart, faces)
				n += 1
				if n % 5000 == 0 then
					task.wait()
				end
			end
		end
	end
	-- bucket: normal + plane offset
	local buckets: { [string]: { Face } } = {}
	for _, f in faces do
		local k = nkey(f.n) .. "|" .. math.floor(f.d / ZFight.PLANE_TOL + 0.5)
		local list = buckets[k]
		if not list then
			list = {}
			buckets[k] = list
		end
		table.insert(list, f)
	end
	local report: Report = { faces = #faces, pairs = 0, examples = {} }
	local seen: { [string]: boolean } = {}
	local checked = 0
	local function compare(list: { Face }, other: { Face }, same: boolean)
		-- coarse grid on the larger list, probe with the other
		local grid: { [number]: { Face } } = {}
		for _, f in list do
			local r = math.abs(f.ax.X) * f.hx + math.abs(f.ay.X) * f.hy
			local q = math.abs(f.ax.Y) * f.hx + math.abs(f.ay.Y) * f.hy
			for gx = math.floor((f.c.X - r) / CELL), math.floor((f.c.X + r) / CELL) do
				for gy = math.floor((f.c.Y - q) / CELL), math.floor((f.c.Y + q) / CELL) do
					local key = gx * 1000003 + gy
					grid[key] = grid[key] or {}
					table.insert(grid[key], f)
				end
			end
		end
		for _, a in other do
			local r = math.abs(a.ax.X) * a.hx + math.abs(a.ay.X) * a.hy
			local q = math.abs(a.ax.Y) * a.hx + math.abs(a.ay.Y) * a.hy
			for gx = math.floor((a.c.X - r) / CELL), math.floor((a.c.X + r) / CELL) do
				for gy = math.floor((a.c.Y - q) / CELL), math.floor((a.c.Y + q) / CELL) do
					for _, b in grid[gx * 1000003 + gy] or {} do
						if b.part == a.part or math.abs(a.d - b.d) > ZFight.PLANE_TOL * 4 then
							continue
						end
						local gap = b.p - a.p
						if math.abs(a.n:Dot(gap)) > ZFight.PLANE_TOL or math.abs(b.n:Dot(gap)) > ZFight.PLANE_TOL then
							continue
						end
						local id = a.part:GetDebugId() .. "|" .. b.part:GetDebugId()
						local id2 = b.part:GetDebugId() .. "|" .. a.part:GetDebugId()
						if seen[id] or seen[id2] then
							continue
						end
						if overlaps(a, b) then
							seen[id] = true
							report.pairs += 1
							if #report.examples < (maxExamples or 40) then
								table.insert(report.examples, string.format("%s <-> %s  n=(%s) d=%.2f", a.part:GetFullName(), b.part:GetFullName(), nkey(a.n), a.d))
							end
						end
					end
				end
			end
			checked += 1
			if checked % 4000 == 0 then
				task.wait()
			end
		end
	end
	for k, list in buckets do
		compare(list, list, true)
		-- neighbouring offset bucket catches planes that straddle a rounding boundary
		local sep = string.find(k, "|", 1, true) :: number
		local base = tonumber(string.sub(k, sep + 1)) :: number
		for off = 1, 4 do
			local nb = buckets[string.sub(k, 1, sep) .. (base + off)]
			if nb then
				compare(nb, list, false)
			end
		end
	end
	print(string.format("[MapGen] zfight: %d faces checked, %d fighting pairs", report.faces, report.pairs))
	for _, line in report.examples do
		print("   " .. line)
	end
	return report
end

return ZFight
