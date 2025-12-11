local Players        = game:GetService("Players")
local ServerStorage  = game:GetService("ServerStorage")
local Permissions    = require(game.ServerScriptService.Permissions)

-- ==== Konfig ====
local ADMIN_LEVEL        = 253
local UI_TEMPLATE_NAMES  = { "AdminGui", "AdminUI" }  -- akzeptierte Namen im ServerStorage
local UI_INSTANCE_NAME   = "AdminUI"                  -- Name im PlayerGui

-- ==== Template auffinden (robust) ====
local AdminUITemplate
for _, name in ipairs(UI_TEMPLATE_NAMES) do
	AdminUITemplate = ServerStorage:FindFirstChild(name) or ServerStorage:FindFirstChild(name, true)
	if AdminUITemplate and AdminUITemplate:IsA("ScreenGui") then break end
end
assert(AdminUITemplate and AdminUITemplate:IsA("ScreenGui"),
	("ScreenGui-Template nicht gefunden. Erwartet einen von: %s"):format(table.concat(UI_TEMPLATE_NAMES, ", ")))

-- ==== Helpers ====
local granting = {}  -- Debounce pro Spieler

local function hasAdmin(plr)
	local ok, res = pcall(Permissions.HasPermission, plr, ADMIN_LEVEL)
	return ok and res == true
end

local function getPlayerGui(plr, timeout)
	local pg = plr:FindFirstChildOfClass("PlayerGui")
	if pg then return pg end
	pg = plr:WaitForChild("PlayerGui", timeout or 5)
	return pg
end

local function grant(plr)
	if granting[plr] then return end
	granting[plr] = true
	local pg = getPlayerGui(plr, 5)
	if not pg then
		warn("[AdminUI] PlayerGui nicht gefunden für", plr.Name)
		granting[plr] = nil
		return
	end

	-- Alte Instanz entfernen (falls vorhanden)
	local old = pg:FindFirstChild(UI_INSTANCE_NAME)
	if old then old:Destroy() end

	-- Klonen & konfigurieren
	local gui
	local ok, err = pcall(function()
		gui = AdminUITemplate:Clone()
		gui.Name = UI_INSTANCE_NAME
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = 50
		gui.Enabled = true
		gui.Parent = pg
	end)
	if not ok then
		warn("[AdminUI] Klonen fehlgeschlagen:", err)
	end

	-- Attribut für Client-Gating
	plr:SetAttribute("IsAdmin", true)
	granting[plr] = nil
end

local function revoke(plr)
	local pg = plr:FindFirstChildOfClass("PlayerGui")
	if pg then
		local g = pg:FindFirstChild(UI_INSTANCE_NAME)
		if g then g:Destroy() end
	end
	plr:SetAttribute("IsAdmin", false)
end

local function refresh(plr)
	if hasAdmin(plr) then
		grant(plr)
	else
		revoke(plr)
	end
end

-- ==== Hooks ====
Players.PlayerAdded:Connect(function(plr)
	refresh(plr)
	-- optionales Refresh beim Respawn (falls andere Scripts UI entfernen)
	plr.CharacterAdded:Connect(function()
		task.defer(refresh, plr)
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	refresh(p)
end

Players.PlayerRemoving:Connect(function(plr)
	revoke(plr)
	granting[plr] = nil
end)
