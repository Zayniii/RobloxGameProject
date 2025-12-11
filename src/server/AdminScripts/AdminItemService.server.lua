-- ServerScriptService/AdminScripts/AdminItemService.server.lua

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local Permissions  = require(game.ServerScriptService:WaitForChild("Permissions"))
local ItemsConfig  = require(ReplicatedStorage:WaitForChild("ItemsConfig"))

-- TipJar-Remotes
local tipJarRemotesFolder = ReplicatedStorage:WaitForChild("TipJarRemotes")
local CloseTipJarGui      = tipJarRemotesFolder:WaitForChild("CloseTipJarGui")

local ADMIN_LEVEL = Permissions.Level["admin"] or 253

---------------------------------------------------------------------
-- ADMIN-CHECK (früh definiert, damit es überall funktioniert)
---------------------------------------------------------------------
local function isAdmin(plr)
	return Permissions.HasPermission(plr, ADMIN_LEVEL)
end

---------------------------------------------------------------------
-- Tools-Ordner in ServerStorage finden
---------------------------------------------------------------------
local function findToolsFolder()
	local f = ServerStorage:FindFirstChild("Tools") or ServerStorage:FindFirstChild("tools")
	if f and f:IsA("Folder") then 
		return f 
	end

	for _, d in ipairs(ServerStorage:GetDescendants()) do
		if d:IsA("Folder") and d.Name:lower() == "tools" then
			return d
		end
	end

	error("[AdminItems] 'Tools' Ordner nicht gefunden in ServerStorage.")
end

local TOOLS = findToolsFolder()

---------------------------------------------------------------------
-- Items-Liste bauen:
-- 1) Konfigurierte Items aus ItemsConfig.list
-- 2) Alle Tools aus TOOLS, die noch nicht vorkommen
---------------------------------------------------------------------
local function buildItems()
	local list = {}
	local byId = {}
	local usedToolNames = {}

	-- 1) Konfigurierte Items (z.B. SpeedCoil, StandardTipJar)
	if ItemsConfig.list then
		for _, meta in ipairs(ItemsConfig.list) do
			-- kleine Kopie, um das Original nicht zu verändern
			local item = table.clone(meta)
			item.toolName = item.toolName or item.id

			table.insert(list, item)
			byId[item.id] = item

			if item.toolName then
				usedToolNames[item.toolName] = true
			end
		end
	end

	-- 2) Alle Tools aus TOOLS, die noch nicht vorkommen
	for _, tool in ipairs(TOOLS:GetChildren()) do
		if tool:IsA("Tool") and not usedToolNames[tool.Name] then
			local item = {
				id          = tool.Name,
				displayName = tool.Name,
				toolName    = tool.Name,
				-- optional: image, gamePassId, etc.
			}
			table.insert(list, item)
			byId[item.id] = item
			usedToolNames[tool.Name] = true
		end
	end

	return list, byId
end

---------------------------------------------------------------------
-- Remotes bereitstellen
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local RF_GIVE = remotes:FindFirstChild("Admin_GiveItem")
if not RF_GIVE then
	RF_GIVE = Instance.new("RemoteFunction")
	RF_GIVE.Name = "Admin_GiveItem"
	RF_GIVE.Parent = remotes
end

local RF_REMOVE = remotes:FindFirstChild("Admin_RemoveItem")
if not RF_REMOVE then
	RF_REMOVE = Instance.new("RemoteFunction")
	RF_REMOVE.Name = "Admin_RemoveItem"
	RF_REMOVE.Parent = remotes
end

local RF_GET_ITEMS = remotes:FindFirstChild("Admin_GetItemDefs")
if not RF_GET_ITEMS then
	RF_GET_ITEMS = Instance.new("RemoteFunction")
	RF_GET_ITEMS.Name = "Admin_GetItemDefs"
	RF_GET_ITEMS.Parent = remotes
end

---------------------------------------------------------------------
-- Helper-Funktionen
---------------------------------------------------------------------
local function getItem(itemId)
	local _, byId = buildItems()
	return byId[itemId]
end

local function getToolTemplate(toolName)
	-- 1) Normale Tools in TOOLS
	local t = TOOLS:FindFirstChild(toolName)
	if t and t:IsA("Tool") then
		return t
	end

	-- 2) Spezial: TipJar in ServerStorage/TipJarSkins/StandardTipJar
	if toolName == "StandardTipJar" then
		local skins = ServerStorage:FindFirstChild("TipJarSkins")
		if skins then
			local jarTemplate = skins:FindFirstChild("StandardTipJar")
			if jarTemplate and jarTemplate:IsA("Tool") then
				return jarTemplate
			end
		end
	end

	return nil
