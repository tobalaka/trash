-- Disabled by default. Enable this Script in server Play mode for verification.
local HttpService=game:GetService("HttpService")
local ok,result=xpcall(function()
	return {
		core=require(script.Parent.CoreSpec).Run(),
		animations=require(script.Parent.AnimationSpec).Run(),
		integration=require(script.Parent.Integration).Run(),
	}
end,debug.traceback)
script:SetAttribute("Passed",ok)
script:SetAttribute("Result",ok and HttpService:JSONEncode(result) or result)
if ok then print("Combat checks passed: "..HttpService:JSONEncode(result)) else warn(result) end
script.Enabled=false

