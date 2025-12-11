-- ServerScriptService/GlobalPlaytimeLeaderboard.server.lua

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- == DataStores (wie in Playtime.server.lua) ==
local ODS = DataStoreService:GetOrderedDataStore("Playtime_TotalSeconds_ORD_v1")
local VIS = DataStoreService:GetDataStore("Playtime_Visibility_v1")  -- speichert Hide-Flag: "hide_<userId>" = true/false

-- == GUI-Referenzen ==
local timeBoardModel = workspace:WaitForChild("TimePlayedLeaderboard")
local ScoreBlock     = timeBoardModel:WaitForChild("ScoreBlock")

local leaderboardGui  = ScoreBlock:WaitForChild("Leaderboard") :: SurfaceGui
local scrollingFrame  = leaderboardGui:WaitForChild("UserListScrollingFrame") :: ScrollingFrame
local userTemplate    = scrollingFrame:WaitForChild("UserTemplate") :: Frame
userTemplate.Visible  = false

-- == Farben für Top 3 ==
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local GOLD_COLOR    = Color3.fromRGB(255, 215, 0)
local SILVER_COLOR  = Color3.fromRGB(192, 192, 192)
local BRONZE_COLOR  = Color3.fromRGB(205, 127, 50)

-- == Einstellungen ==
local UPDATE_INTERVAL = 10         -- wie oft ODS neu gelesen wird
local MAX_ROWS        = 30         -- Top 30

-- == Caches ==
local rowsByUserId    : {[number]: Frame} = {}
local nameCache       : {[number]: string} = {}
local thumbCache      : {[number]: string} = {}
local visibilityCache : {[number]: boolean} = {}

local pendingUpdate = false

-- == Helpers ==

-- "pts_12345" -> 12345
local function extractUserIdFromKey(key: string): number?
	if type(key) ~= "string" then return nil end
	local idStr = key:match("pts_(%d+)")
	if idStr then
		return tonumber(idStr)
	end
	return tonumber(key)
end

-- Minuten hübsch anzeigen
local function formatMinutes(totalMinutes: number): string
	return tostring(totalMinutes) .. " min"
	-- oder:
	-- local h = math.floor(totalMinutes / 60)
	-- local m = totalMinutes % 60
	-- if h > 0 then
	--     return string.format("%dh %02dm", h, m)
	-- else
	--     return string.format("%d min", m)
	-- end
end

local function applyRankColor(row: Frame, rank: number)
	local color = DEFAULT_COLOR
	if rank == 1 then
		color = GOLD_COLOR
	elseif rank == 2 then
		color = SILVER_COLOR
	elseif rank == 3 then
		color = BRONZE_COLOR
	end

	for _, name in ipairs({"RankLabel", "UsernameLabel", "PlaytimeLabel"}) do
		local lbl = row:FindFirstChild(name, true)
		if lbl and lbl:IsA("TextLabel") then
			lbl.TextColor3 = color
		end
	end
end

local function getUsername(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local username = ("User %d"):format(userId)
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and result then
		username = result
	end
	nameCache[userId] = username
	return username
end

local function getThumb(userId: number): string?
	if thumbCache[userId] then
		return thumbCache[userId]
	end
	local ok, url, ready = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
	end)
	if ok and ready and url then
		thumbCache[userId] = url
		return url
	end
	return nil
end

-- Sichtbarkeit (MinutesVisible):
-- Online: Attribute (MinutesVisible)
-- Offline: VIS-DataStore ("hide_<userId>" == true => versteckt)
local function getMinutesVisible(userId: number): boolean
	-- Online -> Attribut ist Truth Source
	local plr = Players:GetPlayerByUserId(userId)
	if plr then
		local attr = plr:GetAttribute("MinutesVisible")
		local visible = (attr == nil) or (attr == true)
		visibilityCache[userId] = visible
		return visible
	end

	-- Cache für Offline
	if visibilityCache[userId] ~= nil then
		return visibilityCache[userId]
	end

	local ok, hidden = pcall(function()
		return VIS:GetAsync("hide_" .. tostring(userId))
	end)

	local visible
	if ok then
		visible = (hidden ~= true)
	else
		-- Fehler -> lieber sichtbar als niemand anzeigen
		visible = true
	end

	visibilityCache[userId] = visible
	return visible
