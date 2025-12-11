local Players = game:GetService("Players")

local function hideHumanoidOverhead(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		char.ChildAdded:Once(function(child)
			if child:IsA("Humanoid") then
				hideHumanoidOverhead(char)
			end
		end)
		return
	end

	-- Versteckt Name + Lebensbalken über dem Kopf (Roblox-Standard)
	if hum:FindFirstChild("DisplayName") then end -- (nur, damit Studio nicht meckert)

	-- Beste, zukunftssichere Variante:
	if hum:GetPropertyChangedSignal("DisplayDistanceType") then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Extra-Absicherung für ältere Rigs (optional):
	if hum:FindFirstChildWhichIsA("NumberValue") then end
	if hum:FindFirstChildWhichIsA("StringValue") then end
	if hum:FindFirstChildWhichIsA("BoolValue") then end
	if hum:FindFirstChildWhichIsA("ObjectValue") then end

	-- Manche Spiele benutzen noch diese Properties – falls vorhanden, auf 0:
	pcall(function()
		hum.NameDisplayDistance = 0
		hum.HealthDisplayDistance = 0
	end)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		hideHumanoidOverhead(char)
	end)
	-- Falls Character schon existiert:
	if plr.Character then
		hideHumanoidOverhead(plr.Character)
	end
end)
