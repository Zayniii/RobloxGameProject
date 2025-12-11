-- GamePassOwnership.server.lua

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ServerStorage      = game:GetService("ServerStorage")

-- GamePass IDs
local GAMEPASS_ID_SPEEDCOIL       = 1571841199       -- SpeedCoil-Pass
local GAMEPASS_ID_STANDARD_TIPJAR = 1586826004      -- TipJar-Pass

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local tipJarRemotesFolder = ReplicatedStorage:FindFirstChild("TipJarRemotes")
local CloseTipJarGui

if tipJarRemotesFolder then
	CloseTipJarGui = tipJarRemotesFolder:FindFirstChild("CloseTipJarGui")
else
	warn("[GamePassOwnership] TipJarRemotes nicht gefunden, TipJar-GUI-Close deaktiviert")
end

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local IsSpeedCoilOwned = remotes:FindFirstChild("IsSpeedCoilOwned")
if not IsSpeedCoilOwned then
	IsSpeedCoilOwned = Instance.new("RemoteFunction")
	IsSpeedCoilOwned.Name = "IsSpeedCoilOwned"
	IsSpeedCoilOwned.Parent = remotes
end

local IsStandardTipJarOwned = remotes:FindFirstChild("IsStandardTipJarOwned")
if not IsStandardTipJarOwned then
	IsStandardTipJarOwned = Instance.new("RemoteFunction")
	IsStandardTipJarOwned.Name = "IsStandardTipJarOwned"
	IsStandardTipJarOwned.Parent = remotes
end

local GrantSpeedCoilIfOwned = remotes:FindFirstChild("GrantSpeedCoilIfOwned")
if not GrantSpeedCoilIfOwned then
	GrantSpeedCoilIfOwned = Instance.new("RemoteEvent")
	GrantSpeedCoilIfOwned.Name = "GrantSpeedCoilIfOwned"
	GrantSpeedCoilIfOwned.Parent = remotes
end

local GrantTipJarIfOwned = remotes:FindFirstChild("GrantTipJarIfOwned")
if not GrantTipJarIfOwned then
	GrantTipJarIfOwned = Instance.new("RemoteEvent")
	GrantTipJarIfOwned.Name = "GrantTipJarIfOwned"
	GrantTipJarIfOwned.Parent = remotes
end

----------------------------------------------------------------
-- Caches für GamePass-Besitz
----------------------------------------------------------------

local ownsSpeedCoilCache      = {}   -- [userId] = true/false
local ownsStandardTipJarCache = {}   -- [userId] = true/false

local function ownsSpeedCoil(userId)
	if ownsSpeedCoilCache[userId] ~= nil then
		return ownsSpeedCoilCache[userId]
	end

	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, GAMEPASS_ID_SPEEDCOIL)
	end)

	if not ok then
		warn("[ownsSpeedCoil] pcall failed for userId", userId)
		has = false
	end

	ownsSpeedCoilCache[userId] = has
	print(("[ownsSpeedCoil] userId=%d -> %s (cached)"):format(userId, tostring(has)))
	return has
end

local function ownsStandardTipJar(userId)
	if ownsStandardTipJarCache[userId] ~= nil then
		return ownsStandardTipJarCache[userId]
	end

	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, GAMEPASS_ID_STANDARD_TIPJAR)
	end)

	if not ok then
		warn("[ownsStandardTipJar] pcall failed for userId", userId)
		has = false
	end

	ownsStandardTipJarCache[userId] = has
	print(("[ownsStandardTipJar] userId=%d -> %s (cached)"):format(userId, tostring(has)))
	return has
end

----------------------------------------------------------------
-- SpeedCoil: Tool-Handling
----------------------------------------------------------------

