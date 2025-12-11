local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local HttpService        = game:GetService("HttpService")

print("✅ TipJarServer gestartet")

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local remotesFolder    = ReplicatedStorage:WaitForChild("TipJarRemotes")
local getTipJarData    = remotesFolder:WaitForChild("GetTipJarData")
local registerDonation = remotesFolder:WaitForChild("RegisterDonation")
local playTipEffect    = remotesFolder:WaitForChild("PlayTipEffect")
local closeTipJarGui   = remotesFolder:WaitForChild("CloseTipJarGui")
-- 🔹 Neues RemoteEvent für Chat-Messages
local tipJarChatEvent = remotesFolder:FindFirstChild("TipJarChatMessage")
if not tipJarChatEvent then
	tipJarChatEvent = Instance.new("RemoteEvent")
	tipJarChatEvent.Name = "TipJarChatMessage"
	tipJarChatEvent.Parent = remotesFolder
end


----------------------------------------------------------------
-- DataStore für Donated / Raised
----------------------------------------------------------------
local donationStore = DataStoreService:GetDataStore("TipJarMainStore")

local ODS_DONATED = DataStoreService:GetOrderedDataStore("TipJar_Donated_ORD_v1")
local ODS_RAISED  = DataStoreService:GetOrderedDataStore("TipJar_Raised_ORD_v1")

local function syncDonatedAndRaisedToODS(player)
	local stats = player:FindFirstChild("TipJarStats")
	if not stats then return end

	local donatedVal = 0
	local raisedVal  = 0

	local donated = stats:FindFirstChild("Donated")
	if donated then
		donatedVal = tonumber(donated.Value) or 0
	end

	local raised = stats:FindFirstChild("Raised")
	if raised then
		raisedVal = tonumber(raised.Value) or 0
	end

	-- 🔹 Donated ODS
	pcall(function()
		ODS_DONATED:SetAsync("donated_" .. player.UserId, math.max(0, donatedVal))
	end)

	-- 🔹 Raised ODS
	pcall(function()
		ODS_RAISED:SetAsync("raised_" .. player.UserId, math.max(0, raisedVal))
	end)
end

local function hookValueToODS(valueObj, player)
	if not valueObj:GetAttribute("ODS_Hooked") then
		valueObj:SetAttribute("ODS_Hooked", true)
		valueObj.Changed:Connect(function()
			syncDonatedAndRaisedToODS(player)
		end)
	end
end



local function addToODS(ods, keyPrefix, userId, delta)
	delta = tonumber(delta) or 0
	if delta <= 0 then return end

	local key = keyPrefix .. tostring(userId)
	pcall(function()
		ods:UpdateAsync(key, function(old)
			old = tonumber(old) or 0
			return old + delta
		end)
	end)
end


----------------------------------------------------------------
-- Caches
----------------------------------------------------------------
-- UserId -> { universeId1, universeId2, ... }
local cachedUniversesByUserId   = {}
-- UniverseId -> { passes... }
local cachedPassesByUniverseId  = {}

----------------------------------------------------------------
-- Hilfsfunktionen: HTTP
----------------------------------------------------------------
local TextChatService = game:GetService("TextChatService")

-- Farben: benutze hier einfach die Farben, die du auch in deinen UIGradients genommen hast
local ROBUX_COLOR = "rgb(255,226,62)"   -- gold (passt zu deinem Value-Gradient)
local TEXT_COLOR  = "rgb(0,255,30)"    -- dein Grün: 0,255,30

local robuxSymbol = utf8.char(0xE002)

local function postTipChatMessage(donorName, ownerName, amount)
	amount = tonumber(amount)
	if not amount or amount <= 0 then return end

	local message = string.format(
		'<font color="%s">%s donated </font>' ..
			'<font color="%s">%d%s</font>' ..
			'<font color="%s"> to %s.</font>',
		TEXT_COLOR, donorName,
		ROBUX_COLOR, amount, robuxSymbol,
		TEXT_COLOR, ownerName
	)

	-- 🔹 Robust: TextChannels holen
	local channels = TextChatService.TextChannels
	if not channels then
		warn("[TipJar] TextChatService.TextChannels ist nil. Nutzt dein Place noch Legacy Chat? (Game Settings > Chat > Chat Version = TextChatService)")
		return
	end

	-- 🔹 Versuche zuerst bekannte Standard-Namen
	local channel =
		channels:FindFirstChild("RBXGeneral") or
		channels:FindFirstChild("All") or
		channels:FindFirstChild("General")

	-- 🔹 Wenn keiner der Standardnamen existiert, nimm einfach den ersten TextChannel
	if not channel then
		local foundAny = nil
		for _, ch in ipairs(channels:GetChildren()) do
			if ch:IsA("TextChannel") then
				foundAny = ch
				break
			end
		end

		if not foundAny then
			warn("[TipJar] Kein TextChannel gefunden. Verfügbare Children von TextChatService.TextChannels:")
			for _, ch in ipairs(channels:GetChildren()) do
				print(" -", ch.Name, ch.ClassName)
			end
			return
		end

		channel = foundAny
		print("[TipJar] Fallback-Channel für SystemMessage benutzt:", channel.Name)
	end

	channel:DisplaySystemMessage(message)
