	-- ServerScriptService/AdminCommandHandler.server.lua

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local DataStoreService = game:GetService("DataStoreService")
	local Permissions = require(game.ServerScriptService.Permissions)

	-- RemoteEvent in ReplicatedStorage: "AdminCommand"
	local AdminCommand: RemoteEvent = ReplicatedStorage:WaitForChild("AdminCommand")

	-- ganz oben bei den lokalen Tabellen:
	local flyAllowed: {[number]: boolean} = {}  -- [userId] = true/false

	local FlyToggleEvent = ReplicatedStorage:FindFirstChild("AdminFlyToggle")
	if not FlyToggleEvent then
		FlyToggleEvent = Instance.new("RemoteEvent")
		FlyToggleEvent.Name = "AdminFlyToggle"
		FlyToggleEvent.Parent = ReplicatedStorage
	end

-- NEU: zentrale Funktion zum Setzen des Fly-Status
local function setFlyAllowed(player: Player, allowed: boolean)
	local uid = player.UserId
	flyAllowed[uid] = allowed and true or false
	FlyToggleEvent:FireClient(player, flyAllowed[uid])
end


	-- ===== Konfiguration =====
	local BAN_DS = DataStoreService:GetDataStore("Bans_v1") -- DataStore name
	local ADMIN_LEVEL = Permissions.Level["admin"] or 253

	-- Rollen, die nie gekickt/gebanned werden dürfen:
	local PROTECTED = {
		["owner"] = true,
		["head developer"] = true,
		["admin"] = true,
		["manager"] = true,
	}

	-- sehr einfaches Anti-Spam (Cooldown pro Admin)
	local _lastCall: {[Player]: number} = {}
	local function throttled(plr: Player): boolean
		local now = os.clock()
		local t = _lastCall[plr] or 0
		if now - t < 0.2 then return true end
		_lastCall[plr] = now
		return false
	end

	-- ===== Helpers =====
	local function getHumanoid(model: Model?)
		return model and model:FindFirstChildOfClass("Humanoid")
	end

	local function getHRP(model: Model?)
		return model and model:FindFirstChild("HumanoidRootPart")
	end

	local function banKey(userId: number) return "ban_" .. tostring(userId) end

	local function setBan(userId: number, info: table)
		pcall(function() BAN_DS:SetAsync(banKey(userId), info) end)
	end

	local function clearBan(userId: number)
		pcall(function() BAN_DS:RemoveAsync(banKey(userId)) end)
	end

	local function getBan(userId: number)
		local ok, v = pcall(function() return BAN_DS:GetAsync(banKey(userId)) end)
		if not ok then return nil end
		return v
	end

	local function isBanned(userId: number)
		local info = getBan(userId)
		if not info then return false, nil end
		if info.expiresAt and os.time() >= info.expiresAt then
			clearBan(userId)
			return false, nil
		end
		return info.banned == true, info
	end

	-- Nur niedrigere Ränge dürfen betroffen werden (Selbst-Aktionen erlaubt)
	local function canAffect(caller: Player, target: Player): boolean
		if caller == target then return true end
		return Permissions.GetLevel(caller) > Permissions.GetLevel(target)
	end

	-- Name/DisplayName/Username → UserId (online bevorzugt, sonst Roblox-Lookup)
	local function resolveUserId(nameOrId: any): number?
		if typeof(nameOrId) == "number" then
			return nameOrId
		end
		if typeof(nameOrId) ~= "string" then
			return nil
		end
		local q = nameOrId:lower()

		-- Online: exakter Match auf Name ODER DisplayName
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Name:lower() == q or p.DisplayName:lower() == q then
				return p.UserId
			end
		end

		-- Offline: Roblox-Username → UserId
		local ok, uid = pcall(function()
			return Players:GetUserIdFromNameAsync(nameOrId)
		end)
		if ok then return uid end
		return nil
	end

	-- Gebannte beim Join sofort kicken
	Players.PlayerAdded:Connect(function(plr)
		local banned, info = isBanned(plr.UserId)
		if banned then
			local msg = "You are banned from this experience."
			if info and info.reason and info.reason ~= "" then
				msg = msg .. "\nReason: " .. tostring(info.reason)
			end
			plr:Kick(msg)
		end
	end)
