local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ODS = DataStoreService:GetOrderedDataStore("Shards_Total_ORD_v1")

-- GUI
local shardBoardModel = workspace:WaitForChild("ShardsLeaderboard")
local ScoreBlock      = shardBoardModel:WaitForChild("ScoreBlock")

local leaderboardGui  = ScoreBlock:WaitForChild("Leaderboard") :: SurfaceGui
local scrollingFrame  = leaderboardGui:WaitForChild("UserListScrollingFrame") :: ScrollingFrame
local userTemplate    = scrollingFrame:WaitForChild("UserTemplate") :: Frame
userTemplate.Visible  = false

-- Farben
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local GOLD_COLOR    = Color3.fromRGB(255, 215, 0)
local SILVER_COLOR  = Color3.fromRGB(192, 192, 192)
local BRONZE_COLOR  = Color3.fromRGB(205, 127, 50)

local UPDATE_INTERVAL = 10
local MAX_ROWS        = 30

local rowsByUserId : {[number]: Frame} = {}
local nameCache    : {[number]: string} = {}
local thumbCache   : {[number]: string} = {}

local function extractUserIdFromKey(key: string): number?
	if type(key) ~= "string" then return nil end
	local idStr = key:match("shards_(%d+)")
	if idStr then
		return tonumber(idStr)
	end
	return tonumber(key)
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

local function updateLeaderboard()
	local success, pages = pcall(function()
		return ODS:GetSortedAsync(false, 80)
	end)

	if not success then
		warn("[GlobalShardLeaderboard] GetSortedAsync failed:", pages)
		return
	end

	local entries = pages:GetCurrentPage()
	local topUsers = {}

	for _, entry in ipairs(entries) do
		local userId = extractUserIdFromKey(entry.key)
		if userId then
			local shards = tonumber(entry.value) or 0
			if shards < 0 then shards = 0 end
			table.insert(topUsers, { userId = userId, shards = shards })
			if #topUsers >= MAX_ROWS then
				break
			end
		end
	end

	local usedUserIds : {[number]: boolean} = {}

	for rank, info in ipairs(topUsers) do
		local userId = info.userId
		local shards = info.shards
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
		local valueLabel     = row:FindFirstChild("PlaytimeLabel", true)
		local profilePicture = row:FindFirstChild("ProfilePicture", true)

		if rankLabel and rankLabel:IsA("TextLabel") then
			rankLabel.Text = ("%d."):format(rank)
		end
		if usernameLabel and usernameLabel:IsA("TextLabel") then
			usernameLabel.Text = username
		end
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = tostring(shards)  -- nur Zahl
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

	for userId, row in pairs(rowsByUserId) do
		if not usedUserIds[userId] then
			row:Destroy()
			rowsByUserId[userId] = nil
		end
	end
end

local function scheduleUpdate()
	while true do
		task.wait(UPDATE_INTERVAL)
		updateLeaderboard()
	end
end

updateLeaderboard()
task.spawn(scheduleUpdate)