end





-- Holt ALLE öffentlichen Games (Universes) eines Users über RoProxy
local function fetchUserUniverses(userId)
	if cachedUniversesByUserId[userId] then
		return cachedUniversesByUserId[userId]
	end

	local universes = {}
	local cursor = nil

	while true do
		local baseUrl = ("https://games.roproxy.com/v2/users/%d/games"):format(userId)
		local query = "sortOrder=Asc&limit=50"
		if cursor then
			query = query .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local url = baseUrl .. "?" .. query
		print("[TipJar] GET (user games):", url)

		local ok, body = pcall(function()
			return HttpService:GetAsync(url)
		end)

		if not ok then
			warn("[TipJar] Fehler beim User-Games-Request:", body)
			break
		end

		if not body or body == "" then
			break
		end

		local decoded
		local ok2, err = pcall(function()
			decoded = HttpService:JSONDecode(body)
		end)

		if not ok2 or not decoded then
			warn("[TipJar] JSON-Fehler beim User-Games-Request:", err)
			break
		end

		local gamesList = decoded.data or decoded.games or decoded

		if type(gamesList) ~= "table" or #gamesList == 0 then
			break
		end

		for _, gameInfo in ipairs(gamesList) do
			local universeId = gameInfo.universeId or gameInfo.id
			local isActive   = (gameInfo.isActive == nil) or gameInfo.isActive
			local isPublic   = (gameInfo.isPublic == nil) or gameInfo.isPublic

			if universeId and isActive and isPublic then
				table.insert(universes, universeId)
			end
		end

		local nextCursor = decoded.nextPageCursor
		if not nextCursor or nextCursor == "" then
			break
		end
		cursor = nextCursor
	end

	cachedUniversesByUserId[userId] = universes
	print(("[TipJar] %d Universes für User %d gefunden"):format(#universes, userId))

	return universes
end

-- Holt ALLE GamePässe eines Universes über RoProxy
local function fetchUniverseGamePasses(universeId)
	if cachedPassesByUniverseId[universeId] then
		return cachedPassesByUniverseId[universeId]
	end

	local baseUrl = ("https://apis.roproxy.com/game-passes/v1/universes/%d/game-passes"):format(universeId)

	local passes = {}
	local cursor = nil

	while true do
		local query = "passView=Full&pageSize=100"
		if cursor then
			query = query .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local url = baseUrl .. "?" .. query
		print("[TipJar] GET (universe passes):", url)

		local ok, body = pcall(function()
			return HttpService:GetAsync(url)
		end)

		if not ok then
			warn("[TipJar] Fehler beim GamePass-Request:", body)
			break
		end

		if not body or body == "" then
			break
		end

		local decoded
		local ok2, err = pcall(function()
			decoded = HttpService:JSONDecode(body)
		end)

		if not ok2 or not decoded then
			warn("[TipJar] JSON-Fehler beim GamePass-Request:", err)
			break
		end

		local items = decoded.gamePasses or decoded.data or decoded

		if type(items) ~= "table" or #items == 0 then
			break
		end

		for _, gp in ipairs(items) do
			local id    = gp.id or gp.gamePassId
			local name  = gp.name or gp.displayName or ("Pass " .. tostring(id))

			local price = 0
			if gp.product and gp.product.price then
				price = tonumber(gp.product.price) or 0
			elseif gp.price then
				price = tonumber(gp.price) or 0
			end

			local image = ""
			if gp.displayIconImageAssetId then
				image = "rbxassetid://" .. tostring(gp.displayIconImageAssetId)
			end

			-- Nur Pässe mit Preis > 0 in die Liste aufnehmen
			if id and price > 0 then
				table.insert(passes, {
					id    = id,
					name  = name,
					price = price,
					image = image,
				})
			end
		end

		local nextCursor = decoded.nextPageCursor
		if not nextCursor or nextCursor == "" then
			break
		end
		cursor = nextCursor
	end

	table.sort(passes, function(a, b)
		return (a.price or 0) < (b.price or 0)
	end)

	print(("[TipJar] %d GamePässe für Universe %d geladen"):format(#passes, universeId))

	cachedPassesByUniverseId[universeId] = passes
	return passes
end

-- Alle Universes eines Users -> alle Pässe zusammenführen
local function getPassListForOwner(ownerUserId)
	local universes = fetchUserUniverses(ownerUserId)

	if not universes or #universes == 0 then
		warn("[TipJar] User", ownerUserId, "hat keine öffentlichen Games – nutze game.GameId als Universe")
		universes = { game.GameId }
	end

	local combinedPasses = {}
	local seenPassIds = {}

	for _, universeId in ipairs(universes) do
		local list = fetchUniverseGamePasses(universeId)
		if list and #list > 0 then
			for _, p in ipairs(list) do
				local price = tonumber(p.price) or 0
				if p.id and price > 0 and not seenPassIds[p.id] then
					table.insert(combinedPasses, p)
					seenPassIds[p.id] = true
				end
			end
		end
	end

	if #combinedPasses == 0 then
		warn("[TipJar] Keine GamePässe in allen Universes gefunden – nutze einfache Fallback-Liste")
		combinedPasses = {
			{ id = 1234567890, name = "Donate 10",  price = 10,  image = "" },
			{ id = 2345678901, name = "Donate 50",  price = 50,  image = "" },
			{ id = 3456789012, name = "Donate 100", price = 100, image = "" },
		}
	end

	table.sort(combinedPasses, function(a, b)
		return (a.price or 0) < (b.price or 0)
	end)

	print(("[TipJar] %d kombinierte GamePässe für User %d"):format(#combinedPasses, ownerUserId))

	return combinedPasses
end

----------------------------------------------------------------
-- "Versteckte" Stats (KEIN leaderstats → kein Leaderboard)
----------------------------------------------------------------

-- Statt leaderstats verwenden wir "TipJarStats"
local function getOrCreateTipJarStats(player)
	local stats = player:FindFirstChild("TipJarStats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "TipJarStats"
		stats.Parent = player
	end

	local donated = stats:FindFirstChild("Donated")
	if not donated then
		donated = Instance.new("IntValue")
		donated.Name = "Donated"
		donated.Value = 0
		donated.Parent = stats
	end

	local raised = stats:FindFirstChild("Raised")
	if not raised then
		raised = Instance.new("IntValue")
		raised.Name = "Raised"
		raised.Value = 0
		raised.Parent = stats
	end

	-- 🔹 NEU: egal, wer Donated/Raised ändert (Donation, Admin, Script) → ODS updaten
	hookValueToODS(donated, player)
	hookValueToODS(raised, player)

	return stats
end


local function loadPlayerData(player)
	local stats = getOrCreateTipJarStats(player)
	local donated = stats:FindFirstChild("Donated")
	local raised  = stats:FindFirstChild("Raised")

	local success, data = pcall(function()
		return donationStore:GetAsync(player.UserId)
	end)

	if success and data then
		local decoded
		local ok, err = pcall(function()
			decoded = HttpService:JSONDecode(data)
		end)

		if ok and type(decoded) == "table" then
			donated.Value = decoded[1] or 0
			raised.Value  = decoded[2] or 0
			print(("[TipJar] Daten geladen für %s: Donated=%d, Raised=%d"):format(
				player.Name, donated.Value, raised.Value
				))
		else
			warn("[TipJar] Konnte Daten nicht dekodieren für", player.Name, err)
		end
	elseif not success then
		warn("[TipJar] Fehler beim Laden von DataStore für", player.Name, data)
	end
end

local function savePlayerData(player)
	local stats = player:FindFirstChild("TipJarStats")
	if not stats then return end

	local donated = stats:FindFirstChild("Donated")
	local raised  = stats:FindFirstChild("Raised")

	local toSave = {
		donated and donated.Value or 0,
		raised  and raised.Value  or 0,
	}

	local success, err = pcall(function()
		local encoded = HttpService:JSONEncode(toSave)
		donationStore:SetAsync(player.UserId, encoded)
	end)

	if success then
		print("[TipJar] Daten gespeichert für", player.Name)
	else
		warn("[TipJar] Fehler beim Speichern für", player.Name, err)
	end
end

----------------------------------------------------------------
-- Owner für TipJar-Tools setzen (StarterPack etc.) + Unequip-Hook
----------------------------------------------------------------
local function assignOwnerForPlayerTools(player)
	local function processContainer(container)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") and tool:FindFirstChild("Owner") then
				local ownerValue = tool.Owner
				if ownerValue.Value ~= player then
					ownerValue.Value = player
					if tool:GetAttribute("SkinId") == nil then
						tool:SetAttribute("SkinId", "Standard")
					end
					print("🧾 Owner gesetzt für Tool", tool.Name, "->", player.Name)
				end

				-- Unequipped-Hook: wenn der Owner das Tool wegpackt -> GUI schließen
				if not tool:GetAttribute("TipJarUnequipHooked") then
					tool:SetAttribute("TipJarUnequipHooked", true)

					tool.Unequipped:Connect(function()
						if ownerValue.Value then
							print("🧯 TipJar von", ownerValue.Value.Name, "unequipped -> CloseTipJarGui an Clients")
							closeTipJarGui:FireAllClients(ownerValue.Value.UserId)
						end
					end)
				end
			end
		end
	end

	processContainer(player:FindFirstChild("Backpack"))
	processContainer(player.Character)
end

----------------------------------------------------------------
-- PlayerAdded / PlayerRemoving
----------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	print("👤 PlayerAdded:", player.Name)
	getOrCreateTipJarStats(player)
	loadPlayerData(player)

	-- 🔹 Donated & Raised einmalig in die OrderedDataStores schreiben
	syncDonatedAndRaisedToODS(player)

	assignOwnerForPlayerTools(player)

	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		assignOwnerForPlayerTools(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- 🔹 HIER wird der aktuelle Wert dauerhaft gespeichert
	savePlayerData(player)

	-- optional: letzten Stand auch nochmal in die OrderedDataStores spiegeln
	syncDonatedAndRaisedToODS(player)
end)



----------------------------------------------------------------
-- GetTipJarData: Daten fürs GUI
----------------------------------------------------------------
getTipJarData.OnServerInvoke = function(callingPlayer, ownerUserId)
	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	local ownerName = ownerPlayer and ownerPlayer.Name or ("User_" .. ownerUserId)

	local raised = 0
	local donated = 0

	if ownerPlayer then
		local stats = ownerPlayer:FindFirstChild("TipJarStats")
		if stats then
			local r = stats:FindFirstChild("Raised")
			if r then
				raised = r.Value
			end

			local d = stats:FindFirstChild("Donated")
			if d then
				donated = d.Value
			end
		end
	end

	local passes = getPassListForOwner(ownerUserId)

	print(("📡 GetTipJarData: %s öffnet TipJar von %s (%d Pässe)"):format(
		callingPlayer.Name, ownerName, #passes
		))

	return {
		ownerUserId = ownerUserId,
		ownerName   = ownerName,
		-- beide Werte gehören jetzt zum OWNER
		raised      = raised,
		donatedByMe = donated,
		passes      = passes,
	}
end

----------------------------------------------------------------
-- Donations registrieren + Effekte
----------------------------------------------------------------
local function getTier(amount)
	if amount >= 1_000_000 then
		return 4
	elseif amount >= 10_000 then
		return 3
	elseif amount >= 1_000 then
		return 2
	else
		return 1
	end
end

registerDonation.OnServerEvent:Connect(function(donorPlayer, ownerUserId, amount)
	amount = tonumber(amount)
	if not amount or amount <= 0 then return end

	-- Donated beim Spender erhöhen
	do
		local stats = donorPlayer:FindFirstChild("TipJarStats") or getOrCreateTipJarStats(donorPlayer)
		local donatedVal = stats:FindFirstChild("Donated")
		if donatedVal then
			donatedVal.Value += amount
		end
	end

	-- Raised beim Owner erhöhen
	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	if ownerPlayer then
		local stats = ownerPlayer:FindFirstChild("TipJarStats") or getOrCreateTipJarStats(ownerPlayer)
		local raisedVal = stats:FindFirstChild("Raised")
		if raisedVal then
			raisedVal.Value += amount
		end
	end

	addToODS(ODS_DONATED, "donated_", donorPlayer.UserId, amount)
	addToODS(ODS_RAISED,  "raised_",  ownerUserId,      amount)

	print(("💸 %s spendet %d R$ an UserId %d"):format(donorPlayer.Name, amount, ownerUserId))

	local tier = getTier(amount)
	-- 🔹 Donator-Name zusätzlich mitsenden (für Popup-Animation)
	playTipEffect:FireAllClients(ownerUserId, amount, tier, donorPlayer.Name)

	-- 🔹 Chat-Nachricht an alle Clients schicken
	if ownerPlayer then
		tipJarChatEvent:FireAllClients(donorPlayer.Name, ownerPlayer.Name, amount)
	end

end)

