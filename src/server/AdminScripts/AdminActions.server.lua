local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Permissions = require(game.ServerScriptService.Permissions)
local ADMIN_LEVEL = 252 -- z.B. "admin"

local AdminGetPlayers = ReplicatedStorage:WaitForChild("AdminGetPlayers")  -- RemoteFunction
local AdminDoAction  = ReplicatedStorage:WaitForChild("AdminDoAction")     -- RemoteEvent

-- optional: Freeze-Status merken
local frozen = {}  -- [userId] = true/false

local function isAdmin(plr)
	return Permissions.HasPermission(plr, ADMIN_LEVEL)
end

-- Hilfen
local function getHRP(char)
	return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function withTarget(userId)
	local target = Players:GetPlayerByUserId(userId)
	if not target then return nil, "target_offline" end
	local char = target.Character
	if not char then return nil, "no_character" end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil, "no_humanoid" end
	return target, char, hum
end

-- Playerliste für Panel
AdminGetPlayers.OnServerInvoke = function(caller)
	if not isAdmin(caller) then return nil, "no_permission" end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(list, {
			userId = p.UserId,
			name = p.Name,
			displayName = (p.DisplayName ~= "" and p.DisplayName) or p.Name,
			frozen = frozen[p.UserId] == true,
		})
	end
	return list
end

-- Aktionen
AdminDoAction.OnServerEvent:Connect(function(caller, action, targetUserId)
	if typeof(action) ~= "string" or typeof(targetUserId) ~= "number" then return end
	if not isAdmin(caller) then return end

	local target, char, hum = withTarget(targetUserId)
	if not target then return end

	if action == "kill" then
		hum.Health = 0

	elseif action == "kick" then
		target:Kick("You were kicked by an admin.")

	elseif action == "ban" then
		-- Platzhalter: hier würdest du in einen Ban-DataStore schreiben.
		-- Aktuell: sofortiger Kick.
		target:Kick("You were banned.")

	elseif action == "freeze" then
		frozen[target.UserId] = true
		local hrp = getHRP(char)
		if hrp then hrp.Anchored = true end
		hum.WalkSpeed = 0
		hum.JumpPower = 0

	elseif action == "unfreeze" then
		frozen[target.UserId] = false
		local hrp = getHRP(char)
		if hrp then hrp.Anchored = false end
		hum.WalkSpeed = 16
		hum.JumpPower = 50

	elseif action == "bring" then
		local cChar = caller.Character
		local cHRP = getHRP(cChar)
		local tHRP = getHRP(char)
		if cHRP and tHRP then
			tHRP.CFrame = cHRP.CFrame * CFrame.new(0, 3, -3)
		end

	elseif action == "teleportToTarget" then
		local cChar = caller.Character
		local cHRP = getHRP(cChar)
		local tHRP = getHRP(char)
		if cHRP and tHRP then
			cHRP.CFrame = tHRP.CFrame * CFrame.new(0, 3, 3)
		end

	end
end)
