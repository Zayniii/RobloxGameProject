-- ServerScriptService/RoleButtonPermissions.server.lua

local Players = game:GetService("Players")
local Permissions = require(game.ServerScriptService:WaitForChild("Permissions"))

local function setupPlayer(player)
	-- aus deinem Permissions-Module:
	local allowed = Permissions.CanSeeRoleButton(player)

	player:SetAttribute("CanSeeRoleBtn", allowed)
end

Players.PlayerAdded:Connect(setupPlayer)

-- falls Script nachträglich reingepackt wird
for _, plr in ipairs(Players:GetPlayers()) do
	setupPlayer(plr)
end
