-- ShardSystem Script in ServerScriptService

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- DataStore für Shards
local shardStore = DataStoreService:GetDataStore("ShardDataStore_V1")
local ODS_SHARDS = DataStoreService:GetOrderedDataStore("Shards_Total_ORD_v1")

local function syncShardsToODS(player)
	local shards = player:FindFirstChild("Shards")
	if not shards then return end

	local value = tonumber(shards.Value) or 0
	pcall(function()
		ODS_SHARDS:SetAsync("shards_" .. player.UserId, math.max(0, value))
	end)
end



-- IntValue "Shards" beim Spieler erstellen
local function createShardValue(player, initialValue)
	local shards = Instance.new("IntValue")
	shards.Name = "Shards"
	shards.Value = initialValue or 0
	shards.Parent = player

	-- 🔹 Immer wenn Shards sich ändern → ODS aktualisieren
	shards.Changed:Connect(function()
		syncShardsToODS(player)
	end)

	-- 🔹 Direkt beim Join den aktuellen Wert in den OrderedDataStore schreiben
	syncShardsToODS(player)

	return shards
end



local function onPlayerAdded(player)
	local shardAmount = 0

	-- Aus DataStore laden
	local success, result = pcall(function()
		return shardStore:GetAsync("player_" .. player.UserId)
	end)

	if success and result ~= nil then
		shardAmount = result
	elseif not success then
		warn("Fehler beim Laden von Shards für " .. player.Name .. ": " .. tostring(result))
	end

	createShardValue(player, shardAmount)
end

local function savePlayerShards(player)
	local shards = player:FindFirstChild("Shards")
	if not shards then return end

	local success, err = pcall(function()
		shardStore:SetAsync("player_" .. player.UserId, shards.Value)
	end)

	if not success then
		warn("Fehler beim Speichern von Shards für " .. player.Name .. ": " .. tostring(err))
	end

	-- 🔹 NEU: auch OrderedDataStore für Leaderboard updaten
	pcall(function()
		ODS_SHARDS:SetAsync("shards_" .. player.UserId, math.max(0, shards.Value))
	end)
end


local function onPlayerRemoving(player)
	savePlayerShards(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerShards(player)
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

----------------------------------------------------------------
-- JEDER SPIELER BEKOMMT JEDE MINUTE 5 SHARDS (Server-seitig)
----------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(60)  -- 60 Sekunden = 1 Minute

		for _, player in ipairs(Players:GetPlayers()) do
			local shards = player:FindFirstChild("Shards")
			if shards then
				shards.Value = shards.Value + 5
			end
		end
	end
end)
