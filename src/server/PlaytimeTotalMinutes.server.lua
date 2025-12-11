-- ServerScriptService/Playtime.server.lua

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

-- ODS speichert GESAMT-SEKUNDEN; Key muss zu deinem bisherigen Save passen
local ODS = DataStoreService:GetOrderedDataStore("Playtime_TotalSeconds_ORD_v1")
local VIS = DataStoreService:GetDataStore("Playtime_Visibility_v1") -- speichert Hide-Flag

local STAT_NAME  = "Minuten"  -- EINZIGES Leaderstat, IntValue
local SAVE_CHUNK = 30         -- alle ~30s persistieren

-- RemoteEvent für den Toggle (Client -> Server)
local ToggleEvt = ReplicatedStorage:FindFirstChild("ToggleMinutesVisible")
if not ToggleEvt then
	ToggleEvt = Instance.new("RemoteEvent")
	ToggleEvt.Name = "ToggleMinutesVisible"
	ToggleEvt.Parent = ReplicatedStorage
end

-- Admin-Event für Playtime-Änderungen (Server <-> Server)
local AdminPlaytimeDelta = ReplicatedStorage:FindFirstChild("AdminPlaytimeDelta")
if not AdminPlaytimeDelta then
	AdminPlaytimeDelta = Instance.new("BindableEvent")
	AdminPlaytimeDelta.Name = "AdminPlaytimeDelta"
	AdminPlaytimeDelta.Parent = ReplicatedStorage
end


-- Session-State
type Session = {
	lastClock: number,
	totalSeconds: number,
	unsavedSeconds: number,
	statValue: IntValue?, -- vorher: IntValue?
	saving: boolean,
}



local sessions: {[Player]: Session} = {}

local function keyFor(userId: number): string
	return ("pts_%d"):format(userId)
end

local function ensureLeaderstatsFolder(plr: Player): Folder
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = plr
	end
	return ls
end



-- EIN StringValue "Minuten" (nur eine Spalte, kann "-" anzeigen)
local STAT_NAME = "Minuten"  -- Leaderstat für Sortierung (IntValue)

local function ensureMinutesStat(plr: Player): IntValue
	local ls = ensureLeaderstatsFolder(plr)
	local iv = ls:FindFirstChild(STAT_NAME)
	if not iv then
		iv = Instance.new("IntValue")
		iv.Name = STAT_NAME
		iv.Value = 0
		iv.Parent = ls
	end
	return iv :: IntValue
end





-- StringValue für die Text-Anzeige (z.B. "-" statt "-1")
local function ensureMinutesDisplay(plr: Player): StringValue
	local ls = ensureLeaderstatsFolder(plr)
	local sv = ls:FindFirstChild("MinutenText")
	if not sv then
		sv = Instance.new("StringValue")
		sv.Name = "MinutenText"
		sv.Value = "0"
		sv.Parent = ls
	end
	return sv :: StringValue
end


local function loadTotalSeconds(userId: number): number
	for i = 1, 3 do
		local ok, v = pcall(function()
			return ODS:GetAsync(keyFor(userId))
		end)
		if ok then return tonumber(v) or 0 end
		task.wait(0.5 * i)
	end
	warn(("[Playtime] Load failed for %d; default 0"):format(userId))
	return 0
end

local function addSeconds(userId: number, addSec: number): boolean
	if addSec <= 0 then return true end
	for i = 1, 3 do
		local ok = pcall(function()
			ODS:UpdateAsync(keyFor(userId), function(old)
				old = tonumber(old) or 0
				return old + addSec
			end)
		end)
		if ok then return true end
		task.wait(0.5 * i)
	end
	return false
end

-- optional: Wert im ODS sofort sichtbar halten (Leaderboards ziehen dann schneller nach)
local function setSeconds(userId: number, seconds: number)
	pcall(function()
		ODS:SetAsync(keyFor(userId), math.max(0, math.floor(seconds)))
	end)
end

-- Anzeige + Sortierwert (nur IntValue "Minuten")
local function updateDisplay(plr: Player, s: Session)
	if not s.statValue or not s.statValue.Parent then
		s.statValue = ensureMinutesStat(plr)
	end

	-- echte Minuten (immer korrekt, egal ob sichtbar oder nicht)
	local rawMinutes = math.floor((s.totalSeconds + s.unsavedSeconds) / 60)

	-- Sichtbarkeit nur für das öffentliche Leaderboard
	local visibleAttr = plr:GetAttribute("MinutesVisible")
	local visible = (visibleAttr == nil) or (visibleAttr == true)

	local shownMinutes = rawMinutes
	if not visible then
		-- im normalen Leaderboard 0 anzeigen
		shownMinutes = 0
	end

	-- das, was alle Spieler sehen (Leaderstat)
	s.statValue.Value = shownMinutes

	-- das, was NUR der Admin benutzt: immer echte Minuten
	plr:SetAttribute("PlaytimeMinutesTotal", rawMinutes)
