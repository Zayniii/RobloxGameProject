-- ShardService ModuleScript in ServerScriptService

local ShardService = {}

-- Hilfsfunktion: holt das Shards-IntValue beim Player
local function getShardValueObject(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local shards = player:FindFirstChild("Shards")
	return shards
end

-- Shards hinzufügen
function ShardService.AddShards(player, amount)
	if typeof(amount) ~= "number" or amount <= 0 then return end

	local shards = getShardValueObject(player)
	if shards then
		shards.Value = shards.Value + amount
	end
end

-- Shards entfernen (nicht negativ werden lassen)
function ShardService.RemoveShards(player, amount)
	if typeof(amount) ~= "number" or amount <= 0 then return end

	local shards = getShardValueObject(player)
	if shards then
		local newValue = shards.Value - amount
		if newValue < 0 then
			newValue = 0
		end
		shards.Value = newValue
	end
end

-- Aktuelle Shards abfragen
function ShardService.GetShards(player)
	local shards = getShardValueObject(player)
	if shards then
		return shards.Value
	end
	return 0
end

return ShardService
