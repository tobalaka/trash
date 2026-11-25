--!strict
--[[
	MapGen.Export - streams parts to the local dev server (tools/syncserver.js POST /dump) as
	JSON lines, so the map can be previewed in headless Blender (blender/ref_render.py) when the
	Studio viewport is not available. Dev tool only; needs HttpService.HttpEnabled during the
	session. Same line format as refplace/parts.jsonl.
]]

local HttpService = game:GetService("HttpService")

local Export = {}

local BATCH = 2500

local function line(p: BasePart, folder: string): string
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local shape = p.ClassName
	if p:IsA("Part") then
		shape = p.Shape.Name
	end
	local c = p.Color
	return HttpService:JSONEncode({
		s = shape,
		p = { x, y, z },
		r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		z = { p.Size.X, p.Size.Y, p.Size.Z },
		c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
		m = p.Material.Name,
		f = folder,
		t = p.Transparency,
	})
end

-- Export every visible BasePart under `roots` to dumps/<name> on the dev server.
function Export.parts(base: string, name: string, roots: { Instance }): number
	local lines: { string } = {}
	local total = 0
	local function flush()
		if #lines > 0 then
			HttpService:PostAsync(base .. "/dump?name=" .. HttpService:UrlEncode(name), table.concat(lines, "\n") .. "\n")
			table.clear(lines)
		end
	end
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				table.insert(lines, line(d, root.Name))
				total += 1
				if #lines >= BATCH then
					flush()
					task.wait()
				end
			end
		end
	end
	flush()
	return total
end

return Export
