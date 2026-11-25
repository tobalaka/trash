--!strict
-- Editor tool: pulls Luau files from the local sync server (Townsfolk/tools/syncserver.js,
-- port 34874, rooted at the Congress Game folder) into Studio by their Rojo-style paths.
--   require(game.ServerStorage.ProgressionSync).push("TRASH-Progression/src/", filter?)
local Http = game:GetService("HttpService")
local BASE = "http://127.0.0.1:34874"
local M = {}
local function ensureFolder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end
function M.push(prefix: string, filter: string?): string
	local index = Http:JSONDecode(Http:GetAsync(BASE .. "/index", true))
	local out = {}
	for _, rel in index do
		if rel:sub(1, #prefix) == prefix and rel:match("%.luau$") and (not filter or rel:find(filter, 1, true)) then
			local path = rel:sub(#prefix + 1)
			local parts = path:split("/")
			local file = table.remove(parts) :: string
			local class = "ModuleScript"
			local name = file:gsub("%.luau$", "")
			if name:match("%.server$") then class = "Script"; name = name:gsub("%.server$", "") end
			if name:match("%.client$") then class = "LocalScript"; name = name:gsub("%.client$", "") end
			local service = parts[1]
			local parent: Instance
			if service == "StarterPlayer" or service == "StarterPlayerScripts" then
				parent = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts") :: Instance
				for i = (if service == "StarterPlayer" then 3 else 2), #parts do
					parent = ensureFolder(parent, parts[i])
				end
			elseif service == "StarterCharacterScripts" then
				parent = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterCharacterScripts") :: Instance
			else
				parent = game:GetService(service)
				for i = 2, #parts do
					parent = ensureFolder(parent, parts[i])
				end
			end
			local text = Http:GetAsync(BASE .. "/file?path=" .. Http:UrlEncode(rel), true)
			local inst = parent:FindFirstChild(name)
			if inst and inst.ClassName ~= class then inst:Destroy(); inst = nil end
			if not inst then
				inst = Instance.new(class)
				inst.Name = name
				inst.Parent = parent
			end
			if (inst :: any).Source ~= text then
				(inst :: any).Source = text
				table.insert(out, inst:GetFullName() .. " " .. #text)
			end
		end
	end
	return if #out > 0 then table.concat(out, "\n") else "nothing changed"
end
return M
