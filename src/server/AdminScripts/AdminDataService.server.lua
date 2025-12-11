-- ServerScriptService/AdminDataService.server.lua

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Permissions = require(ServerScriptService:WaitForChild("Permissions"))
local ShardService = require(ServerScriptService:WaitForChild("ShardService"))
local AdminPlaytimeDelta = ReplicatedStorage:WaitForChild("AdminPlaytimeDelta") :: BindableEvent

local ADMIN_LEVEL = Permissions.Level["admin"] or 253

-- ==== Remotes vorbereiten ====
local root = ReplicatedStorage:FindFirstChild("AdminDataRemotes")
if not root then
	root = Instance.new("Folder")
	root.Name = "AdminDataRemotes"
	root.Parent = ReplicatedStorage
end

local RF_Get  = root:FindFirstChild("Admin_GetUserData")  :: RemoteFunction
local RF_Apply = root:FindFirstChild("Admin_ApplyUserData") :: RemoteFunction

if not RF_Get then
	RF_Get = Instance.new("RemoteFunction")
	RF_Get.Name = "Admin_GetUserData"
	RF_Get.Parent = root
end

if not RF_Apply then
	RF_Apply = Instance.new("RemoteFunction")
	RF_Apply.Name = "Admin_ApplyUserData"
	RF_Apply.Parent = root
end

-- ==== Helper ====

local function isAdmin(plr: Player): boolean
	return Permissions.HasPermission(plr, ADMIN_LEVEL)
end

local function getPlayerById(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function getStatInstance(plr: Player, names: {string})
	-- 1) direkt unter dem Player
	for _, name in ipairs(names) do
		local v = plr:FindFirstChild(name)
		if v and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
			return v
		end
	end

	-- 2) leaderstats
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		for _, name in ipairs(names) do
			local v = ls:FindFirstChild(name)
			if v and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
				return v
			end
		end
	end

	-- 3) TipJarStats (hier liegen bei dir Donated/Raised)
	local tjs = plr:FindFirstChild("TipJarStats")
	if tjs then
		for _, name in ipairs(names) do
			local v = tjs:FindFirstChild(name)
			if v and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
				return v
			end
		end
	end

	return nil
end



local function getStatNumber(plr: Player, names: {string}): number
	local inst = getStatInstance(plr, names)
	if not inst then return 0 end

	if inst:IsA("StringValue") then
		return tonumber(inst.Value) or 0
	else
		return inst.Value
	end
end

local function setStatNumber(plr: Player, names: {string}, newValue: number)
	local inst = getStatInstance(plr, names)
	if not inst then
		-- Fallback: keine Instanz -> nichts tun
		return
	end

	newValue = math.max(0, math.floor(newValue))

	if inst:IsA("StringValue") then
		inst.Value = tostring(newValue)
	else
		inst.Value = newValue
	end
end

local function addStatDelta(plr: Player, names: {string}, delta: number)
	if delta == 0 then return end

	-- Shards machen wir über dein ShardService:
	if names[1] == "Shards" then
		if delta > 0 then
			ShardService.AddShards(plr, delta)
		else
			ShardService.RemoveShards(plr, -delta)
		end
		return
	end

	local current = getStatNumber(plr, names)
	local newValue = current + delta
	setStatNumber(plr, names, newValue)
end

-- ==== Mapping für deine 4 Stats ====
local STAT_DEF = {
	shards   = { names = {"Shards"} },
	donated  = { names = {"Donated", "Donations"} },
	raised   = { names = {"Raised"} },
	playtime = { names = {"Minuten", "Playtime"} }, -- anpassen falls du anderen Namen nutzt
}

local function getPlaytimeMinutesFor(plr: Player): number
	-- 1) bevorzugt: echtes Attribut vom Playtime-System
	local attr = plr:GetAttribute("PlaytimeMinutesTotal")
	if typeof(attr) == "number" then
		return attr
	end

	-- 2) Fallback: falls aus irgendeinem Grund Attribut fehlt, auf das Leaderstat schauen
	local v = getStatInstance(plr, STAT_DEF.playtime.names)
	if v then
		if v:IsA("IntValue") or v:IsA("NumberValue") then
			return v.Value
		elseif v:IsA("StringValue") then
			local n = tonumber(v.Value)
			return n or 0
		end
	end

	return 0
end


local function buildUserData(plr: Player)
	return {
		shards   = getStatNumber(plr, STAT_DEF.shards.names),
		donated  = getStatNumber(plr, STAT_DEF.donated.names),
		raised   = getStatNumber(plr, STAT_DEF.raised.names),
		playtime = getPlaytimeMinutesFor(plr), -- <<< HIER das Attribut nutzen
	}
end


-- ==== RemoteFunction: Admin_GetUserData ====
RF_Get.OnServerInvoke = function(caller: Player, targetUserId: number)
	if not isAdmin(caller) then
		return { ok = false, error = "no_permission" }
	end

	if type(targetUserId) ~= "number" then
		return { ok = false, error = "bad_userId" }
	end

	local target = getPlayerById(targetUserId)
	if not target then
		return { ok = false, error = "target_offline" }
	end

	local data = buildUserData(target)

	-- 🔍 Debug:
	print(("[AdminData] GetUserData -> %s | shards=%d, donated=%d, raised=%d, playtime=%d")
		:format(target.Name, data.shards, data.donated, data.raised, data.playtime))

	return { ok = true, data = data }
end


-- ==== RemoteFunction: Admin_ApplyUserData ====
-- diffs = { shardsDelta = number?, donatedDelta = number?, raisedDelta = number?, playtimeDelta = number? }
RF_Apply.OnServerInvoke = function(caller: Player, targetUserId: number, diffs: any)
	if not isAdmin(caller) then
		return { ok = false, error = "no_permission" }
	end

	if type(targetUserId) ~= "number" then
		return { ok = false, error = "bad_userId" }
	end
	if type(diffs) ~= "table" then
		return { ok = false, error = "bad_payload" }
	end

	local target = getPlayerById(targetUserId)
	if not target then
		return { ok = false, error = "target_offline" }
	end

	local function numOrZero(v)
		local n = tonumber(v)
		if not n then return 0 end
		if n ~= n or n == math.huge or n == -math.huge then
			return 0
		end
		return math.floor(n)
	end

	local shardsDelta   = numOrZero(diffs.shardsDelta)
	local donatedDelta  = numOrZero(diffs.donatedDelta)
	local raisedDelta   = numOrZero(diffs.raisedDelta)
	local playtimeDelta = numOrZero(diffs.playtimeDelta)

	if shardsDelta ~= 0 then
		addStatDelta(target, STAT_DEF.shards.names, shardsDelta)
	end
	if donatedDelta ~= 0 then
		addStatDelta(target, STAT_DEF.donated.names, donatedDelta)
	end
	if raisedDelta ~= 0 then
		addStatDelta(target, STAT_DEF.raised.names, raisedDelta)
	end
	if playtimeDelta ~= 0 then
		-- AdminPlaytimeDelta erwartet: UserId, Delta in Minuten
		AdminPlaytimeDelta:Fire(target.UserId, playtimeDelta)
	end


	print(("[AdminData] %s edited %s: Δ shards=%d, donated=%d, raised=%d, playtime=%d")
		:format(caller.Name, target.Name, shardsDelta, donatedDelta, raisedDelta, playtimeDelta))

	-- neue Werte zurückgeben -> Client kann UI wieder "echtzeit-grün" machen
	local data = buildUserData(target)
	return { ok = true, data = data }
end
