-- the ragdoll now ships in StarterCharacterScripts (RagdollV3); without the old child this only errored on every spawn
if not script:FindFirstChild("RagdollV3") then
	return
end
game.Players.PlayerAdded:connect(function(player)
	player.CharacterAdded:connect(function(character)
		local ragdollV3 = script.RagdollV3:Clone()
		ragdollV3.Parent = character
		ragdollV3.Disabled = false
	end)
end)
