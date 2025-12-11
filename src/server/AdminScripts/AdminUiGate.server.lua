-- ServerScriptService/AdminScripts/AdminUiGate.server.lua

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Permissions = require(game.ServerScriptService.Permissions)

-- ==== Konfig ====
local ADMIN_LEVEL = 253

-- mögliche Namen im ServerStorage
local UI_TEMPLATE_NAMES = {
	"AdminGui",
	"AdminUI",
}

-- Name, den die UI im PlayerGui haben soll
local UI_INSTANCE_NAME = "AdminUI"

-- ==== Template auffinden (robust) ====

local AdminUITemplate

for _, name in ipairs(UI_TEMPLATE_NAMES) do
	AdminUITemplate = ServerStorage:FindFirstChild(name) or ServerStorage:FindFirstChild(name, true)
	if AdminUITemplate and AdminUITemplate:IsA("ScreenGui") then
		break
	end
end

assert(
	AdminUITemplate and AdminUITemplate:IsA("ScreenGui"),
	("ScreenGui-Template nicht gefunden. Erwartet einen von: %s"):format(table.concat(UI_TEMPLATE_NAMES, ", "))
)

-- ==== Helpers ====

local granting: {[Player]: boolean} = {} -- Debounce pro Spieler

local function hasAdmin(plr: Player): boolean
	local ok, res = pcall(Permissions.HasPermission, plr, ADMIN_LEVEL)
	return ok and res == true
end

local function getPlayerGui(plr: Player, timeout: number?)
	local pg = plr:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	pg = plr:WaitForChild("PlayerGui", timeout or 5)
	return pg
end

local function grant(plr: Player)
	if granting[plr] then
		return
	end
	granting[plr] = true

	local pg = getPlayerGui(plr, 5)
	if not pg then
		warn("[AdminUI] PlayerGui nicht gefunden für", plr.Name)
		granting[plr] = nil
		return
	end

	-- alte Instanz entfernen
	local old = pg:FindFirstChild(UI_INSTANCE_NAME)
	if old then
		old:Destroy()
	end

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

	-- Attribut für Client: "Ich bin Admin"
	plr:SetAttribute("IsAdmin", true)
	granting[plr] = nil
end

local function revoke(plr: Player)
	local pg = plr:FindFirstChildOfClass("PlayerGui")
	if pg then
		local g = pg:FindFirstChild(UI_INSTANCE_NAME)
		if g then
			g:Destroy()
		end
	end
	plr:SetAttribute("IsAdmin", false)
end

local function refresh(plr: Player)
	if hasAdmin(plr) then
		grant(plr)
	else
		revoke(plr)
	end
end

-- ==== Hooks ====

Players.PlayerAdded:Connect(function(plr)
	-- beim Join prüfen
	refresh(plr)

	-- optional: beim Respawn erneut prüfen
	plr.CharacterAdded:Connect(function()
		task.defer(refresh, plr)
	end)
end)

-- bereits eingeloggt Spieler (Studio-Test)
for _, p in ipairs(Players:GetPlayers()) do
	refresh(p)
end

Players.PlayerRemoving:Connect(function(plr)
	revoke(plr)
	granting[plr] = nil
end)
