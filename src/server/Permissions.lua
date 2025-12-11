-- ServerScriptService/Permissions  (ModuleScript)
local Permissions = {}

local GroupId = 219894398 -- DEINE Gruppen-ID

-- Mappe Rollennamen (aus der Gruppe) -> internes Level (nur für dich, optional)
Permissions.Level = {
	["owner"] = 255,
	["head developer"] = 254,
	["manager"] = 253,
	["admin"] = 253,
	["developer"] = 8,
	["moderator"] = 7,
	["event team"] = 5,
	["test moderator"] = 4,
	["content creator"] = 3,
	["tester"] = 2,
	["vip"] = 2,
	["user"] = 1,
	["guest"] = 0,
}

local ALLOWED_ROLES = { ["owner"]=true, ["head developer"]=true, ["admin"]= true,["moderator"]= true ,["tester"]=true, ["test moderator"] = true,["designer"]=true }
local ALLOWED_USERIDS = { -- optional, frei befüllbar
	-- weitere IDs ...
}

-- Rollenname aus der Roblox-Gruppe holen (als lowercase-String)
function Permissions.GetRank(player)
	local roleName = player:GetRoleInGroup(GroupId) or "User"
	return roleName:lower()
end

-- Level für ggf. spätere Rechteprüfung
function Permissions.GetLevel(player)
	local rank = Permissions.GetRank(player)
	return Permissions.Level[rank] or 0
end

-- Rechteprüfung (optional, für Commands etc.)
function Permissions.HasPermission(player, neededLevel)
	return Permissions.GetLevel(player) >= neededLevel
end

function Permissions.CanSeeRoleButton(player)
	if ALLOWED_USERIDS[player.UserId] then
		return true
	end

	local role = Permissions.GetRank(player) or "user"
	role = role:lower()

	-- alle außer "user" und "guest" dürfen
	if role == "user" or role == "guest" then
		return false
	end

	return true
end


local NEEDED_LEVEL_FOR_TOOL = Permissions.Level["head developer"] -- = 254

function Permissions.CanReceiveOwnerTool(player)
	-- Whitelist zieht immer
	if ALLOWED_USERIDS[player.UserId] then return true end
	-- Owner (255) & Head Dev (254) dürfen, Rest nicht
	return Permissions.GetLevel(player) >= NEEDED_LEVEL_FOR_TOOL
end

return Permissions