end



-- Admin kann Playtime (in Minuten) verändern
AdminPlaytimeDelta.Event:Connect(function(userId: number, deltaMinutes: number)
	deltaMinutes = tonumber(deltaMinutes) or 0
	if deltaMinutes == 0 then return end

	-- Minuten → Sekunden
	local addSec = math.floor(deltaMinutes) * 60
	if addSec == 0 then return end

	local plr = Players:GetPlayerByUserId(userId)

	if plr then
		local s = sessions[plr]
		if not s then
			-- Falls aus irgendeinem Grund keine Session existiert, nur DataStore updaten
			local current = loadTotalSeconds(userId)
			local newTotal = current + addSec
			if newTotal < 0 then newTotal = 0 end
			setSeconds(userId, newTotal)
			return
		end

		-- Aktuelle Sekunden (inkl. unsavedSeconds) + Delta
		local currentTotal = s.totalSeconds + s.unsavedSeconds
		local newTotal = currentTotal + addSec
		if newTotal < 0 then newTotal = 0 end

		-- Session anpassen
		s.totalSeconds = newTotal
		s.unsavedSeconds = 0

		-- Sofort DataStore und Anzeige aktualisieren
		setSeconds(userId, s.totalSeconds)
		updateDisplay(plr, s)
	else
		-- Spieler offline → nur DataStore anpassen
		local current = loadTotalSeconds(userId)
		local newTotal = current + addSec
		if newTotal < 0 then newTotal = 0 end
		setSeconds(userId, newTotal)
	end
end)




local function flush(plr: Player, s: Session)
	if not s or s.saving then return end
	local toSave = math.floor(s.unsavedSeconds)
	if toSave <= 0 then return end

	s.saving = true
	if addSeconds(plr.UserId, toSave) then
		s.totalSeconds += toSave
		s.unsavedSeconds -= toSave
		setSeconds(plr.UserId, s.totalSeconds)
	end
	s.saving = false
	updateDisplay(plr, s)
end

local function loadVisibility(userId: number): boolean
	-- true = sichtbar (Minuten zeigen), false = versteckt
	local ok, hidden = pcall(function()
		return VIS:GetAsync("hide_" .. tostring(userId))
	end)
	if ok then
		return hidden ~= true
	end
	-- Fallback: sichtbar
	return true
end

Players.PlayerAdded:Connect(function(plr)
	-- Sichtbarkeit persistent laden
	local visible = loadVisibility(plr.UserId)

	-- Attribute setzen (beide, für Kompatibilität)
	plr:SetAttribute("MinutesVisible", visible)
	plr:SetAttribute("HideMinutes", not visible)

	-- Leaderstat anlegen
	local iv = ensureMinutesStat(plr)
	local loaded = loadTotalSeconds(plr.UserId)

	local s: Session = {
		lastClock = os.clock(),
		totalSeconds = loaded,
		unsavedSeconds = 0,
		statValue = iv, -- ist jetzt StringValue
		saving = false,
	}
	sessions[plr] = s

	-- Initialanzeige
	updateDisplay(plr, s)

	-- Sekundensammler / Autosave
	task.spawn(function()
		while sessions[plr] == s do
			local now = os.clock()
			local dt  = now - s.lastClock
			s.lastClock = now

			s.unsavedSeconds += dt
			updateDisplay(plr, s)

			if s.unsavedSeconds >= SAVE_CHUNK then
				flush(plr, s)
			end
			task.wait(1)
		end
	end)

	-- Attribute-Änderung -> Anzeige anpassen
	local function onAttr()
		updateDisplay(plr, s)
	end
	plr:GetAttributeChangedSignal("MinutesVisible"):Connect(onAttr)
	plr:GetAttributeChangedSignal("HideMinutes"):Connect(onAttr)
end)

Players.PlayerRemoving:Connect(function(plr)
	local s = sessions[plr]
	if s then
		flush(plr, s)
		sessions[plr] = nil
	end
end)

game:BindToClose(function()
	for plr, s in pairs(sessions) do
		flush(plr, s)
	end
end)

-- Toggle vom Client: Sichtbarkeit speichern
ToggleEvt.OnServerEvent:Connect(function(plr, wantVisible: boolean)
	local visible = wantVisible == true
	plr:SetAttribute("MinutesVisible", visible)
	plr:SetAttribute("HideMinutes", not visible)

	pcall(function()
		VIS:SetAsync("hide_" .. plr.UserId, not visible)
	end)

	local s = sessions[plr]
	if s then
		updateDisplay(plr, s)
	end
end)