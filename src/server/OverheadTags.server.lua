print("[OverheadTags] Server script started (with persistence)")

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- Module & Remotes/Templates
local Permissions = require(game.ServerScriptService.Permissions)
local RequestRoleVisibility = ReplicatedStorage:WaitForChild("RequestRoleVisibility")
local template: BillboardGui = ReplicatedStorage:WaitForChild("OverheadGui")

-- DataStore
local VIS_DS = DataStoreService:GetDataStore("RoleVisibilityDS_v1") -- versionsbump bei Schemaänderungen

local function keyFor(userId: number): string
	return "roleVisible_" .. tostring(userId)
end

-- Cache im RAM (userId -> bool)
local roleVisible: {[number]: boolean} = {}

-- Utils: Farben pro Rang (für Overhead)
local function getColorForRank(lower: string): Color3
	if lower == "owner" or lower == "head developer" then
		return Color3.fromRGB(118, 0, 0)
	elseif lower == "admin" then
		return Color3.fromRGB(255, 0, 0)
	elseif lower == "moderator" then
		return Color3.fromRGB(0, 99, 0)
	elseif lower == "test moderator" then
		return Color3.fromRGB(0, 255, 0)
	elseif lower == "vip" then
		return Color3.fromRGB(255, 255, 0)
	elseif lower == "manager" then
		return Color3.fromRGB(93, 12, 144)
	elseif lower == "tester" then
		return Color3.fromRGB(32, 184, 255)
	end
	return Color3.fromRGB(255, 255, 255)
end

-- Anwenden: nur Rolle+Farbe schalten; Name bleibt immer
local function applyAppearance(gui: BillboardGui, roleLower: string, showRole: boolean)
	local frame = gui:WaitForChild("Frame") :: Frame
	local roleLabel = frame:WaitForChild("RoleLabel") :: TextLabel
	local userLabel = frame:WaitForChild("UsernameLabel") :: TextLabel

	if showRole then
		local c = getColorForRank(roleLower)
		roleLabel.Visible = true
		roleLabel.TextColor3 = c
		userLabel.TextColor3 = c
	else
		roleLabel.Visible = false
		userLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- neutral
	end

	gui:SetAttribute("RoleVisible", showRole)
end

local function applyOverheadTag(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChildWhichIsA("BasePart")
	if not head then
		warn(("[OverheadTags] %s: no head/upper torso/basepart found"):format(player.Name))
		return
	end

	for _, child in ipairs(head:GetChildren()) do
		if child:IsA("BillboardGui") and child.Name == "OverheadGui" then
			child:Destroy()
		end
	end

	local tag = template:Clone()
	tag.Name = "OverheadGui"
	tag.Adornee = head
	tag.Parent = head

	tag.AlwaysOnTop = false         -- nicht durch Wände
	tag.StudsOffset = Vector3.new(0, 2.5, 0)
	tag.MaxDistance = 250
	tag.Enabled = true              -- Name immer sichtbar

	local frame = tag:WaitForChild("Frame") :: Frame
	local roleLabel = frame:WaitForChild("RoleLabel") :: TextLabel
	local userLabel = frame:WaitForChild("UsernameLabel") :: TextLabel

	local role = (Permissions.GetRank(player) or "user")
	local lower = role:lower()
	local displayName = (player.DisplayName ~= "" and player.DisplayName) or player.Name

	roleLabel.Text = "[" .. role:upper() .. "]"
	userLabel.Text = displayName

	-- Sichtbarkeit aus Cache laden (falls nicht vorhanden, default false)
	local showRole = roleVisible[player.UserId]
	if showRole == nil then showRole = false end

	-- Attribute für den Chat setzen/aktualisieren (Chat liest dieses Flag)
	player:SetAttribute("RoleName", lower)
	player:SetAttribute("RoleVisible", showRole)

	applyAppearance(tag, lower, showRole)
	print(("[OverheadTags] Init for %s | roleOn=%s"):format(player.Name, tostring(showRole)))
end

-- Persistence: load/save mit Retry
local function loadVisibility(userId: number): boolean
	for i = 1, 3 do
		local ok, val = pcall(function()
			return VIS_DS:GetAsync(keyFor(userId))
		end)
		if ok then
			if typeof(val) == "boolean" then return val else return false end
		end
		task.wait(0.5 * i)
	end
	warn("[OverheadTags] Load failed for userId", userId, "-> default false")
	return false
end

local function saveVisibility(userId: number, value: boolean)
	for i = 1, 3 do
		local ok, err = pcall(function()
			VIS_DS:SetAsync(keyFor(userId), value)
		end)
		if ok then return true end
		warn(("[OverheadTags] Save retry %d for %d failed: %s"):format(i, userId, tostring(err)))
		task.wait(0.5 * i)
	end
	return false
end

-- Player lifecycle
Players.PlayerAdded:Connect(function(player)
	-- Laden (default false bei Fehler/kein Eintrag)
	local persisted = loadVisibility(player.UserId)
	roleVisible[player.UserId] = persisted

	-- Attribute früh setzen (Clients können sofort lesen)
	local lower = (Permissions.GetRank(player) or "user"):lower()
	player:SetAttribute("RoleName", lower)
	player:SetAttribute("RoleVisible", persisted)

	if player.Character then
		applyOverheadTag(player, player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 5)
		applyOverheadTag(player, char)
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	local value = roleVisible[plr.UserId]
	if value ~= nil then
		saveVisibility(plr.UserId, value)
	end
	roleVisible[plr.UserId] = nil
end)

-- Toggle vom Button: nur Rolle+Farbe (Name bleibt)
RequestRoleVisibility.OnServerEvent:Connect(function(plr: Player, newOn: boolean)
	if typeof(newOn) ~= "boolean" then
		warn(("[OverheadTags] %s sent invalid value: %s"):format(plr.Name, tostring(newOn)))
		return
	end

	-- Update Cache + sofort speichern (Best Effort)
	roleVisible[plr.UserId] = newOn
	plr:SetAttribute("RoleVisible", newOn)  -- Chat liest dieses Flag
	task.spawn(function()
		saveVisibility(plr.UserId, newOn)
	end)

	local char = plr.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
		or char:FindFirstChild("UpperTorso")
		or char:FindFirstChildWhichIsA("BasePart")
	if not head then return end

	local gui = head:FindFirstChild("OverheadGui") :: BillboardGui
	if not gui then
		applyOverheadTag(plr, char)
		gui = head:FindFirstChild("OverheadGui") :: BillboardGui
	end
	if not gui then return end

	local role = (Permissions.GetRank(plr) or "user")
	local lower = role:lower()

	applyAppearance(gui, lower, newOn)
	print(("[OverheadTags] %s toggled role to %s (persisted)"):format(plr.Name, tostring(newOn)))
end)
