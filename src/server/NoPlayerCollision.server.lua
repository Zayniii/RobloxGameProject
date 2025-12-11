-- ServerScriptService/NoPlayerCollision.server.lua
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local GROUP = "Players"

-- Neue API: registriert die Gruppe (idempotent)
PhysicsService:RegisterCollisionGroup(GROUP)

-- Spieler sollen nicht mit Spielern kollidieren, aber mit Default schon
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
PhysicsService:CollisionGroupSetCollidable(GROUP, "Default", true)

local function tagIfPart(inst)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = GROUP  -- statt SetPartCollisionGroup(...)
	end
end

local function onCharacter(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		tagIfPart(d)
	end
	char.DescendantAdded:Connect(tagIfPart) -- Accessories/Tool-Handles nachträglich
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(onCharacter)
	if plr.Character then onCharacter(plr.Character) end
end)

-- Falls Script neu lädt, während Spieler schon da sind:
for _, plr in ipairs(Players:GetPlayers()) do
	if plr.Character then onCharacter(plr.Character) end
end