Players.PlayerAdded:Connect(function(plr)
	-- Standard: erst mal kein Fly
	flyAllowed[plr.UserId] = false

	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				-- Bei Tod: Fly AUS, wie im Admin-Panel
				if flyAllowed[plr.UserId] then
					setFlyAllowed(plr, false)
					print(("[AdminFly] Auto-Fly OFF (death) for %s"):format(plr.Name))
				end
			end)
		end

		-- Optional: beim Spawn dem Client den aktuellen Status schicken
		local allowed = flyAllowed[plr.UserId] == true
		FlyToggleEvent:FireClient(plr, allowed)
	end)
end)

-- Client -> Server: "RequestStatus" abfangen
FlyToggleEvent.OnServerEvent:Connect(function(player, action)
	if action == "RequestStatus" then
		local allowed = flyAllowed[player.UserId] == true
		FlyToggleEvent:FireClient(player, allowed)
	end
end)


	-- ===== Zentrale Admin-Remote =====
	AdminCommand.OnServerEvent:Connect(function(caller: Player, cmd: string, targetUserId: any, payload: any)
		if throttled(caller) then return end
		if typeof(cmd) ~= "string" then return end
		if not Permissions.HasPermission(caller, ADMIN_LEVEL) then
			warn(("[Admin] %s tried '%s' without permission"):format(caller.Name, cmd))
			return
		end

		-- ------ UNBAN (per UserId oder Name/DisplayName/Username) ------
		if cmd == "Unban" then
			local uid = (typeof(targetUserId) == "number" and targetUserId ~= 0) and targetUserId or nil
			if not uid and payload and typeof(payload) == "table" and typeof(payload.name) == "string" then
				uid = resolveUserId(payload.name)
			end
			if not uid then
				warn(("[Admin] %s tried Unban but could not resolve '%s'"):format(caller.Name, tostring(payload and payload.name or targetUserId)))
				return
			end
			clearBan(uid)
			print(("[Admin] %s unbanned userId=%d"):format(caller.Name, uid))
			return
		end

		-- Ab hier: Kommandos gegen einen (meist) anwesenden Spieler
		local target: Player? = nil
		if typeof(targetUserId) == "number" and targetUserId ~= 0 then
			target = Players:GetPlayerByUserId(targetUserId)
		end

		-- Offline-BAN erlauben (per UserId), falls Ziel nicht online ist
		if cmd == "Ban" and not target then
			if typeof(targetUserId) == "number" and targetUserId > 0 then
				local info = {
					banned = true,
					by = caller.UserId,
					reason = (payload and payload.reason) or "",
					ts = os.time(),
					expiresAt = nil, -- für Temp-Ban später setzen
				}
				setBan(targetUserId, info)
				print(("[Admin] %s offline-banned userId=%d"):format(caller.Name, targetUserId))
			end
			return
		end

		-- Wenn weiterhin kein Ziel vorhanden ist, abbrechen
		if not target then return end

		-- Schutz vor Rang-Missbrauch
		if (cmd == "Kick" or cmd == "Ban") then
			local rank = (Permissions.GetRank(target) or "user"):lower()
			if PROTECTED[rank] then
				warn(("[Admin] %s tried %s on PROTECTED '%s' (%s)"):format(caller.Name, cmd, rank, target.Name))
				return
			end
		end
		if not canAffect(caller, target) then
			warn(("[Admin] %s not allowed to '%s' %s"):format(caller.Name, cmd, target.Name))
			return
		end

		-- ===== COMMANDS =====
		local lower = cmd:lower()

		if lower == "kill" then
			-- NEU (empfohlen)
			local hum = getHumanoid(target.Character)
			if hum then
				hum.Health = 0
				hum:ChangeState(Enum.HumanoidStateType.Dead) -- optional, sauberer State
			else
				-- Kein Humanoid? Erzwinge einen Respawn statt BreakJoints
				if target and target.LoadCharacter then
					pcall(function() target:LoadCharacter() end)
				end
			end

			print(("[Admin] %s killed %s"):format(caller.Name, target.Name))

		elseif lower == "kick" then
			target:Kick(("Kicked by %s"):format(caller.Name))
			print(("[Admin] %s kicked %s"):format(caller.Name, target.Name))

		elseif lower == "ban" then
			local info = {
				banned = true,
				by = caller.UserId,
				reason = (payload and payload.reason) or "",
				ts = os.time(),
				expiresAt = nil,
			}
			setBan(target.UserId, info)
			target:Kick(("Banned by %s"):format(caller.Name))
			print(("[Admin] %s banned %s"):format(caller.Name, target.Name))

		elseif lower == "freeze" then
			local hrp = getHRP(target.Character)
			local hum = getHumanoid(target.Character)
			if hrp and hum then
				local frozen = target.Character:GetAttribute("Frozen") == true
				if frozen then
					target.Character:SetAttribute("Frozen", false)
					hrp.Anchored = false
					hum.WalkSpeed = 16
					hum.JumpPower = 50
					print(("[Admin] %s unfroze %s"):format(caller.Name, target.Name))
				else
					target.Character:SetAttribute("Frozen", true)
					hrp.Anchored = true
					hum.WalkSpeed = 0
					hum.JumpPower = 0
					print(("[Admin] %s froze %s"):format(caller.Name, target.Name))
				end
			end

		elseif lower == "bring" then
			local adminHRP = getHRP(caller.Character)
			local tgtHRP   = getHRP(target.Character)
			if adminHRP and tgtHRP then
				-- Ziel 2 Studs VOR den Admin setzen (in Admin-Blickrichtung) und nur das Ziel drehen
				local adminPos  = adminHRP.Position
				local forward   = adminHRP.CFrame.LookVector
				local targetPos = adminPos + forward * 2

				tgtHRP.CFrame = CFrame.lookAt(
					targetPos,
					Vector3.new(adminPos.X, targetPos.Y, adminPos.Z) -- nur yaw
				)
				-- adminHRP bleibt UNVERÄNDERT
				print(("[Admin] %s brought %s (target faces admin)"):format(caller.Name, target.Name))
			end

		elseif lower == "teleport" or lower == "tpto" then
			local adminHRP = getHRP(caller.Character)
			local tgtHRP   = getHRP(target.Character)
			if adminHRP and tgtHRP then
				-- Admin 3 Studs VOR dem Ziel (in Ziel-Blickrichtung) platzieren
				local tPos = tgtHRP.Position
				local tFwd = tgtHRP.CFrame.LookVector
				local aPos = tPos + tFwd * 3  -- + = vor dem Ziel; - wäre hinter dem Ziel

				-- Nur den ADMIN ausrichten (Yaw), Ziel bleibt unverändert
				adminHRP.CFrame = CFrame.lookAt(
					Vector3.new(aPos.X, tPos.Y, aPos.Z), -- gleiche Höhe wie Ziel
					Vector3.new(tPos.X, tPos.Y, tPos.Z)
				)

				print(("[Admin] %s teleported in front of %s (admin faces target, target unchanged)"):format(caller.Name, target.Name))
			end


			-- Platzhalter: Implementiere bei Bedarf
		elseif lower == "spectate" then
			-- TODO: Kamera clientseitig steuern (Remote an Caller), hier nur Erlaubnis verteilen

		elseif lower == "fly" then
		-- Admin erlaubt/verbietet Fly für diesen Spieler
			local uid = target.UserId
			local currentlyAllowed = flyAllowed[uid] == true
			local newAllowed = not currentlyAllowed

			setFlyAllowed(target, newAllowed)

		print(("[Admin] %s set flyAllowed=%s for %s"):format(
			caller.Name,
			tostring(newAllowed),
			target.Name
			))
	end






	end)
