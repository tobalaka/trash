--!strict
--[[
	MapGenSync - pulls src/ from the local sync server (tools/syncserver.js) into Studio.
	Mirrors Rojo naming: X.luau -> ModuleScript, X.server.luau -> Script, X.client.luau -> LocalScript,
	folders -> Folder. Roots: ServerStorage/MapGen, ReplicatedStorage/MapShared, ReplicatedStorage/Shared,
	ReplicatedStorage/Client and ServerScriptService/Combat are fully mirrored (unknown scripts are
	removed, but only when the running server serves that folder); StarterPlayerScripts and
	StarterCharacterScripts files are created/updated individually.
	ModuleScripts are recreated (not edited in place) so the next require() is never stale.
	Usage: require(game.ServerStorage.MapGenSync)("http://127.0.0.1:34873")
]]
local HttpService = game:GetService("HttpService")

local ROOTS: { [string]: () -> Instance } = {
	ServerStorage = function()
		return game:GetService("ServerStorage")
	end,
	ReplicatedStorage = function()
		return game:GetService("ReplicatedStorage")
	end,
	StarterPlayerScripts = function()
		-- the service, not any same-named script (StarterPlayer also holds a LocalScript called "StarterPlayerScripts")
		return game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts") :: Instance
	end,
	StarterCharacterScripts = function()
		return game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterCharacterScripts") :: Instance
	end,
	ServerScriptService = function()
		return game:GetService("ServerScriptService")
	end,
}
local MIRRORED = {
	["ServerStorage/MapGen"] = true,
	["ReplicatedStorage/MapShared"] = true,
	["ReplicatedStorage/Shared"] = true,
	["ReplicatedStorage/Client"] = true,
	["ServerScriptService/Combat"] = true,
}

local function classFor(file: string): (string, string)
	if file:match("%.server%.luau$") then
		return "Script", (file:gsub("%.server%.luau$", ""))
	elseif file:match("%.client%.luau$") then
		return "LocalScript", (file:gsub("%.client%.luau$", ""))
	end
	return "ModuleScript", (file:gsub("%.luau$", ""))
end

return function(base: string): string
	local index = HttpService:JSONDecode(HttpService:GetAsync(base .. "/index")) :: { string }
	local seen: { [Instance]: boolean } = {}
	local count = 0
	for _, path in index do
		if not path:match("%.luau$") then
			continue
		end
		local segs = string.split(path, "/")
		local rootFn = ROOTS[segs[1]]
		if not rootFn then
			continue
		end
		local parent: Instance = rootFn()
		for i = 2, #segs - 1 do
			local child = parent:FindFirstChild(segs[i])
			if not child then
				child = Instance.new("Folder")
				child.Name = segs[i]
				child.Parent = parent
			end
			seen[child :: Instance] = true
			parent = child :: Instance
		end
		local className, name = classFor(segs[#segs])
		local source = HttpService:GetAsync(base .. "/file?path=" .. HttpService:UrlEncode(path))
		local existing = parent:FindFirstChild(name)
		if existing and (existing.ClassName ~= className or className == "ModuleScript") then
			existing:Destroy()
			existing = nil
		end
		local script = existing or Instance.new(className)
		script.Name = name;
		(script :: any).Source = source
		script.Parent = parent
		seen[script] = true
		count += 1
	end
	-- remove scripts that no longer exist on disk inside fully mirrored roots
	local removed = 0
	for rootPath in MIRRORED do
		-- only prune a mirrored folder this server actually serves (another src root must not wipe it)
		local served = false
		for _, path in index do
			if string.sub(path, 1, #rootPath + 1) == rootPath .. "/" then
				served = true
				break
			end
		end
		local segs = string.split(rootPath, "/")
		local root = ROOTS[segs[1]]():FindFirstChild(segs[2])
		if root and served then
			for _, d in root:GetDescendants() do
				if d:IsA("LuaSourceContainer") and not seen[d] then
					d:Destroy()
					removed += 1
				end
			end
		end
	end
	return string.format("synced %d scripts, removed %d", count, removed)
end
