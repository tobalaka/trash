-- Enable in server Play mode after the player enters through the copied menu.
local ok,result=xpcall(function() return require(script.Parent.TrainingSpec).Run() end,debug.traceback)
script:SetAttribute("Passed",ok)
script:SetAttribute("Result",ok and game:GetService("HttpService"):JSONEncode(result) or tostring(result))
if not ok then warn(result) end