end

-- Attribute-Änderungen von Online-Spielern direkt in Cache spiegeln
local function trackPlayerVisibility(plr: Player)
	local function update()
		local attr = plr:GetAttribute("MinutesVisible")
		local visible = (attr == nil) or (attr == true)
		visibilityCache[plr.UserId] = visible
	end
	update()
	plr:GetAttributeChangedSignal("MinutesVisible"):Connect(update)
end

Players.PlayerAdded:Connect(trackPlayerVisibility)
for _, plr in ipairs(Players:GetPlayers()) do
	trackPlayerVisibility(plr)
end

Players.PlayerRemoving:Connect(function(plr)
	-- Cache löschen, damit wir bei späterem Wiedererscheinen frisch laden
	visibilityCache[plr.UserId] = nil
end)

-- == Haupt-Update-Funktion (smooth, inkrementell) ==

local function updateLeaderboard()
	-- ODS lesen: Top N nach Sekunden
	local success, pages = pcall(function()
		return ODS:GetSortedAsync(false, 80)  -- mehr holen, falls viele versteckt sind
	end)

	if not success then
		warn("[GlobalPlaytimeLeaderboard] GetSortedAsync failed:", pages)
		return
	end

	local entries = pages:GetCurrentPage()
	local topUsers = {}  -- { {userId=, seconds=} ... } in Rank-Reihenfolge

	for _, entry in ipairs(entries) do
		local userId = extractUserIdFromKey(entry.key)
		if userId then
			if getMinutesVisible(userId) then
				local totalSeconds = tonumber(entry.value) or 0
				if totalSeconds < 0 then totalSeconds = 0 end
				table.insert(topUsers, {
					userId = userId,
					seconds = totalSeconds,
				})
				if #topUsers >= MAX_ROWS then
					break
				end
			end
		end
	end

	-- Benutzer, die jetzt im Top-Board sind
	local usedUserIds: {[number]: boolean} = {}

	for rank, info in ipairs(topUsers) do
		local userId = info.userId
		local totalMinutes = math.floor(info.seconds / 60)
		local username = getUsername(userId)
		local row = rowsByUserId[userId]

		if not row then
			row = userTemplate:Clone()
			rowsByUserId[userId] = row
			row.Parent = scrollingFrame
		end

		row.Visible     = true
		row.LayoutOrder = rank
		row.Name        = ("UserRow_%02d_%d"):format(rank, userId)

		local rankLabel      = row:FindFirstChild("RankLabel", true)
		local usernameLabel  = row:FindFirstChild("UsernameLabel", true)
		local playtimeLabel  = row:FindFirstChild("PlaytimeLabel", true)
		local profilePicture = row:FindFirstChild("ProfilePicture", true)

		if rankLabel and rankLabel:IsA("TextLabel") then
			rankLabel.Text = ("%d."):format(rank)
		end
		if usernameLabel and usernameLabel:IsA("TextLabel") then
			usernameLabel.Text = username
		end
		if playtimeLabel and playtimeLabel:IsA("TextLabel") then
			playtimeLabel.Text = formatMinutes(totalMinutes)
		end
		if profilePicture and profilePicture:IsA("ImageLabel") then
			local url = getThumb(userId)
			if url then
				profilePicture.Image = url
			end
		end

		applyRankColor(row, rank)
		usedUserIds[userId] = true
	end

	-- Rows von Usern, die nicht mehr im Top-Board sind (oder jetzt versteckt) -> entfernen
	for userId, row in pairs(rowsByUserId) do
		if not usedUserIds[userId] then
			row:Destroy()
			rowsByUserId[userId] = nil
		end
	end
end

local function scheduleUpdate()
	if pendingUpdate then return end
	pendingUpdate = true
	task.spawn(function()
		-- leichtes Debounce, falls mehrere Dinge gleichzeitig passieren
		task.wait(0.5)
		pendingUpdate = false
		updateLeaderboard()
	end)
end

-- Initiales Laden
scheduleUpdate()

-- Regelmäßiges globales Update (Offline + ODS)
task.spawn(function()
	while true do
		task.wait(UPDATE_INTERVAL)
		scheduleUpdate()
	end
end)
