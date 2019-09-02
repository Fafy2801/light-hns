-- Enums
ROUND_WAIT, ROUND_ACTIVE, ROUND_POST = 1, 2, 3
ROUND_ENDTIME, ROUND_ENDCAUGHT, ROUND_ENDABORT, ROUND_ENDLEAVE = 1, 2, 3, 4

GM.RoundStartTime = 0
GM.RoundCount = -1
GM.RoundState = ROUND_WAIT
GM.PlayedLastHiderSound = false

if SERVER then
	util.AddNetworkString("HNS.RoundInfo")

	function GM:RoundCheck()
		timer.Simple(0.1, function()
			if self.RoundState == ROUND_ACTIVE then
				-- Check for hiders
				if team.NumPlayers(TEAM_HIDE) == 0 then
					self:RoundEnd(ROUND_ENDCAUGHT)
				-- Check for seekers
				elseif team.NumPlayers(TEAM_SEEK) == 0 then
					-- Seeker avoided
					self:RoundEnd(ROUND_ENDLEAVE)
				end

				-- Advert last hider
				if !self.PlayedLastHiderSound && team.NumPlayers(TEAM_HIDE) == 1 then
					self:BroadcastSound("ui/medic_alert.wav")
					self:BroadcastChat(COLOR_WHITE, "[", Color(155, 155, 255), "HNS", COLOR_WHITE, "] ", Color(155, 155, 155), "1 hider left.")
					self.PlayedLastHiderSound = true
				end
			elseif self.RoundState == ROUND_WAIT then
				-- Check for any players
				if team.NumPlayers(TEAM_HIDE) + team.NumPlayers(TEAM_SEEK) > 1 then
					self:RoundRestart()
				end
			end
		end)
	end

	function GM:RoundTimer(time)
		-- Store this, so when the cvar changes, it won't fuck up seeker blind time
		self.RoundLength = self.CVars.TimeLimit:GetInt()
		-- Network
		net.Start("HNS.RoundInfo")
			net.WriteDouble(CurTime())
			net.WriteDouble(time)
			net.WriteDouble(self.RoundLength)
			net.WriteInt(self.RoundCount, 8)
			net.WriteUInt(self.RoundState, 3)
		net.Broadcast()
		-- Round end timer
		timer.Create("HNS.RoundTimer", time, 1, function()
			-- If round was active, stop and set hiders as champions
			if self.CVars.TimeLimit:GetInt() > 0 && self.RoundState == ROUND_ACTIVE then
				self:RoundEnd(ROUND_ENDTIME)
				-- Call hook
				hook.Run("HASRoundEndedTime")
			-- If round was over, start a new one
			elseif self.RoundState == ROUND_POST then
				self:RoundRestart()
			end
		end)
	end

	function GM:RoundRestart()
		-- Restart map
		game.CleanUpMap()

		-- Remove weapons and vehicles
		for _, ent in pairs(ents.GetAll()) do
			if (ent:IsWeapon() && ent:GetClass() != "has_hands") || ent:IsVehicle() then
				ent:Remove()
			end
		end

		for _, ply in ipairs(player.GetAll()) do
			-- Turn seekers into hiders
			if ply:Team() == TEAM_SEEK then
				ply:SetTeam(TEAM_HIDE)
			end
			-- Spawn hiders (will skip spectators)
			if ply:Team() == TEAM_HIDE then
				ply:Spawn()
			end
		end

		-- Check for enough players
		if team.NumPlayers(TEAM_HIDE) > 1 then
			-- Start round
			self.RoundState = ROUND_ACTIVE
			self.RoundCount = self.RoundCount + 1
			self:RoundTimer(self.CVars.TimeLimit:GetInt() + self.CVars.BlindTime:GetInt())

			-- Select random seeker and spawn
			local seeker = team.GetPlayers(TEAM_HIDE)[math.random(team.NumPlayers(TEAM_HIDE))]
			seeker:SetTeam(TEAM_SEEK)
			seeker:Spawn()

			-- Log
			print(string.format("[LHNS] Starting round %s. The first seeker is %s (%s)", self.RoundCount, seeker:Name(), seeker:SteamID()))

			-- Don't play sound when round starts with 1 hider
			self.PlayedLastHiderSound = team.NumPlayers(TEAM_HIDE) <= 1
		else
			self.RoundState = ROUND_WAIT
			-- Network
			self:RoundTimer(self.CVars.TimeLimit:GetInt() + self.CVars.BlindTime:GetInt())
			-- Advert
			self:BroadcastChat(COLOR_WHITE, "[", COLOR_HNS_TAG, "HNS", COLOR_WHITE, "] There's not enough players to start the round...")
			print("[LHNS] There's not enough players to begin round " .. self.RoundCount .. "!")
		end

		hook.Run("HASRoundStarted")
	end

	function GM:RoundEnd(ending)
		-- Store time left
		local left = math.abs(timer.TimeLeft("HNS.RoundTimer") || 0)
		-- End round and start counting the next
		self.RoundState = ROUND_POST
		self:RoundTimer(10)

		-- If a seeker avoided, use one less round to restart the round we just lost
		if ending == ROUND_ENDLEAVE then
			self.RoundCount = self.RoundCount - 1
			-- Advert
			self:BroadcastChat(COLOR_WHITE, "[", Color(155, 155, 255), "HNS", COLOR_WHITE, "] ", Color(155, 155, 255), "The Hiding Win!")
			self:BroadcastSound("misc/happy_birthday.wav")
			-- Log
			print(string.format("[LHNS] Round %s was aborted! Starting round again.", self.RoundCount + 1))
			return
		else
			if ending == ROUND_ENDTIME then
				-- Award hiders
				if GAMEMODE.RoundCount > 0 then
					for _, ply in ipairs(team.GetPlayers(TEAM_HIDE)) do
						ply:AddFrags(GetConVar("has_hidereward"):GetInt())
					end
				end
				-- Advert
				self:BroadcastChat(COLOR_WHITE, "[", Color(155, 155, 255), "HNS", COLOR_WHITE, "] ", Color(155, 155, 255), "The Hiding Win!")
				self:BroadcastSound("misc/happy_birthday.wav")
				-- Log
				print(string.format("[LHNS] Hiders won round %s with %s hider(s) left.", self.RoundCount, team.NumPlayers(TEAM_HIDE)))
			elseif ending == ROUND_ENDCAUGHT then
				-- Advert seekers
				self:BroadcastChat(COLOR_WHITE, "[", Color(255, 155, 155), "HNS", COLOR_WHITE, "] ", Color(255, 155, 155), "The Seekers Win!")
				self:BroadcastSound("misc/happy_birthday.wav")
				-- Log
				print(string.format("[LHNS] Seekers won round %s with %s left.", self.RoundCount, string.ToMinutesSeconds(left)))
			end

			if self.RoundCount >= self.CVars.MaxRounds:GetInt() then
				-- Start votemap
				hook.Run("HASVotemapStart")

				-- Remove timer
				timer.Remove("HNS.RoundTimer")
			end
		end

	end
elseif CLIENT then
	net.Receive("HNS.RoundInfo", function()
		GAMEMODE.RoundStartTime = net.ReadDouble()
		local time = net.ReadDouble()
		GAMEMODE.RoundLength = net.ReadDouble()
		GAMEMODE.RoundCount = net.ReadInt(8)
		GAMEMODE.RoundState = net.ReadUInt(3)

		-- Create a timer to display info
		if GAMEMODE.RoundState == ROUND_ACTIVE then
			timer.Create("HNS.RoundTimer", GAMEMODE.RoundStartTime - CurTime() + time, 1, function() end)
		else
			-- Put timer to the max if we are waiting (so we can see the server's max time)
			if GAMEMODE.RoundState == ROUND_WAIT then
				timer.Create("HNS.RoundTimer", GetConVar("has_timelimit"):GetInt() + 30, 1, function () end)
			end
			-- Pause the timer if the round didn't start
			timer.Pause("HNS.RoundTimer")
		end
	end)
end