local function hasSpeedCoilAlready(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	if backpack and backpack:FindFirstChild("SpeedCoil") then
		return true
	end
	if character and character:FindFirstChild("SpeedCoil") then
		return true
	end

	return false
end

local function giveSpeedCoil(player)
	local toolsFolder = ServerStorage:FindFirstChild("Tools")
	if not toolsFolder then
		warn("ServerStorage/Tools fehlt")
		return false
	end

	local template = toolsFolder:FindFirstChild("SpeedCoil")
	if not template or not template:IsA("Tool") then
		warn("Tool 'SpeedCoil' fehlt oder ist kein Tool")
		return false
	end

	if hasSpeedCoilAlready(player) then
		return true
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack")

	local clone = template:Clone()
	clone.Name = "SpeedCoil"
	clone.Parent = backpack

	print("[GrantSpeedCoil] SpeedCoil an", player.Name, "gegeben")
	return true
end

----------------------------------------------------------------
-- TipJar: Tool-Handling
----------------------------------------------------------------

local function hasTipJarAlready(player)
	local function checkContainer(container)
		if not container then return false end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("Tool") and inst:FindFirstChild("Owner") then
				return true
			end
		end
		return false
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	if checkContainer(backpack) then return true end
	if checkContainer(character) then return true end

	return false
end

local function giveStandardTipJar(player)
	local tipJarSkinsFolder = ServerStorage:FindFirstChild("TipJarSkins")
	if not tipJarSkinsFolder then
		warn("ServerStorage/TipJarSkins fehlt")
		return false
	end

	local template = tipJarSkinsFolder:FindFirstChild("StandardTipJar")
	if not template or not template:IsA("Tool") then
		warn("Tool 'StandardTipJar' fehlt oder ist kein Tool")
		return false
	end

	if hasTipJarAlready(player) then
		return true
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack")
	local clone = template:Clone()
	clone.Name = "TipJar"

	local ownerValue = clone:FindFirstChild("Owner")
	if not ownerValue then
		ownerValue = Instance.new("ObjectValue")
		ownerValue.Name = "Owner"
		ownerValue.Parent = clone
	end
	ownerValue.Value = player

	if clone:GetAttribute("SkinId") == nil then
		clone:SetAttribute("SkinId", "Standard")
	end

	if CloseTipJarGui then
		clone.Unequipped:Connect(function()
			if ownerValue.Value then
				print("TipJar unequipped -> CloseTipJarGui")
				CloseTipJarGui:FireAllClients(ownerValue.Value.UserId)
			end
		end)
	end

	clone.Parent = backpack

	print("[GrantTipJar] StandardTipJar an", player.Name, "gegeben (Owner =", player.Name .. ")")
	return true
end

----------------------------------------------------------------
-- RemoteFunctions: Ownership abfragen
----------------------------------------------------------------

IsSpeedCoilOwned.OnServerInvoke = function(player)
	return ownsSpeedCoil(player.UserId)
end

IsStandardTipJarOwned.OnServerInvoke = function(player)
	return ownsStandardTipJar(player.UserId)
end

----------------------------------------------------------------
-- RemoteEvents: nach Kauf Tool geben
----------------------------------------------------------------

GrantSpeedCoilIfOwned.OnServerEvent:Connect(function(plr)
	-- Cache zurücksetzen, damit der neue Kauf erkannt wird
	ownsSpeedCoilCache[plr.UserId] = nil
	local has = ownsSpeedCoil(plr.UserId)
	print("[GrantSpeedCoilIfOwned] ownsSpeedCoil =", has, "für", plr.Name)
	if has then
		giveSpeedCoil(plr)
	end
end)

GrantTipJarIfOwned.OnServerEvent:Connect(function(plr)
	ownsStandardTipJarCache[plr.UserId] = nil
	local has = ownsStandardTipJar(plr.UserId)
	print("[GrantTipJarIfOwned] ownsStandardTipJar =", has, "für", plr.Name)
	if has then
		giveStandardTipJar(plr)
	end
end)

----------------------------------------------------------------
-- Beim Join & Respawn automatisch geben
----------------------------------------------------------------

Players.PlayerAdded:Connect(function(plr)
	local hasCoil = ownsSpeedCoil(plr.UserId)
	local hasJar  = ownsStandardTipJar(plr.UserId)

	print(("[Join] %s ownsSpeedCoil=%s, ownsStandardTipJar=%s")
		:format(plr.Name, tostring(hasCoil), tostring(hasJar)))

	local function onCharacterAdded(char)
		local backpack = plr:WaitForChild("Backpack")
		task.wait(0.1)

		if hasCoil then
			local ok = giveSpeedCoil(plr)
			print("[CharacterAdded] giveSpeedCoil:", ok, "für", plr.Name)
		end

		if hasJar then
			local ok2 = giveStandardTipJar(plr)
			print("[CharacterAdded] giveStandardTipJar:", ok2, "für", plr.Name)
		end
	end

	plr.CharacterAdded:Connect(onCharacterAdded)

	if plr.Character then
		onCharacterAdded(plr.Character)
	end
end)