end

local function setupTipJarTool(tool: Tool, ownerPlayer: Player)
	-- Owner-Value
	local ownerValue = tool:FindFirstChild("Owner")
	if not ownerValue then
		ownerValue = Instance.new("ObjectValue")
		ownerValue.Name = "Owner"
		ownerValue.Parent = tool
	end
	ownerValue.Value = ownerPlayer

	-- SkinId
	if tool:GetAttribute("SkinId") == nil then
		tool:SetAttribute("SkinId", "Standard")
	end

	-- Unequipped -> GUI schließen
	tool.Unequipped:Connect(function()
		if ownerValue.Value then
			CloseTipJarGui:FireAllClients(ownerValue.Value.UserId)
		end
	end)
end

local function removeToolEverywhere(plr, toolName)
	local removed = 0

	local function drop(container)
		if not container then return end
		local t = container:FindFirstChild(toolName)
		if t and t:IsA("Tool") then
			removed += 1
			t:Destroy()
		end
	end

	drop(plr.Backpack)
	drop(plr.Character)
	drop(plr:FindFirstChild("StarterGear"))

	return removed
end

-- Soft-Respawn: Spieler neu laden und an gleiche Stelle setzen
local function respawnAtSameSpot(plr)
	local oldCF
	do
		local char = plr.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		oldCF = hrp and hrp.CFrame or nil
	end

	local conn
	conn = plr.CharacterAdded:Connect(function(newChar)
		if conn then 
			conn:Disconnect()
			conn = nil 
		end
		local newHRP = newChar:WaitForChild("HumanoidRootPart", 5)
		if newHRP and oldCF then
			task.defer(function()
				newChar:PivotTo(oldCF * CFrame.new(0, 2, 0)) -- 2 Studs höher
			end)
		end
	end)

	pcall(function()
		plr:LoadCharacter()
	end)
end

---------------------------------------------------------------------
-- Remote-Callbacks
---------------------------------------------------------------------

-- Item-Definitionen holen (für Admin-GUI)
RF_GET_ITEMS.OnServerInvoke = function(caller)
	if not isAdmin(caller) then
		return {} -- Sicherheit: keine Infos für Nicht-Admins
	end

	local list = buildItems()
	return list
end

-- Item geben
RF_GIVE.OnServerInvoke = function(caller, targetUserId, itemId)
	if not isAdmin(caller) then 
		return false, "Keine Berechtigung." 
	end

	if typeof(targetUserId) ~= "number" or not itemId then 
		return false, "Ungültige Parameter." 
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then 
		return false, "Spieler nicht online." 
	end

	local item = getItem(itemId)
	if not item then 
		return false, "Item unbekannt." 
	end

	local tmpl = getToolTemplate(item.toolName)
	if not tmpl then
		return false, ("Tool '%s' nicht gefunden."):format(item.toolName)
	end

	local isTipJar = (item.toolName == "StandardTipJar")

	-- Backpack
	local backpackTool = tmpl:Clone()
	backpackTool.Parent = target.Backpack
	if isTipJar then
		setupTipJarTool(backpackTool, target)
	end

	-- StarterGear (persistentes Loadout)
	local sg = target:FindFirstChild("StarterGear")
	if sg then
		local sgTool = tmpl:Clone()
		sgTool.Parent = sg
		if isTipJar then
			setupTipJarTool(sgTool, target)
		end
	end

	respawnAtSameSpot(target)

	return true, ("'%s' an %s gegeben."):format(item.displayName, target.Name)
end

-- Item entfernen
RF_REMOVE.OnServerInvoke = function(caller, targetUserId, itemId)
	if not isAdmin(caller) then 
		return false, "Keine Berechtigung." 
	end

	if typeof(targetUserId) ~= "number" or not itemId then 
		return false, "Ungültige Parameter." 
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then 
		return false, "Spieler nicht online." 
	end

	local item = getItem(itemId)
	if not item then 
		return false, "Item unbekannt." 
	end

	local removed = removeToolEverywhere(target, item.toolName)
	if removed == 0 then
		return false, ("Spieler hat '%s' nicht."):format(item.displayName)
	end

	respawnAtSameSpot(target)

	return true, ("'%s' entfernt (x%d)."):format(item.displayName, removed)
end
