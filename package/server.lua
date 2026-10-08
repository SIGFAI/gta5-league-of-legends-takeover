-- Summoner's Rift: Los Santos, the match server.
-- It keeps the lobby (teams of up to 5, champion picks, the countdown), relays every ability cast to the other players,
-- owns the health of the turrets and nexuses so everybody sees the same base fall, and announces the winner.
-- Minions, jungle camps and bots run on every client; players, building health and objectives are shared from here.
local MAX_TEAM = 5
local LOBBY_SEC = 25          -- countdown after the first pick
local FULL_SEC = 8            -- shorter once both teams are full
local OVER_SEC = 18           -- scoreboard time before the next lobby
local CHAMPS = { aurelia = true, kael = true, vesper = true, shade = true, bastion = true, lumi = true, cinder = true, voltaire = true }

local players = {}           -- source -> { name, team, slot, champ }
local phase = 'lobby'        -- lobby | playing | over
local countdownAt            -- os.time() when the match starts
local matchT0 = 0
local hp = {}                -- structure id -> hit points left
local startedMatch = 0

local function count(team)
	local n = 0
	for _, p in pairs(players) do if p.team == team and p.champ then n = n + 1 end end
	return n
end

local function freeSlot(team)
	local used = {}
	for _, p in pairs(players) do if p.team == team and p.slot then used[p.slot] = true end end
	for i = 1, MAX_TEAM do if not used[i] then return i end end
end

local function publicList()
	local out = {}
	for src, p in pairs(players) do
		if p.champ then out[#out + 1] = { src = src, name = p.name, team = p.team, slot = p.slot, champ = p.champ } end
	end
	table.sort(out, function(a, b) return a.team == b.team and a.slot < b.slot or a.team < b.team end)
	return out
end

local function broadcastLobby()
	local left = countdownAt and math.max(0, countdownAt - os.time()) or -1
	TriggerClientEvent('lol:lobby', -1, { phase = phase, players = publicList(), left = left })
end

local function startMatch()
	if phase ~= 'lobby' then return end
	phase = 'playing'
	countdownAt = nil
	hp = {}
	startedMatch = startedMatch + 1
	matchT0 = os.time()
	TriggerClientEvent('lol:start', -1, { players = publicList(), id = startedMatch })
	print('SIGF_NOTE lol match ' .. startedMatch .. ' started with ' .. #publicList() .. ' players')
end

local function toLobby()
	phase = 'lobby'
	hp = {}
	countdownAt = os.time() + LOBBY_SEC
	TriggerClientEvent('lol:reset', -1)
	broadcastLobby()
end

-- the lobby clock
CreateThread(function()
	while true do
		Wait(1000)
		if phase == 'lobby' and countdownAt then
			if os.time() >= countdownAt then startMatch() else broadcastLobby() end
		end
	end
end)

RegisterNetEvent('lol:hello', function()
	local src = source
	TriggerClientEvent('lol:lobby', src, { phase = phase, players = publicList(), left = countdownAt and math.max(0, countdownAt - os.time()) or -1,
		running = phase == 'playing' and (os.time() - matchT0) or nil, id = startedMatch })
	if phase == 'playing' then TriggerClientEvent('lol:hpsync', src, hp) end
end)

-- a champion pick: joins the smaller team the first time
RegisterNetEvent('lol:pick', function(champ, name)
	local src = source
	if not CHAMPS[champ] then return end
	local p = players[src]
	if not p then
		local team = count('blue') <= count('red') and 'blue' or 'red'
		local slot = freeSlot(team)
		if not slot then team = team == 'blue' and 'red' or 'blue' slot = freeSlot(team) end
		if not slot then TriggerClientEvent('lol:full', src) return end
		p = { team = team, slot = slot }
		players[src] = p
	elseif phase == 'playing' then
		return
	end
	p.name = tostring(name or ('PLAYER ' .. src)):sub(1, 14):upper()
	p.champ = champ
	if phase == 'lobby' then
		if not countdownAt then countdownAt = os.time() + LOBBY_SEC end
		if count('blue') >= MAX_TEAM and count('red') >= MAX_TEAM then countdownAt = math.min(countdownAt, os.time() + FULL_SEC) end
		broadcastLobby()
	elseif phase == 'playing' then
		-- a late player takes over a bot of the smaller team
		TriggerClientEvent('lol:late', -1, { src = src, name = p.name, team = p.team, slot = p.slot, champ = p.champ, t = os.time() - matchT0, id = startedMatch })
		TriggerClientEvent('lol:hpsync', src, hp)
	end
end)

-- "start now": the match begins once every player in the lobby asked for it
RegisterNetEvent('lol:go', function()
	local src = source
	if phase ~= 'lobby' or not players[src] then return end
	players[src].go = true
	for _, p in pairs(players) do if p.champ and not p.go then return end end
	startMatch()
end)

AddEventHandler('playerDropped', function()
	local src = source
	local p = players[src]
	if not p then return end
	players[src] = nil
	TriggerClientEvent('lol:left', -1, src)
	if phase == 'lobby' then
		local any = false
		for _ in pairs(players) do any = true end
		if not any then countdownAt = nil end
		broadcastLobby()
	elseif phase == 'playing' then
		local any = false
		for _ in pairs(players) do any = true end
		if not any then phase = 'lobby' hp = {} countdownAt = nil end
	end
end)

-- relay of what a player did: casts, deaths, levels, objectives
RegisterNetEvent('lol:cast', function(k, ax, ay, az)
	local src = source
	if not players[src] or phase ~= 'playing' then return end
	TriggerClientEvent('lol:cast', -1, src, k, ax, ay, az)
end)

RegisterNetEvent('lol:died', function(killer)
	local src = source
	if not players[src] or phase ~= 'playing' then return end
	TriggerClientEvent('lol:died', -1, src, tonumber(killer) or 0)
end)

RegisterNetEvent('lol:back', function()
	local src = source
	if not players[src] or phase ~= 'playing' then return end
	TriggerClientEvent('lol:back', -1, src)
end)

RegisterNetEvent('lol:stat', function(lv, gold)
	local src = source
	if not players[src] or phase ~= 'playing' then return end
	TriggerClientEvent('lol:stat', -1, src, tonumber(lv) or 1, tonumber(gold) or 0)
end)

local taken = {}
RegisterNetEvent('lol:obj', function(kind, team, serial)
	local src = source
	if not players[src] or phase ~= 'playing' then return end
	local key = tostring(kind) .. ':' .. tostring(serial or 0)
	if taken[key] == startedMatch then return end        -- the first client to report it wins
	taken[key] = startedMatch
	TriggerClientEvent('lol:obj', -1, src, kind, team)
end)

-- building health: every hit is reported here, the answer goes to everybody
RegisterNetEvent('lol:sh', function(id, dmg, max)
	local src = source
	if not players[src] or phase ~= 'playing' then return end
	id, dmg, max = tostring(id), tonumber(dmg) or 0, tonumber(max) or 1000
	if dmg <= 0 or dmg > 1500 then return end
	local left = (hp[id] or max) - dmg
	if left < 0 then left = 0 end
	hp[id] = left
	TriggerClientEvent('lol:sh', -1, id, left, src)
	if left <= 0 and id:find('nexus') then
		phase = 'over'
		local winner = id:find('^blue') and 'red' or 'blue'
		TriggerClientEvent('lol:over', -1, winner)
		SetTimeout(OVER_SEC * 1000, toLobby)
		print('SIGF_NOTE lol match over, winner ' .. winner)
	end
end)
