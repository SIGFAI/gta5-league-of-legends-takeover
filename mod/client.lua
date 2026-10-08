-- Summoner's Rift: Los Santos. A three-lane MOBA played on the Sandy Shores airfield:
-- two bases with a nexus, three lanes of turrets and minion waves, jungle camps, a void boss, gold, levels, an item shop.
-- The hero (Aurelia) casts Q W E R, auto-attacks with the carbine, buys items; AI champions fight back in every lane.
Lol = Lol or {}
Lol.NET = { on = false, me = 0, auth = false }
Sigf._killer = Sigf._killer or {}

local BLUE, RED = { 70, 170, 255 }, { 255, 70, 45 }
local COL = { blue = BLUE, red = RED, neutral = { 255, 215, 90 } }
local function foe(team) return team == 'blue' and 'red' or 'blue' end

local stage = Sigf.Stage()
local DEMO = stage == 'demo'
local HOME = stage == ''                 -- a player's own game: the player is the hero and can lose
local PLAYER_HERO = DEMO or HOME
Lol.DEMO, Lol.HOME = DEMO, HOME
local function god() return DEMO and not Lol.mortal end

-- ---------- tuning ----------
local N = 70.0                           -- nexus to the middle of the map along the mid lane
local T = 40.0                           -- how far the side lanes bend away from the mid lane
local WAVE_SEC = DEMO and 14 or 30
local FIRST_WAVE = DEMO and 1.0 or 18.0
local MAP_ASPECT = 1.45
local MAP_W = 2 * N / 0.88               -- world metres covered by the minimap width
local MAP_H = MAP_W / MAP_ASPECT

local ITEMS = {                          -- id matches mod/img/icon_item_<id>.png
	{ id = 1, name = 'Rift Blade',  cost = 350,  desc = '+25% damage',            dmg = 0.25 },
	{ id = 2, name = 'Swift Boots', cost = 300,  desc = '+20% move speed',        ms = 0.20 },
	{ id = 3, name = 'Heartstone',  cost = 400,  desc = '+150 health',            hp = 150 },
	{ id = 4, name = 'Arcane Orb',  cost = 450,  desc = '-20% cooldowns',         cdr = 0.20 },
	{ id = 5, name = 'Vamp Sash',   cost = 500,  desc = '12% life steal',         ls = 0.12 },
	{ id = 6, name = 'Stormcaller', cost = 800,  desc = '+45% damage',            dmg = 0.45 },
	{ id = 7, name = 'Titan Plate', cost = 700,  desc = '+300 health',            hp = 300 },
	{ id = 8, name = 'Hex Crown',   cost = 1000, desc = '+30% damage, -10% cooldowns', dmg = 0.30, cdr = 0.10 },
}
local AI_BUILD = { 1, 3, 2, 5, 4, 7, 6, 8 }
local MAX_LV = 10
local XP_NEED = { 0, 60, 150, 270, 420, 600, 820, 1080, 1380, 1720 }   -- total xp for level 1..10

local S = {}                             -- structures (array) + S.nexus[team], S.turret[team]
local M = {}                             -- lane minions: ped -> info
local JG = {}                            -- jungle monsters: ped -> info
local CAMPS = {}                         -- jungle camps
local CH = {}                            -- champions (array) with CH.hero
local BOSS                               -- the void boss
local fx = { beams = {}, projs = {}, domes = {}, dashes = {}, meteors = {}, rings = {}, bursts = {}, slashes = {}, novas = {} }
local L                                  -- map layout
local match = { over = false, t0 = 0, wave = 0, kills = { blue = 0, red = 0 }, running = false }
local hud = { shopOpen = false }
Lol.CH, Lol.S = CH, S

-- ---------- small helpers ----------
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function flat(v) return vector3(v.x, v.y, 0.0) end
local function norm2(v)
	local f = flat(v)
	local l = #f
	if l < 0.001 then return vector3(1.0, 0.0, 0.0) end
	return f / l
end
local function dist2(a, b) return #(flat(a) - flat(b)) end
local function alive(ped) return ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) end
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local function now() return GetGameTimer() end

local function gz(x, y, hint)
	local ok, z = GetGroundZFor_3dCoord(x, y, hint + 40.0, false)
	return ok and z or hint
end

-- lane space (u along the mid lane from the blue to the red base, v to the side) -> world
local function W(u, v)
	local x, y = L.c.x + L.dir.x * u + L.side.x * v, L.c.y + L.dir.y * u + L.side.y * v
	return vector3(x, y, gz(x, y, L.c.z))
end
local function toLane(p)
	local d = p - L.c
	return d.x * L.dir.x + d.y * L.dir.y, d.x * L.side.x + d.y * L.side.y
end

local function banner(text, col, sec) Sigf.Nui({ banner = text, color = col or '#f0e6d2', sec = sec or 3 }) end
local function feed(text, team) Sigf.Nui({ feed = { text = text, team = team == 'red' and 1 or 0 } }) end

-- A real GTA explosion, unless the player stands close: a blast knocks the player flat, so only the smoke shows then.
local function boom(pos, kind, opts)
	if #(GetEntityCoords(PlayerPedId()) - pos) > 12.0 then Sigf.Explode(pos, kind, opts)
	else Sigf.Fx('core', 'exp_grd_grenade_lod', pos, { scale = 1.6 }) end
end

-- ---------- lanes ----------
local LANES = {}
local function buildLanes()
	local pts = {
		mid = { { -N, 0 }, { N, 0 } },
		top = { { -N, 0 }, { -0.64 * N, T }, { 0.64 * N, T }, { N, 0 } },
		bot = { { -N, 0 }, { -0.64 * N, -T }, { 0.64 * N, -T }, { N, 0 } },
	}
	for name, list in pairs(pts) do
		local ln = { name = name, p = {}, len = 0.0, cum = { 0.0 } }
		for i, q in ipairs(list) do
			ln.p[i] = W(q[1], q[2])
			if i > 1 then
				local a, b = list[i - 1], list[i]
				ln.len = ln.len + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
				ln.cum[i] = ln.len
			end
		end
		ln.uv = list
		LANES[name] = ln
	end
end

-- point at distance s (metres) from the blue base along the lane (lat: sideways offset), as lane-space coords
local function laneUV(ln, s, lat)
	s = clamp(s, 0.0, ln.len)
	for i = 2, #ln.uv do
		if s <= ln.cum[i] + 0.0001 then
			local a, b = ln.uv[i - 1], ln.uv[i]
			local f = (s - ln.cum[i - 1]) / math.max(0.001, ln.cum[i] - ln.cum[i - 1])
			local u, v = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			if lat and lat ~= 0 then
				local dx, dy = b[1] - a[1], b[2] - a[2]
				local l = math.sqrt(dx * dx + dy * dy)
				u, v = u - dy / l * lat, v + dx / l * lat
			end
			return u, v
		end
	end
	local e = ln.uv[#ln.uv]
	return e[1], e[2]
end
local function lanePos(ln, s, lat) local u, v = laneUV(ln, s, lat) return W(u, v) end

-- progress of a world position along a lane (metres from the blue base), and its distance from the lane line
local function laneProgress(ln, p)
	local pu, pv = toLane(p)
	local best, bs, bd = nil, 0.0, 1e9
	for i = 2, #ln.uv do
		local a, b = ln.uv[i - 1], ln.uv[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l2 = dx * dx + dy * dy
		local f = clamp(((pu - a[1]) * dx + (pv - a[2]) * dy) / l2, 0.0, 1.0)
		local qx, qy = a[1] + dx * f, a[2] + dy * f
		local d = math.sqrt((pu - qx) ^ 2 + (pv - qy) ^ 2)
		if d < bd then bd, bs = d, ln.cum[i - 1] + f * math.sqrt(l2) end
	end
	return bs, bd
end


-- ---------- damage ----------
local function popText(p, dmg, col)
	Sigf.Text3D(tostring(math.floor(dmg)), p + vector3(0, 0, 1.5), 0.9, { color = col or { 255, 255, 255 }, scale = 0.55 })
end

local champOf                           -- (ped) -> champion table, defined with the champions

-- Hurt a ped; `by` is the attacking ped (credits the kill). Armour (shield) soaks first. Returns true if it died.
local function hurt(ped, dmg, by, col)
	if not alive(ped) or ped == PlayerPedId() and god() then return false end
	local ch = champOf and champOf(ped)
	if ch and ch.remote then popText(GetEntityCoords(ped), dmg, col) return false end       -- its own player takes the damage
	if ch and ch.guard and now() < ch.guard then dmg = dmg * 0.5 end
	local eff = GetEntityHealth(ped) - 100 + GetPedArmour(ped)
	popText(GetEntityCoords(ped), dmg, col)
	if by and by ~= ped then
		local bc = champOf and champOf(by)
		if bc and bc.ls and bc.ls > 0 and alive(by) then
			local mx = GetEntityMaxHealth(by)
			SetEntityHealth(by, math.min(mx, GetEntityHealth(by) + math.floor(dmg * bc.ls)))
		end
	end
	if eff - dmg <= 0 then
		Sigf._killer[ped] = by
		SetEntityHealth(ped, 0)
		return true
	end
	ApplyDamageToPed(ped, math.floor(dmg), true)
	return false
end

local function knock(ped, dir, force)
	if not alive(ped) or ped == PlayerPedId() then return end
	local kc = champOf and champOf(ped)
	if kc and kc.remote then return end
	SetPedToRagdoll(ped, 800, 800, 0, false, false, false)
	SetEntityVelocity(ped, dir.x * force, dir.y * force, 3.0)
end

-- ---------- structures ----------
local skinned = {}
-- The generated models carry their painted texture by name: swap it in from mod/img at run time.
local function skin(model)
	if skinned[model] then return end
	if model:find('poro') or model:find('drake') or model:find('baron') or model:find('shop') then return end      -- these carry their own embedded texture
	skinned[model] = true
	Sigf.LoadModel(model)
	local name = 'lol_' .. model .. '_' .. GetGameTimer()
	local txd = CreateRuntimeTxd(name)
	CreateRuntimeTextureFromImage(txd, 'skin', 'img/tex_' .. model:sub(6) .. '.png')
	AddReplaceTexture(model, model .. '_image_0', name, 'skin')
end

local destroyStruct                      -- defined below
local addTeamGold                        -- defined with the champions

local function vulnerable(s)
	if s.kind == 'turret' then
		if s.tier == 1 then return true end
		local outer = S.lane and S.lane[s.team] and S.lane[s.team][s.lane]
		return not (outer and outer.alive)
	end
	for _, t in ipairs(S) do
		if t.kind == 'turret' and t.team == s.team and t.tier == 2 and not t.alive then return true end
	end
	return false
end

local function hurtStruct(s, dmg, col, by)
	if not s.alive or match.over then return end
	if not vulnerable(s) then
		if now() > (s.warnAt or 0) then
			s.warnAt = now() + 2500
			Sigf.Text3D(s.kind == 'nexus' and 'SHIELDED: DESTROY A TURRET FIRST' or 'SHIELDED: DESTROY THE OUTER TURRET', s.pos + vector3(0, 0, s.top + 2.0), 1.8,
				{ color = { 200, 200, 255 }, scale = 0.55 })
		end
		return
	end
	if Lol.NET.on then
		Lol.netStructHit(s, dmg, by)               -- the server keeps the health and tells everybody
		return
	end
	s.hp = s.hp - dmg
	s.hitAt = now()
	s.by = by or s.by
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], s.pos + vector3(0, 0, 2.5 + math.random() * 2), { scale = 1.5 })
	if s.hp <= 0 then destroyStruct(s) end
end

local function mkStruct(team, kind, lane, tier, pos)
	local model = 'sigf_' .. kind .. '_' .. team
	skin(model)
	local face = team == 'blue' and L.dirHeading or (L.dirHeading + 180.0)
	local ent = Sigf.Prop(model, pos, { ground = true, heading = face })
	local nexus = kind == 'nexus'
	local hp = nexus and (DEMO and 600 or 2600) or (DEMO and 380 or (tier == 1 and 1100 or 1300))
	local s = { id = team .. ':' .. kind .. ':' .. lane .. ':' .. tier, team = team, kind = kind, lane = lane, tier = tier, ent = ent, pos = pos, hp = hp, max = hp, alive = true,
		r = nexus and 4.6 or 3.0, top = nexus and 10.5 or 7.5, shotAt = 0 }
	S[#S + 1] = s
	S[kind] = S[kind] or {}
	if nexus then S.nexus[team] = s
	else
		S.turret[team] = S.turret[team] or {}
		S.turret[team][#S.turret[team] + 1] = s
		S.lane = S.lane or {}
		S.lane[team] = S.lane[team] or {}
		if tier == 1 then S.lane[team][lane] = s end
	end
	return s
end

local function buildStructures()
	S.nexus, S.turret, S.lane = {}, {}, {}
	mkStruct('blue', 'nexus', 'mid', 0, W(-N, 0))
	mkStruct('red', 'nexus', 'mid', 0, W(N, 0))
	for name, ln in pairs(LANES) do
		for _, team in ipairs({ 'blue', 'red' }) do
			for tier = 1, 2 do
				local f = tier == 1 and 0.33 or 0.17
				local s = team == 'blue' and ln.len * f or ln.len * (1.0 - f)
				mkStruct(team, 'turret', name, tier, lanePos(ln, s, 0))
			end
		end
	end
end

-- Targets for team `team` (the buildings it can attack), nearest first. Respects the shields.
local function targetStruct(team, from)
	local best, bd
	for _, s in ipairs(S) do
		if s.alive and s.team ~= team and vulnerable(s) then
			local d = dist2(s.pos, from)
			if not bd or d < bd then best, bd = s, d end
		end
	end
	return best, bd
end

function destroyStruct(s)
	s.alive = false
	local p = s.pos
	local big = s.kind == 'nexus'
	if big then Sigf.Slowmo(0.4, 2.6) Sigf.Shake(0.6) Sigf.Sound('nexus_boom', nil, { volume = 1.0 })
	else Sigf.Sound('turret_boom', p, { range = 120.0, volume = 0.9 }) end
	for i = 0, big and 4 or 2 do
		Sigf.After(i * 0.35, function()
			local q = p + vector3(math.random(-3, 3), math.random(-3, 3), 1.0 + i * 0.9)
			boom(q, 4, { scale = 0.7, shake = big and 1.2 or 0.7 })
			Sigf.Fx('core', 'exp_grd_molotov', q, { scale = 1.4 })
			Sigf.Light(q, COL[s.team], 20.0, 12.0, 0.6)
		end)
	end
	Sigf.After(big and 3.4 or 1.2, function()
		Sigf.Remove(s.ent)
		s.rubble = Sigf.Fx('core', 'fire_petroltank_truck', p + vector3(0, 0, 0.3), { loop = true, scale = 1.4, life = 30 })
	end)
	local mine = s.team == (CH.hero and CH.hero.team or 'blue')
	if big then
		match.over = true
		Lol.Finish(s.team == 'red')
		return
	end
	local where = (s.tier == 1 and 'OUTER' or 'INNER') .. ' ' .. s.lane:upper()
	banner(mine and ('YOUR ' .. where .. ' TURRET HAS BEEN DESTROYED') or ('ENEMY ' .. where .. ' TURRET DESTROYED'), mine and '#ff7a5a' or '#7ac8ff', 3.5)
	feed((mine and 'Void' or 'Order') .. ' destroyed the ' .. s.lane .. ' ' .. (s.tier == 1 and 'outer' or 'inner') .. ' turret', mine and 'red' or 'blue')
	addTeamGold(foe(s.team), 120, s.by)
	if not mine then Lol.quest('turret') end
end

-- ---------- turret and nexus fire ----------
local function turretTick()
	local t0 = now()
	for _, s in ipairs(S) do
		if s.alive and (s.kind == 'turret' or (s.kind == 'nexus' and vulnerable(s))) then
			local top = s.pos + vector3(0, 0, s.top - 0.5)
			local range = s.kind == 'nexus' and 24.0 or 26.0
			local list = Lol.foes(s.team, s.pos, range, true)
			local best
			for _, f in ipairs(list) do
				if s.kind ~= 'nexus' or f.champ then
					local w = f.d + (f.champ and 8.0 or 0.0)       -- minions first, like the real thing
					if not best or w < best.w then best = f best.w = w end
				end
			end
			if best then
				fx.beams[#fx.beams + 1] = { a = top, b = best.pos + vector3(0, 0, 1.0), col = COL[s.team], to = t0 + 260 }
				Sigf.Light(top, COL[s.team], 10.0, 8.0, 0.25)
				Sigf.Sound('turret_zap', top, { range = 70.0, volume = 0.5 })
				Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], best.pos + vector3(0, 0, 1.0), { scale = 1.5 })
				local dmg = best.champ and (s.kind == 'nexus' and 45 or 34) or 52
				hurt(best.ped, dmg, nil, COL[s.team])
				knock(best.ped, norm2(best.pos - s.pos), 2.0)
			end
		end
	end
end


-- ---------- queries ----------
-- Living enemies of `team` within radius of pos: lane minions, jungle monsters (unless noJungle) and champions.
function Lol.foes(team, pos, radius, noJungle)
	local out = {}
	for ped, m in pairs(M) do
		if m.team ~= team and alive(ped) then
			local p = GetEntityCoords(ped)
			local d = #(p - pos)
			if d <= radius then out[#out + 1] = { ped = ped, pos = p, d = d, champ = false, kind = 'minion' } end
		end
	end
	if not noJungle then
		for ped in pairs(JG) do
			if alive(ped) then
				local p = GetEntityCoords(ped)
				local d = #(p - pos)
				if d <= radius then out[#out + 1] = { ped = ped, pos = p, d = d, champ = false, kind = 'jungle' } end
			end
		end
	end
	for _, c in ipairs(CH) do
		if c.team ~= team and alive(c.ped) then
			local p = GetEntityCoords(c.ped)
			local d = #(p - pos)
			if d <= radius then out[#out + 1] = { ped = c.ped, pos = p, d = d, champ = true, kind = 'champ', ch = c } end
		end
	end
	return out
end

function Lol.allies(team, pos, radius)
	local out = {}
	for ped, m in pairs(M) do
		if m.team == team and alive(ped) and #(GetEntityCoords(ped) - pos) <= radius then out[#out + 1] = ped end
	end
	for _, c in ipairs(CH) do
		if c.team == team and alive(c.ped) and #(GetEntityCoords(c.ped) - pos) <= radius then out[#out + 1] = c.ped end
	end
	return out
end

-- Buildings and the boss hit by something at pos with an area `radius` (a bolt, a meteor, a slash).
local function hitThings(team, pos, radius, dmg, col, by)
	if Lol.poroHit then Lol.poroHit(pos, radius, by) end
	local dk = Lol.Drake and Lol.Drake()
	if dk and dk.alive and dist2(dk.pos, pos) < dk.r + radius and pos.z < dk.pos.z + dk.top + radius then Lol.hurtDrake(dmg, col, by) end
	for _, s in ipairs(S) do
		if s.alive and s.team ~= team and dist2(s.pos, pos) < s.r + radius then hurtStruct(s, dmg, col, by) end
	end
	if BOSS and BOSS.alive and dist2(BOSS.pos, pos) < BOSS.r + radius and #(BOSS.pos + vector3(0, 0, 2) - pos) < BOSS.top + radius + 2.0 then
		Lol.hurtBoss(dmg, col, by)
	end
end

-- ---------- lane minions ----------
local KINDS = {
	warrior = { blue = 's_m_m_movspace_01', red = 's_m_m_movalien_01', weapon = 'WEAPON_BAT', health = 130, acc = 30, xp = 22, gold = 20 },
	caster  = { blue = 's_m_m_hazmatworker_01', red = 'u_m_y_zombie_01', weapon = 'WEAPON_PISTOL', health = 90, acc = 35, xp = 16, gold = 14 },
	super   = { blue = 'u_m_y_juggernaut_02', red = 'u_m_y_juggernaut_01', weapon = 'WEAPON_COMBATMG', health = 380, acc = 20, armor = 40, xp = 60, gold = 60 },
}
local minionCount = 0

local function spawnMinion(team, kind, laneName, idx, total)
	if minionCount > 64 then return end
	local k, ln = KINDS[kind], LANES[laneName]
	local s0 = team == 'blue' and 9.0 or ln.len - 9.0
	if DEMO and match.wave == 1 and laneName == 'mid' then s0 = team == 'blue' and ln.len * 0.36 or ln.len * 0.64 end
	local p = lanePos(ln, s0 + (team == 'blue' and 1 or -1) * (idx % 2) * 1.4, ((idx - 1) % 3 - 1) * 1.9)
	local toward = norm2((team == 'blue' and lanePos(ln, 20.0, 0) or lanePos(ln, ln.len - 20.0, 0)) - p)
	local buffed = match.buff and match.buff.team == team and now() < match.buff.to
	local hp = math.floor(k.health * (buffed and 1.8 or 1.0))
	local ped = Sigf.Ped(k[team], p + vector3(0, 0, 0.6), { enemy = team == 'red', weapon = k.weapon, health = hp,
		armor = (k.armor or 0) + (buffed and 40 or 0), accuracy = k.acc, fight = false, heading = GetHeadingFromVector_2d(toward.x, toward.y), life = 200 })
	if not ped then return end
	SetPedKeepTask(ped, true)
	SetPedFleeAttributes(ped, 0, false)
	SetPedCombatAttributes(ped, 46, true)
	SetPedCombatRange(ped, kind == 'warrior' and 0 or 2)
	M[ped] = { team = team, kind = kind, lane = laneName, born = now(), buffed = buffed, def = k,
		max = hp + (k.armor or 0) + (buffed and 40 or 0) }
	minionCount = minionCount + 1
end

local function spawnWave()
	if match.over then return end
	match.wave = match.wave + 1
	local n = match.wave
	local super = n % 4 == 0
	Sigf.Sound('wave_horn', nil, { volume = 0.35 })
	banner(n == 1 and 'MINIONS HAVE SPAWNED' or ('MINION WAVE ' .. n), '#f0e6d2', 2.5)
	for laneName in pairs(LANES) do
		for _, team in ipairs({ 'blue', 'red' }) do
			local order = laneName == 'mid' and { 'warrior', 'warrior', 'warrior', 'caster', 'caster' } or { 'warrior', 'warrior', 'caster', 'caster' }
			if super or (match.buff and match.buff.team == team and now() < match.buff.to) then order[#order + 1] = 'super' end
			for i, kind in ipairs(order) do
				Sigf.After((i - 1) * 0.55, function()
					if not match.over then spawnMinion(team, kind, laneName, i, #order) end
				end)
			end
		end
	end
end

local function minionTick(ped, m)
	local t0 = now()
	local p = GetEntityCoords(ped)
	local best
	for _, f in ipairs(Lol.foes(m.team, p, 17.0)) do
		if f.kind ~= 'jungle' and (not best or f.d < best.d) then best = f end
	end
	if best then
		if m.tgt ~= best.ped or t0 > (m.cmd or 0) then
			m.tgt, m.cmd, m.state = best.ped, t0 + 2500, 'fight'
			TaskCombatPed(ped, best.ped, 0, 16)
		end
		return
	end
	local ln = LANES[m.lane]
	local st, sd = targetStruct(m.team, p)
	if st and sd < 14.0 then
		if m.state ~= 'siege' then m.state, m.cmd = 'siege', 0 end
		if t0 > (m.cmd or 0) then
			m.cmd = t0 + 1500
			TaskShootAtCoord(ped, st.pos.x, st.pos.y, st.pos.z + 2.5, 1500, GetHashKey('FIRING_PATTERN_BURST_FIRE'))
		end
		hurtStruct(st, (m.kind == 'super' and 9 or 3), COL[m.team])
		fx.beams[#fx.beams + 1] = { a = p + vector3(0, 0, 1.2), b = st.pos + vector3(math.random() - 0.5, math.random() - 0.5, 2.5), col = COL[m.team], to = t0 + 120 }
		return
	end
	if m.state ~= 'march' or t0 > (m.cmd or 0) then
		m.state, m.cmd = 'march', t0 + 3500
		local prog = laneProgress(ln, p)
		local goal = lanePos(ln, clamp(prog + (m.team == 'blue' and 16.0 or -16.0), 0.0, ln.len), 0)
		TaskGoToCoordAnyMeans(ped, goal.x, goal.y, goal.z, 2.4, 0, false, 786603, 0.0)
	end
end

-- ---------- jungle ----------
local MOBS = {
	yeti   = { model = 'u_m_m_yeti', hp = 420, name = 'Frost Sentinel' },
	yule   = { model = 'u_m_m_yulemonster', hp = 420, name = 'Ember Brute' },
	coyote = { model = 'a_c_coyote', hp = 120, name = 'Dune Wolf' },
	boar   = { model = 'a_c_boar', hp = 220, name = 'Rift Boar' },
}
local CAMP_DEFS = {
	{ id = 'sentinel_b', u = -0.40 * N, v = 0.52 * T,  mobs = { 'yeti' },                        buff = 'focus', gold = 90, xp = 180, name = 'Frost Sentinel' },
	{ id = 'sentinel_r', u = 0.40 * N,  v = 0.52 * T,  mobs = { 'yeti' },                        buff = 'focus', gold = 90, xp = 180, name = 'Frost Sentinel' },
	{ id = 'ember_b',    u = -0.40 * N, v = -0.52 * T, mobs = { 'yule' },                        buff = 'might', gold = 90, xp = 180, name = 'Ember Brute' },
	{ id = 'ember_r',    u = 0.40 * N,  v = -0.52 * T, mobs = { 'yule' },                        buff = 'might', gold = 90, xp = 180, name = 'Ember Brute' },
	{ id = 'wolves_b',   u = -0.14 * N, v = -0.40 * T, mobs = { 'coyote', 'coyote', 'coyote' },  gold = 55, xp = 110, name = 'Dune Wolves' },
	{ id = 'wolves_r',   u = 0.14 * N,  v = -0.40 * T, mobs = { 'coyote', 'coyote', 'coyote' },  gold = 55, xp = 110, name = 'Dune Wolves' },
	{ id = 'boars_b',    u = -0.14 * N, v = 0.40 * T,  mobs = { 'boar', 'boar' },                gold = 55, xp = 110, name = 'Rift Boars' },
	{ id = 'boars_r',    u = 0.14 * N,  v = 0.40 * T,  mobs = { 'boar', 'boar' },                gold = 55, xp = 110, name = 'Rift Boars' },
}
local BUFFS = {
	focus = { name = 'ARCANE FOCUS', sec = 60, cdr = 0.25, color = { 90, 190, 255 }, text = 'ARCANE FOCUS: -25% cooldowns for 60 s' },
	might = { name = 'EMBER MIGHT', sec = 60, dmg = 0.25, color = { 255, 140, 50 }, text = 'EMBER MIGHT: +25% damage for 60 s' },
}
Lol.BUFFS = BUFFS

local function spawnCamp(cp)
	cp.mobs = {}
	for i, key in ipairs(cp.def.mobs) do
		local def = MOBS[key]
		local a = (i - 1) / #cp.def.mobs * 6.283
		local off = #cp.def.mobs > 1 and vector3(math.cos(a) * 2.2, math.sin(a) * 2.2, 0) or vector3(0, 0, 0)
		local p = cp.pos + off
		local ped = Sigf.Ped(def.model, p + vector3(0, 0, 0.6), { health = def.hp, fight = false, accuracy = 30, life = 0,
			heading = math.random(0, 359) })
		if ped then
			SetPedKeepTask(ped, true)
			SetBlockingOfNonTemporaryEvents(ped, true)
			SetPedCanRagdoll(ped, true)
			JG[ped] = { camp = cp, home = p, max = def.hp, key = key, born = now() }
			cp.mobs[#cp.mobs + 1] = ped
		end
	end
	cp.deadAt = nil
	cp.respawning = false
end

local function jungleTick()
	local t0 = now()
	for _, cp in ipairs(CAMPS) do
		local n = 0
		for _, ped in ipairs(cp.mobs) do if alive(ped) then n = n + 1 end end
		if n == 0 and #cp.mobs > 0 and not cp.respawning and not match.over then
			cp.respawning = true
			cp.deadAt = cp.deadAt or t0
			Sigf.After(cp.def.buff and 75 or 55, function()
				if match.running and not match.over then
					for _, ped in ipairs(cp.mobs) do Sigf.Remove(ped) JG[ped] = nil end
					spawnCamp(cp)
				end
			end)
		end
	end
	for ped, j in pairs(JG) do
		if not DoesEntityExist(ped) then JG[ped] = nil
		elseif not IsPedDeadOrDying(ped, true) then
			local p = GetEntityCoords(ped)
			local hp = GetEntityHealth(ped) - 100
			local hurtNow = j.lastHp and hp < j.lastHp
			j.lastHp = hp
			if hurtNow then j.aggroUntil = t0 + 6000 end
			if j.returning then
				if #(p - j.home) < 3.0 then
					j.returning = false
					ClearPedTasks(ped)
				else
					if t0 > (j.cmd or 0) then
						j.cmd = t0 + 2000
						TaskGoToCoordAnyMeans(ped, j.home.x, j.home.y, j.home.z, 2.0, 0, false, 786603, 0.0)
					end
					SetEntityHealth(ped, math.min(100 + j.max, GetEntityHealth(ped) + math.floor(j.max * 0.05)))
				end
			else
				local best
				for _, f in ipairs(Lol.foes('neutral', p, 11.0, true)) do
					if not best or f.d < best.d then best = f end
				end
				if best and (not j.aggroUntil or t0 < j.aggroUntil or best.d < 8.0) then
					j.aggroUntil = j.aggroUntil or (t0 + 5000)
					if j.tgt ~= best.ped or t0 > (j.cmd or 0) then
						j.tgt, j.cmd = best.ped, t0 + 2500
						TaskCombatPed(ped, best.ped, 0, 16)
						if not j.roared then j.roared = true Sigf.Sound('jungle_roar', p, { range = 60.0, volume = 0.6 }) end
					end
				end
				if #(p - j.home) > 26.0 or (not best and j.aggroUntil and t0 > j.aggroUntil) then
					j.returning, j.tgt, j.aggroUntil, j.roared = true, nil, nil, false
					ClearPedTasks(ped)
				end
			end
		end
	end
end

local function buildCamps()
	for _, d in ipairs(CAMP_DEFS) do
		local cp = { def = d, pos = W(d.u, d.v), mobs = {} }
		CAMPS[#CAMPS + 1] = cp
		spawnCamp(cp)
	end
end

-- ---------- the void boss ----------
local function bossHeading(to)
	return GetHeadingFromVector_2d(to.x - BOSS.pos.x, to.y - BOSS.pos.y)
end

local function spawnBoss()
	skin('sigf_baron')
	local pos = W(0, 0.62 * T)
	local ent = Sigf.Prop('sigf_baron', pos, { ground = true, heading = L.dirHeading + 90.0 })
	if not ent then return end
	local hp = DEMO and 900 or 3000
	match.bossN = (match.bossN or 0) + 1
	BOSS = { id = 'boss' .. match.bossN, ent = ent, pos = GetEntityCoords(ent), hp = hp, max = hp, alive = true, r = 4.2, top = 8.0, born = now(), atk = 0, n = 0, base = GetEntityCoords(ent) }
	if not DEMO then banner('THE VOID NASHOR HAS AWAKENED', '#d98aff', 4) end
	feed('The Void Nashor has awakened in the top river', 'red')
	Sigf.Sound('baron_roar', BOSS.pos, { range = 220.0, volume = 1.0 })
	Sigf.Shake(0.3)
end

function Lol.hurtBoss(dmg, col, by)
	if not (BOSS and BOSS.alive) then return end
	BOSS.hitAt = now()
	BOSS.by = by or BOSS.by
	BOSS.agro = now() + 12000
	Sigf.Text3D(tostring(math.floor(dmg)), BOSS.pos + vector3(math.random() * 2 - 1, math.random() * 2 - 1, 5.5), 0.9, { color = col or { 255, 255, 255 }, scale = 0.6 })
	Sigf.Fx('core', 'exp_grd_bzgas_smoke', BOSS.pos + vector3(0, 0, 3 + math.random() * 3), { scale = 0.8 })
	if Lol.NET.on then Lol.netBossHit(dmg, by) return end       -- the server keeps its health
	BOSS.hp = BOSS.hp - dmg
	if BOSS.hp <= 0 then Lol.killBoss(BOSS.by) end
end

function Lol.killBoss(by)
	do
		BOSS.alive = false
		local p = BOSS.pos
		Sigf.Sound('baron_die', p, { range = 250.0, volume = 1.0 })
		Sigf.Shake(0.8)
		for i = 0, 5 do
			Sigf.After(i * 0.3, function()
				local q = p + vector3(math.random(-3, 3), math.random(-3, 3), 1.0 + i * 1.1)
				boom(q, 4, { scale = 0.6, shake = 1.0 })
				Sigf.Fx('core', 'exp_grd_molotov', q, { scale = 1.6 })
				Sigf.Light(q, { 190, 90, 255 }, 20.0, 12.0, 0.5)
			end)
		end
		local ent = BOSS.ent
		Sigf.After(2.0, function() Sigf.Remove(ent) end)
		Lol.bossSlain(by)
	end
end

local function bossTick()
	if not (BOSS and BOSS.alive) then return end
	local t0 = now()
	local p = BOSS.base
	local list = Lol.foes('neutral', p, 24.0, true)
	local best, target
	for _, f in ipairs(list) do
		local w = f.d - (f.champ and 6.0 or 0.0)
		if not best or w < best.w then best = f best.w = w end
	end
	target = best
	if target then
		SetEntityHeading(BOSS.ent, bossHeading(target.pos))
		if t0 > BOSS.atk then
			BOSS.atk = t0 + 2800
			BOSS.n = BOSS.n + 1
			local from = p + vector3(0, 0, 6.5)
			if BOSS.n % 3 == 0 then
				Sigf.Sound('baron_roar', p, { range = 120.0, volume = 0.7 })
				Sigf.Marker(1, p + vector3(0, 0, 0.2), vector3(15.0, 15.0, 0.2), { 200, 80, 255, 90 }, 0.7)
				Sigf.After(0.7, function()
					if not BOSS.alive then return end
					boom(p + vector3(0, 0, 0.5), 0, { scale = 0.0, shake = 0.6 })
					Sigf.Fx('core', 'exp_grd_molotov', p + vector3(0, 0, 0.5), { scale = 1.8 })
					for _, f in ipairs(Lol.foes('neutral', p, 7.5, true)) do
						hurt(f.ped, f.champ and 75 or 140, nil, { 200, 100, 255 })
						knock(f.ped, norm2(f.pos - p), 9.0)
					end
				end)
			else
				Sigf.Sound('baron_spit', p, { range = 120.0, volume = 0.8 })
				fx.beams[#fx.beams + 1] = { a = from, b = target.pos + vector3(0, 0, 1.0), col = { 190, 80, 255 }, to = t0 + 450 }
				Sigf.Light(from, { 190, 80, 255 }, 14.0, 9.0, 0.4)
				Sigf.Fx('core', 'exp_grd_bzgas_smoke', target.pos + vector3(0, 0, 0.8), { scale = 1.2 })
				hurt(target.ped, target.champ and 58 or 120, nil, { 200, 100, 255 })
				knock(target.ped, norm2(target.pos - p), 3.0)
			end
		end
	elseif t0 > (BOSS.agro or 0) and BOSS.hp < BOSS.max then
		BOSS.hp = math.min(BOSS.max, BOSS.hp + BOSS.max * 0.01)
	end
end


-- ---------- champions ----------
local ROSTER = {
	{ team = 'blue', name = 'AURELIA',    lane = 'mid', kit = 'mage',  hero = true, model = { 'u_m_y_imporage' }, weapon = 'WEAPON_CARBINERIFLE' },
	{ team = 'blue', name = 'KAEL',       lane = 'top', kit = 'brute', model = { 'u_m_m_juggernaut_03', 'u_m_y_juggernaut_02' }, weapon = 'WEAPON_ASSAULTSHOTGUN' },
	{ team = 'blue', name = 'MIRA',       lane = 'bot', kit = 'mage',  model = { 'ig_luchadora', 'a_f_y_hipster_02' }, weapon = 'WEAPON_SMG' },
	{ team = 'red',  name = 'VOIDREAVER', lane = 'mid', kit = 'brute', model = { 'u_m_y_pogo_01' }, weapon = 'WEAPON_ASSAULTSHOTGUN' },
	{ team = 'red',  name = 'SYTHE',      lane = 'top', kit = 'mage',  model = { 'u_m_y_zombie_01' }, weapon = 'WEAPON_CARBINERIFLE' },
	{ team = 'red',  name = 'KHARAX',     lane = 'bot', kit = 'brute', model = { 'ig_furry', 'u_m_y_zombie_01' }, weapon = 'WEAPON_COMBATMG' },
}
local CD = { mage = { q = 3.0, w = 9.0, e = 5.0, r = 18.0 }, brute = { q = 4.0, w = 10.0, e = 7.0, r = 22.0 } }
if DEMO then CD.mage.r = 8.0 end
Lol.CD = CD

champOf = function(ped)
	for _, c in ipairs(CH) do if c.ped == ped then return c end end
end

local function pickModel(list)
	for _, m in ipairs(list) do
		if IsModelInCdimage(GetHashKey(m)) then return m end
	end
	return 'a_m_y_beach_01'
end

-- stats from level, items and buffs
local function recalc(c)
	local dmg, cdr, ms, ls, hp = 0.07 * (c.lv - 1), 0.0, 0.0, 0.0, 0
	for _, id in ipairs(c.items) do
		local it = ITEMS[id]
		dmg, cdr, ms, ls, hp = dmg + (it.dmg or 0), cdr + (it.cdr or 0), ms + (it.ms or 0), ls + (it.ls or 0), hp + (it.hp or 0)
	end
	local dk = match.drk and match.drk[c.team]
	if dk then dmg, ms = dmg + 0.07 * dk, ms + 0.02 * dk end
	local bf = c.buff and now() < c.buff.to and BUFFS[c.buff.id]
	if bf then dmg, cdr = dmg + (bf.dmg or 0), cdr + (bf.cdr or 0) end
	if match.buff and match.buff.team == c.team and now() < match.buff.to then dmg, ms = dmg + 0.20, ms + 0.08 end
	c.mul, c.cdr, c.ms, c.ls = 1.0 + dmg, math.min(0.5, cdr), math.min(0.45, ms), ls
	local newMax = 440 + 38 * (c.lv - 1) + hp
	if newMax ~= c.hpmax then
		local old = c.hpmax or newMax
		c.hpmax = newMax
		if alive(c.ped) then
			SetPedMaxHealth(c.ped, 100 + newMax)
			SetEntityHealth(c.ped, math.min(100 + newMax, GetEntityHealth(c.ped) + math.max(0, newMax - old)))
		end
	end
end

local function newChamp(r)
	local c = { team = r.team, name = r.name, lane = r.lane, kit = r.kit, lv = 1, xp = 0, gold = DEMO and 500 or 500, items = {},
		kills = 0, deaths = 0, ready = { q = 0, w = 0, e = 0, r = 0 }, hero = r.hero, isPlayer = r.hero and PLAYER_HERO, r = r,
		remote = (r.human and r.human ~= Lol.NET.me) and r.human or nil, id = r.id }
	recalc(c)
	CH[#CH + 1] = c
	if r.hero then CH.hero = c end
	return c
end

local function fountainPos(team) return W(team == 'blue' and -N + 13.0 or N - 13.0, 0) end

local function equip(c)
	if not c.isPlayer then return end
	local me = c.ped
	local h = GetHashKey(c.r.weapon)
	GiveWeaponToPed(me, h, 9999, false, true)
	SetPedInfiniteAmmo(me, true, h)
	SetCurrentPedWeapon(me, h, true)
end

local function spawnChamp(c, atFountain)
	if c.remote then return end                 -- another player: their own game places them
	local r = c.r
	local fp = fountainPos(c.team)
	local lat = ({ mid = 0.0, top = 3.5, bot = -3.5 })[c.lane]
	local p = fp + L.side * lat * 1.0
	p = vector3(p.x, p.y, gz(p.x, p.y, fp.z))
	local face = c.team == 'blue' and L.dirHeading or (L.dirHeading + 180.0)
	if c.isPlayer then
		local mh = GetHashKey(pickModel(r.model))
		if GetEntityModel(PlayerPedId()) ~= mh then
			RequestModel(mh)
			local t = GetGameTimer() + 4000
			while not HasModelLoaded(mh) and GetGameTimer() < t do Wait(0) end
			if HasModelLoaded(mh) then SetPlayerModel(PlayerId(), mh) end
			SetPedCanRagdoll(PlayerPedId(), not DEMO)
		end
		c.ped = PlayerPedId()
		SetEntityCoords(c.ped, p.x, p.y, p.z + 1.0, false, false, false, false)
		SetEntityHeading(c.ped, face)
		if IsPedDeadOrDying(c.ped, true) then NetworkResurrectLocalPlayer(p.x, p.y, p.z + 1.0, face, true, false) end
		SetPedMaxHealth(c.ped, 100 + c.hpmax)
		SetEntityHealth(c.ped, 100 + c.hpmax)
		SetPedArmour(c.ped, 40)
		equip(c)
		if Lol.Dress then Lol.Dress(c) end
		return
	end
	local ped = Sigf.Ped(pickModel(r.model), p + vector3(0, 0, 0.6), { enemy = c.team == 'red', weapon = r.weapon, health = c.hpmax, armor = 40,
		accuracy = 45, fight = false, life = 0, heading = face })
	if not ped then return end
	c.ped = ped
	SetPedKeepTask(ped, true)
	SetPedCombatAttributes(ped, 46, true)
	SetPedCombatRange(ped, 2)
	SetPedFleeAttributes(ped, 0, false)
	if not atFountain then Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 1), { scale = 2.0 }) end
	Sigf.Light(p + vector3(0, 0, 1.0), COL[c.team], 10.0, 8.0, 0.8)
	if Lol.Dress then Lol.Dress(c) end
end

local function levelOf(xp)
	local lv = 1
	for i = 2, MAX_LV do if xp >= XP_NEED[i] then lv = i end end
	return lv
end

local function addXp(c, n)
	if c.lv >= MAX_LV then return end
	c.xp = c.xp + n
	local lv = levelOf(c.xp)
	if lv > c.lv then
		c.lv = lv
		recalc(c)
		if alive(c.ped) then
			local p = GetEntityCoords(c.ped)
			Sigf.Light(p + vector3(0, 0, 1.0), { 120, 255, 150 }, 10.0, 6.0, 0.8)
			Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 1), { scale = 2.0 })
			Sigf.Sound('levelup', p, { range = 60.0, volume = c.isPlayer and 0.9 or 0.4 })
			if c.isPlayer then Sigf.Nui({ levelup = lv }) end
		end
	end
end

local function itemOwned(c, id) for _, x in ipairs(c.items) do if x == id then return true end end return false end

local function buyItem(c, id, silent)
	local it = ITEMS[id]
	if not it or itemOwned(c, id) or #c.items >= 6 or c.gold < it.cost then return false end
	c.gold = c.gold - it.cost
	c.items[#c.items + 1] = id
	recalc(c)
	if c.isPlayer then
		Sigf.Sound('item_buy', nil, { volume = 0.8 })
		Sigf.Nui({ shop = { bought = id } })
		if not silent then banner('ITEM PURCHASED: ' .. it.name:upper(), '#ffd45a', 2.5) end
	end
	return true
end

local function autoBuy(c)
	for _, id in ipairs(AI_BUILD) do
		if not itemOwned(c, id) then
			buyItem(c, id, true)
			return
		end
	end
end

local function addGold(c, n, at)
	if not c then return end
	c.gold = c.gold + n
	if c.isPlayer then
		Sigf.Nui({ gold = { n = n } })
		if at then Sigf.Text3D('+' .. math.floor(n) .. 'g', at + vector3(0, 0, 1.2), 1.3, { color = { 255, 212, 90 }, scale = 0.5 }) end
		Sigf.Sound('gold', nil, { volume = 0.4 })
	end
end

-- gold for a whole team (turret plates); `by` (a ped) gets a bonus when it is a champion
function addTeamGold(team, n, by)
	for _, c in ipairs(CH) do
		if c.team == team then addGold(c, c.ped == by and n * 1.6 or n * 0.5) end
	end
end

-- xp for every champion of `team` that is near the dying thing
local function shareXp(team, pos, n, radius)
	for _, c in ipairs(CH) do
		if c.team == team and alive(c.ped) and #(GetEntityCoords(c.ped) - pos) <= (radius or 32.0) then addXp(c, n) end
	end
end

-- ---------- abilities ----------
local function aimDir(c, aim)
	local p = GetEntityCoords(c.ped)
	if aim then return norm2(aim - p) end
	if c.isPlayer and not DEMO then
		local r = GetGameplayCamRot(2)
		local h = math.rad(r.z)
		return vector3(-math.sin(h), math.cos(h), 0.0)
	end
	return norm2(GetEntityForwardVector(c.ped))
end

-- where the player's crosshair points on the ground (for the ultimate), within `maxd` metres
local function crosshair(c, maxd)
	local p = GetEntityCoords(c.ped)
	if not (c.isPlayer and not DEMO) then return nil end
	local cam = GetGameplayCamCoord()
	local r = GetGameplayCamRot(2)
	local rx, rz = math.rad(r.x), math.rad(r.z)
	local d = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
	local to = cam + d * 90.0
	local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16 + 8, c.ped, 4)
	local _, hit, pos = GetShapeTestResult(ray)
	local tgt = hit == 1 and pos or (p + norm2(d) * 18.0)
	local off = flat(tgt - p)
	if #off > maxd then tgt = p + off / #off * maxd end
	return vector3(tgt.x, tgt.y, gz(tgt.x, tgt.y, p.z))
end

local function faceDir(c, d) SetEntityHeading(c.ped, GetHeadingFromVector_2d(d.x, d.y)) end
local function ready(c, k) return now() >= c.ready[k] and not c.dead end

local function spend(c, k)
	local cd = CD[c.kit][k] * (1.0 - c.cdr)
	c.ready[k] = now() + math.floor(cd * 1000)
	c.cdTotal = c.cdTotal or {}
	c.cdTotal[k] = cd
	if c.isPlayer then Sigf.Nui({ cast = k }) end
end

local KIT = { mage = {}, brute = {} }
function Lol.Cast(c, k, aim, extra)
	if not c or not alive(c.ped) or not ready(c, k) then return false end
	local f = KIT[c.kit][k]
	if not f then return false end
	spend(c, k)
	f(c, aim, extra)
	return true
end
function Lol.Q(c, aim) return Lol.Cast(c, 'q', aim) end
function Lol.W(c, aim) return Lol.Cast(c, 'w', aim) end
function Lol.E(c, aim, dist) return Lol.Cast(c, 'e', aim, dist) end
function Lol.R(c, aim) return Lol.Cast(c, 'r', aim) end

-- mage -------------------------------------------------------------------
function KIT.mage.q(c, aim)
	Sigf.Sound('q_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local d = aimDir(c, aim)
	faceDir(c, d)
	local from = GetEntityCoords(c.ped) + vector3(0, 0, 0.2) + d * 0.8
	fx.projs[#fx.projs + 1] = { c = c, pos = from, dir = d, dist = 0.0, max = 46.0, speed = 36.0, hit = {}, trail = {}, col = COL[c.team], dmg = 85 * c.mul }
	Sigf.Light(from, COL[c.team], 8.0, 6.0, 0.25)
end

function KIT.mage.w(c)
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local p = GetEntityCoords(c.ped)
	fx.domes[#fx.domes + 1] = { c = c, to = now() + 4500, born = now(), col = COL[c.team] }
	c.guard = now() + 4500
	for _, ped in ipairs(Lol.allies(c.team, p, 9.0)) do
		SetPedArmour(ped, math.min(100, GetPedArmour(ped) + 45))
		local mx = GetEntityMaxHealth(ped)
		SetEntityHealth(ped, math.min(mx, GetEntityHealth(ped) + 45))
		Sigf.Text3D('+45', GetEntityCoords(ped) + vector3(0, 0, 0.8), 1.0, { color = { 110, 255, 140 }, scale = 0.5 })
	end
	Sigf.Light(p + vector3(0, 0, 1), COL[c.team], 12.0, 6.0, 1.0)
end

function KIT.mage.e(c, aim, dist)
	Sigf.Sound('e_dash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.7 })
	local d = aimDir(c, aim)
	faceDir(c, d)
	local a = GetEntityCoords(c.ped)
	fx.dashes[#fx.dashes + 1] = { c = c, a = a, d = d, len = dist or 13.0, t = 0.0, hit = {}, col = COL[c.team], dmg = 35, mode = 'phase' }
end

function KIT.mage.r(c, aim)
	Sigf.Sound('r_cast', nil, { volume = 0.7 })
	Sigf.LoadModel('prop_rock_1_a')
	local p = GetEntityCoords(c.ped)
	local tgt = aim or crosshair(c, 30.0) or (p + aimDir(c) * 16.0)
	faceDir(c, norm2(tgt - p))
	tgt = vector3(tgt.x, tgt.y, gz(tgt.x, tgt.y, p.z))
	fx.rings[#fx.rings + 1] = { pos = tgt, t0 = now(), warm = 1100, col = COL[c.team], c = c }
	banner(c.isPlayer and 'STARFALL!' or (c.name .. ' CASTS STARFALL'), c.isPlayer and '#ffb347' or '#ff6a50', 2.0)
end

-- brute ------------------------------------------------------------------
function KIT.brute.q(c, aim)
	Sigf.Sound('brute_slash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.9 })
	local d = aimDir(c, aim)
	faceDir(c, d)
	local p = GetEntityCoords(c.ped)
	fx.slashes[#fx.slashes + 1] = { pos = p, dir = d, t0 = now(), col = COL[c.team] }
	for _, f in ipairs(Lol.foes(c.team, p, 9.5)) do
		local dd = norm2(f.pos - p)
		if dot(dd, d) > 0.6 then
			hurt(f.ped, 90 * c.mul, c.ped, { 230, 120, 255 })
			knock(f.ped, d, 6.0)
			Sigf.Fx(Sigf.FX.blood[1], Sigf.FX.blood[2], f.pos + vector3(0, 0, 0.9), { scale = 1.0 })
			Sigf.Sound('camp_hit', f.pos, { range = 50.0, volume = 0.7 })
		end
	end
	hitThings(c.team, p + d * 4.0, 3.0, 40 * c.mul, { 230, 120, 255 }, c.ped)
end

function KIT.brute.w(c)
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.7 })
	c.guard = now() + 4000
	local p = GetEntityCoords(c.ped)
	SetPedArmour(c.ped, math.min(100, GetPedArmour(c.ped) + 50))
	local mx = GetEntityMaxHealth(c.ped)
	SetEntityHealth(c.ped, math.min(mx, GetEntityHealth(c.ped) + 70))
	Sigf.Text3D('+70', p + vector3(0, 0, 0.8), 1.0, { color = { 110, 255, 140 }, scale = 0.5 })
	fx.domes[#fx.domes + 1] = { c = c, to = now() + 4000, born = now(), col = { 190, 90, 255 } }
end

function KIT.brute.e(c, aim, dist)
	Sigf.Sound('brute_leap', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local p = GetEntityCoords(c.ped)
	local tgt = aim or crosshair(c, 14.0) or (p + aimDir(c) * 12.0)
	local d = norm2(tgt - p)
	faceDir(c, d)
	local len = math.min(dist or 14.0, #flat(tgt - p))
	fx.dashes[#fx.dashes + 1] = { c = c, a = p, d = d, len = math.max(5.0, len), t = 0.0, hit = {}, col = { 230, 120, 255 }, dmg = 0, mode = 'leap' }
end

function KIT.brute.r(c, aim)
	Sigf.Sound('brute_nova', GetEntityCoords(c.ped), { range = 90.0, volume = 1.0 })
	local p = GetEntityCoords(c.ped)
	faceDir(c, norm2((aim or p + aimDir(c)) - p))
	fx.novas[#fx.novas + 1] = { c = c, pos = p, t0 = now(), warm = 800, col = { 200, 90, 255 }, r = 11.0, dmg = 170 }
	banner(c.isPlayer and 'OBLIVION!' or (c.name .. ' UNLEASHES OBLIVION'), '#d98aff', 2.0)
end

local function meteorImpact(c, pos)
	boom(pos, 0, { scale = 0.0, shake = 0.4 })
	Sigf.Fx('core', 'exp_grd_molotov', pos, { scale = 0.7 })
	Sigf.Light(pos + vector3(0, 0, 1.5), { 255, 140, 40 }, 16.0, 10.0, 0.5)
	Sigf.Sound('r_hit', pos, { range = 90.0, volume = 0.5 })
	for _, f in ipairs(Lol.foes(c.team, pos, 5.5)) do
		hurt(f.ped, 150 * c.mul, c.ped, { 255, 160, 60 })
		knock(f.ped, norm2(f.pos - pos), 7.0)
	end
	hitThings(c.team, pos, 5.0, 22 * c.mul, { 255, 160, 60 }, c.ped)
end

local function novaImpact(n)
	local c, pos = n.c, n.pos
	boom(pos + vector3(0, 0, 0.3), 0, { scale = 0.0, shake = 0.8 })
	Sigf.Fx('core', 'exp_grd_molotov', pos, { scale = 1.4 })
	Sigf.Fx('core', 'exp_grd_grenade_lod', pos, { scale = 1.4 })
	Sigf.Light(pos + vector3(0, 0, 1.5), n.col, 18.0, 10.0, 0.6)
	for _, f in ipairs(Lol.foes(c.team, pos, n.r)) do
		hurt(f.ped, n.dmg * c.mul, c.ped, n.col)
		knock(f.ped, norm2(f.pos - pos), 11.0)
	end
	hitThings(c.team, pos, n.r - 4.0, 30 * c.mul, n.col, c.ped)
end


local function sphere(p, r, col, a)
	if #(p - GetFinalRenderedCamCoord()) < 2.6 then return end
	DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, r, col[1], col[2], col[3], a, false, false, 2, false, nil, nil, false)
end

local function ring(p, r, col, a, h)
	DrawMarker(1, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, h or 0.15, col[1], col[2], col[3], a, false, false, 2, false, nil, nil, false)
end

local function bar(p, frac, w, col)
	frac = clamp(frac, 0.0, 1.0)
	SetDrawOrigin(p.x, p.y, p.z, 0)
	DrawRect(0.0, 0.0, w + 0.002, 0.0105, 0, 0, 0, 200)
	DrawRect(-(w * (1 - frac)) / 2, 0.0, w * frac, 0.0075, col[1], col[2], col[3], 235)
	ClearDrawOrigin()
end

local function label(p, text, col, scale)
	SetDrawOrigin(p.x, p.y, p.z, 0)
	SetTextFont(4)
	SetTextScale(0.0, scale or 0.3)
	SetTextColour(col[1], col[2], col[3], 235)
	SetTextOutline()
	SetTextCentre(true)
	BeginTextCommandDisplayText('STRING')
	AddTextComponentSubstringPlayerName(text)
	EndTextCommandDisplayText(0.0, 0.0)
	ClearDrawOrigin()
end

local function hpFrac(ped, max) return (GetEntityHealth(ped) - 100 + GetPedArmour(ped)) / max end


-- ---------- the champion pack: eight champions, each with its own look and four abilities ----------
-- Aurelia (star mage) and Kael (void brute) come first; Vesper, Shade, Bastion, Lumi, Cinder and Voltaire are new.
do
local ZONES, SLOW, HASTE = {}, {}, {}

Lol.CHAMPS = {
	{ id = 'aurelia', name = 'AURELIA', title = 'The Star Mage', role = 'MAGE', kit = 'mage', col = { 110, 190, 255 },
	  model = { 'u_m_y_imporage' }, weapon = 'WEAPON_CARBINERIFLE',
	  abil = { 'Starbolt: a piercing skillshot', 'Aegis: a shield dome for allies', 'Phase: dash through the line', 'Starfall: a rain of meteors' } },
	{ id = 'kael', name = 'KAEL', title = 'The Void Warden', role = 'FIGHTER', kit = 'brute', col = { 200, 100, 255 },
	  model = { 'u_m_m_juggernaut_03', 'u_m_y_juggernaut_02' }, weapon = 'WEAPON_ASSAULTSHOTGUN',
	  abil = { 'Rend: a cone of dark energy', 'Mantle: a shield and heal', 'Leap: crash onto enemies', 'Oblivion: a huge shockwave' } },
	{ id = 'vesper', name = 'VESPER', title = 'The Hawk Ranger', role = 'MARKSMAN', kit = 'ranger', col = { 120, 230, 120 },
	  model = { 'cs_hunter', 'ig_hunter', 'a_m_m_hillbilly_01' }, weapon = 'WEAPON_MARKSMANRIFLE',
	  abil = { 'Piercing Arrow: a long fast shot', 'Roll: hop back and run faster', 'Arrow Volley: five arrows in a fan', 'Hawkshot: a giant arrow that stuns' } },
	{ id = 'shade', name = 'SHADE', title = 'The Night Blade', role = 'ASSASSIN', kit = 'assassin', col = { 215, 90, 255 },
	  model = { 's_m_y_blackops_01', 's_m_y_blackops_02', 's_m_y_swat_01' }, weapon = 'WEAPON_SMG',
	  abil = { 'Shadow Strike: dash and slash', 'Smoke Bomb: slow and vanish', 'Blink Strike: appear behind a target', 'Death Lotus: a flurry of strikes' } },
	{ id = 'bastion', name = 'BASTION', title = 'The Iron Wall', role = 'TANK', kit = 'tank', col = { 255, 200, 90 },
	  model = { 's_m_m_marine_01', 's_m_m_armoured_01', 's_m_y_armymech_01' }, weapon = 'WEAPON_PUMPSHOTGUN',
	  abil = { 'Shield Bash: stun in front', 'Iron Wall: half damage for 5 s', 'Seismic Slam: slow everyone near', 'Warlord Roar: pull and stun' } },
	{ id = 'lumi', name = 'LUMI', title = 'The Dawn Priestess', role = 'SUPPORT', kit = 'healer', col = { 255, 170, 225 },
	  model = { 'cs_priest', 'a_f_y_yoga_01', 'a_f_y_hipster_02' }, weapon = 'WEAPON_PISTOL',
	  abil = { 'Light Orb: damages and heals nearby allies', 'Mending Aura: heal your team', 'Haste Song: allies run faster', 'Sanctuary: a healing zone that burns foes' } },
	{ id = 'cinder', name = 'CINDER', title = 'The Pyromancer', role = 'MAGE', kit = 'pyro', col = { 255, 130, 30 },
	  model = { 's_m_y_fireman_01', 'u_m_y_pogo_01' }, weapon = 'WEAPON_FLAREGUN',
	  abil = { 'Flame Breath: a cone of real fire', 'Heat Wave: burn everything around', 'Fireball: explodes on impact', 'Inferno: a field of fire' } },
	{ id = 'voltaire', name = 'VOLTAIRE', title = 'The Storm Caller', role = 'MAGE', kit = 'storm', col = { 140, 210, 255 },
	  model = { 'u_m_m_jesus_01', 'cs_old_man2', 'u_m_y_imporage' }, weapon = 'WEAPON_MICROSMG',
	  abil = { 'Chain Lightning: jumps between foes', 'Static Field: a slowing zone', 'Thunder Step: blink with lightning', 'Tempest: a storm of lightning strikes' } },
}
Lol.CHAMP = {}
for _, ch in ipairs(Lol.CHAMPS) do Lol.CHAMP[ch.id] = ch end

CD.ranger   = { q = 3.5, w = 8.0, e = 6.0, r = 20.0 }
CD.assassin = { q = 3.5, w = 10.0, e = 6.0, r = 20.0 }
CD.tank     = { q = 4.0, w = 11.0, e = 7.0, r = 22.0 }
CD.healer   = { q = 3.0, w = 8.0, e = 12.0, r = 22.0 }
CD.pyro     = { q = 3.5, w = 7.0, e = 5.0, r = 20.0 }
CD.storm    = { q = 3.0, w = 9.0, e = 6.0, r = 22.0 }
if DEMO then for _, k in ipairs({ 'ranger', 'assassin', 'tank', 'healer', 'pyro', 'storm' }) do CD[k].r = 9.0 end end
for _, k in ipairs({ 'ranger', 'assassin', 'tank', 'healer', 'pyro', 'storm' }) do KIT[k] = {} end

-- ---------- helpers ----------
local function bolt(a, b, col, ms)
	local n, prev = 7, a
	for i = 1, n do
		local q = a + (b - a) * (i / n)
		if i < n then q = q + vector3((math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.2) end
		fx.beams[#fx.beams + 1] = { a = prev, b = q, col = col, to = now() + (ms or 200), nos = true, w = 2 }
		prev = q
	end
	sphere(b, 0.6, col, 150)
end

local function stun(ped, ms)
	if not alive(ped) or ped == PlayerPedId() then return end
	SetPedToRagdoll(ped, ms, ms, 0, false, false, false)
end
function Lol.slow(ped, ms) SLOW[ped] = now() + ms end
function Lol.haste(ped, ms) HASTE[ped] = now() + ms end

local function foesIn(c, pos, r) return Lol.foes(c.team, pos, r) end

local function strike(c, pos, r, dmg, col)
	bolt(pos + vector3(math.random() * 5 - 2.5, math.random() * 5 - 2.5, 40.0), pos + vector3(0, 0, 0.3), { 220, 235, 255 }, 280)
	Sigf.Fx('core', 'ent_amb_elec_crackle', pos, { scale = 1.6 })
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], pos + vector3(0, 0, 0.5), { scale = 2.0 })
	Sigf.Marker(1, pos, vector3(0.9, 0.9, 45.0), { 190, 225, 255, 190 }, 0.22)
	Sigf.Marker(1, pos, vector3(0.35, 0.35, 45.0), { 255, 255, 255, 255 }, 0.22)
	Sigf.Light(pos + vector3(0, 0, 2.0), col or { 160, 210, 255 }, 20.0, 14.0, 0.3)
	Sigf.Sound('turret_zap', pos, { range = 90.0, volume = 0.6 })
	Sigf.Shake(0.12, 'SMALL_EXPLOSION_SHAKE')
	for _, f in ipairs(foesIn(c, pos, r)) do
		hurt(f.ped, dmg * c.mul, c.ped, col or { 160, 210, 255 })
		knock(f.ped, norm2(f.pos - pos), 4.0)
	end
	hitThings(c.team, pos, r, dmg * 0.4 * c.mul, col or { 160, 210, 255 }, c.ped)
end

local function nearestFoe(c, range, aim)
	local p = GetEntityCoords(c.ped)
	local d = aimDir(c, aim)
	local best
	for _, f in ipairs(foesIn(c, p, range)) do
		if dot(norm2(f.pos - p), d) > (c.isPlayer and not DEMO and 0.6 or -0.2) then
			local w = f.d - (f.champ and 4.0 or 0.0)
			if not best or w < best.w then best = f best.w = w end
		end
	end
	return best, p, d
end

local function zone(c, pos, r, sec, col, every, onTick, kind)
	ZONES[#ZONES + 1] = { c = c, pos = pos, r = r, to = now() + sec * 1000, col = col, every = every * 1000, nextT = now() + 200, onTick = onTick, kind = kind, born = now() }
end

local function arrow(c, d, speed, max, dmg, opts)
	local from = GetEntityCoords(c.ped) + vector3(0, 0, 0.3) + d * 0.8
	local q = { c = c, pos = from, dir = d, dist = 0.0, max = max, speed = speed, hit = {}, trail = {}, col = c.r.col or COL[c.team], dmg = dmg * c.mul }
	for k, v in pairs(opts or {}) do q[k] = v end
	fx.projs[#fx.projs + 1] = q
	return q
end

local function colOf(c) return c.r.col or COL[c.team] end

-- ---------- ranger: Vesper ----------
function KIT.ranger.q(c, aim)
	Sigf.Sound('q_cast', GetEntityCoords(c.ped), { range = 80.0, volume = 0.8 })
	local d = aimDir(c, aim) faceDir(c, d)
	arrow(c, d, 78.0, 75.0, 95, { rad = 1.6, hcol = { 150, 255, 150 } })
end
function KIT.ranger.w(c)
	Sigf.Sound('e_dash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.7 })
	local d = norm2(GetEntityForwardVector(c.ped)) * -1.0
	c.hasteUntil = now() + 3500
	Lol.haste(c.ped, 3500)
	fx.dashes[#fx.dashes + 1] = { c = c, a = GetEntityCoords(c.ped), d = d, len = 8.5, t = 0.0, hit = {}, col = colOf(c), dmg = 0, mode = 'phase' }
end
function KIT.ranger.e(c, aim)
	Sigf.Sound('q_cast', GetEntityCoords(c.ped), { range = 80.0, volume = 0.9 })
	local d = aimDir(c, aim) faceDir(c, d)
	local base = math.atan2(d.y, d.x)
	for k = -2, 2 do
		local a = base + k * 0.16
		arrow(c, vector3(math.cos(a), math.sin(a), 0.0), 48.0, 26.0, 48, { stop = true, rad = 1.3, hcol = { 150, 255, 150 } })
	end
end
function KIT.ranger.r(c, aim)
	Sigf.Sound('r_cast', nil, { volume = 0.8 })
	banner(c.isPlayer and 'HAWKSHOT!' or (c.name .. ' LOOSES A HAWKSHOT'), '#8cff8c', 1.8)
	local d = aimDir(c, aim) faceDir(c, d)
	arrow(c, d, 62.0, 95.0, 230, { rad = 3.0, kb = 10.0, hcol = { 200, 255, 160 },
		onHit = function(f) stun(f.ped, 1300) Sigf.Fx(Sigf.FX.firework[1], Sigf.FX.firework[2], f.pos + vector3(0, 0, 1.5), { scale = 1.0 }) end })
end

-- ---------- assassin: Shade ----------
function KIT.assassin.q(c, aim)
	Sigf.Sound('brute_slash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.9 })
	local d = aimDir(c, aim) faceDir(c, d)
	fx.dashes[#fx.dashes + 1] = { c = c, a = GetEntityCoords(c.ped), d = d, len = 10.0, t = 0.0, hit = {}, col = colOf(c), dmg = 80, mode = 'phase' }
	fx.slashes[#fx.slashes + 1] = { pos = GetEntityCoords(c.ped), dir = d, t0 = now(), col = colOf(c) }
end
function KIT.assassin.w(c)
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.7 })
	local p = GetEntityCoords(c.ped)
	Sigf.Fx('core', 'exp_grd_bzgas_smoke', p, { scale = 3.0 })
	Sigf.Fx('core', 'exp_grd_bzgas_smoke', p + vector3(1.5, 0, 0), { scale = 2.0 })
	for _, f in ipairs(foesIn(c, p, 7.0)) do Lol.slow(f.ped, 2800) hurt(f.ped, 20 * c.mul, c.ped, colOf(c)) end
	c.hasteUntil = now() + 2800
	Lol.haste(c.ped, 2800)
	c.guard = now() + 1500
	SetEntityAlpha(c.ped, 70, false)
	Sigf.After(2.8, function() if DoesEntityExist(c.ped) then ResetEntityAlpha(c.ped) end end)
	fx.bursts[#fx.bursts + 1] = { p = p - vector3(0, 0, 0.9), to = now() + 700, col = colOf(c), r = 8.0 }
end
function KIT.assassin.e(c, aim)
	Sigf.Sound('e_dash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local f, p, d = nearestFoe(c, 22.0, aim)
	local from = p
	local to
	if f then
		local dd = norm2(f.pos - p)
		to = f.pos + dd * 1.6
		to = vector3(to.x, to.y, gz(to.x, to.y, f.pos.z))
		SetEntityCoords(c.ped, to.x, to.y, to.z + 0.4, false, false, false, false)
		SetEntityHeading(c.ped, GetHeadingFromVector_2d(-dd.x, -dd.y))
		hurt(f.ped, 115 * c.mul, c.ped, colOf(c))
		knock(f.ped, dd, 4.0)
		Sigf.Sound('camp_hit', f.pos, { range = 50.0, volume = 0.8 })
		Sigf.Fx(Sigf.FX.blood[1], Sigf.FX.blood[2], f.pos + vector3(0, 0, 0.9), { scale = 1.0 })
	else
		to = p + d * 10.0
		to = vector3(to.x, to.y, gz(to.x, to.y, p.z))
		SetEntityCoords(c.ped, to.x, to.y, to.z + 0.4, false, false, false, false)
	end
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], from + vector3(0, 0, 1.0), { scale = 2.5 })
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], to + vector3(0, 0, 1.0), { scale = 2.5 })
	Sigf.Light(to + vector3(0, 0, 1.0), colOf(c), 10.0, 8.0, 0.4)
	fx.bursts[#fx.bursts + 1] = { p = to - vector3(0, 0, 0.9), to = now() + 700, col = colOf(c), r = 5.0 }
end
function KIT.assassin.r(c, aim)
	Sigf.Sound('brute_nova', GetEntityCoords(c.ped), { range = 90.0, volume = 0.8 })
	banner(c.isPlayer and 'DEATH LOTUS!' or (c.name .. ' UNLEASHES DEATH LOTUS'), '#e08aff', 1.8)
	c.guard = now() + 2200
	for i = 1, 5 do
		Sigf.After(i * 0.3, function()
			if not alive(c.ped) then return end
			local p = GetEntityCoords(c.ped)
			local list = foesIn(c, p, 14.0)
			table.sort(list, function(a, b) return a.d < b.d end)
			local f = list[1]
			if f then
				local dd = norm2(f.pos - p)
				local to = f.pos - dd * 1.3
				to = vector3(to.x, to.y, gz(to.x, to.y, f.pos.z))
				SetEntityCoords(c.ped, to.x, to.y, to.z + 0.4, false, false, false, false)
				SetEntityHeading(c.ped, GetHeadingFromVector_2d(dd.x, dd.y))
				hurt(f.ped, 70 * c.mul, c.ped, colOf(c))
				knock(f.ped, dd, 2.5)
				fx.slashes[#fx.slashes + 1] = { pos = to, dir = dd, t0 = now(), col = colOf(c) }
				Sigf.Fx(Sigf.FX.blood[1], Sigf.FX.blood[2], f.pos + vector3(0, 0, 0.9), { scale = 1.2 })
				Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], to + vector3(0, 0, 1.0), { scale = 2.0 })
				Sigf.Sound('brute_slash', f.pos, { range = 60.0, volume = 0.6 })
			end
		end)
	end
end

-- ---------- tank: Bastion ----------
function KIT.tank.q(c, aim)
	Sigf.Sound('brute_slash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.9 })
	local d = aimDir(c, aim) faceDir(c, d)
	local p = GetEntityCoords(c.ped)
	fx.slashes[#fx.slashes + 1] = { pos = p, dir = d, t0 = now(), col = colOf(c) }
	for _, f in ipairs(foesIn(c, p, 6.5)) do
		if dot(norm2(f.pos - p), d) > 0.5 then
			hurt(f.ped, 60 * c.mul, c.ped, colOf(c))
			knock(f.ped, d, 7.0)
			stun(f.ped, 1100)
			Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], f.pos + vector3(0, 0, 0.9), { scale = 1.8 })
			Sigf.Sound('shield_hit', f.pos, { range = 50.0, volume = 0.8 })
		end
	end
	hitThings(c.team, p + d * 3.0, 3.0, 40 * c.mul, colOf(c), c.ped)
end
function KIT.tank.w(c)
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	c.guard = now() + 5000
	SetPedArmour(c.ped, math.min(100, GetPedArmour(c.ped) + 60))
	fx.domes[#fx.domes + 1] = { c = c, to = now() + 5000, born = now(), col = colOf(c) }
	Sigf.Text3D('IRON WALL', GetEntityCoords(c.ped) + vector3(0, 0, 1.0), 1.2, { color = { 255, 220, 120 }, scale = 0.5 })
end
function KIT.tank.e(c)
	Sigf.Sound('brute_nova', GetEntityCoords(c.ped), { range = 90.0, volume = 0.9 })
	local p = GetEntityCoords(c.ped)
	boom(p + vector3(0, 0, 0.3), 0, { scale = 0.0, shake = 0.6 })
	Sigf.Fx('core', 'exp_grd_grenade_lod', p, { scale = 1.8 })
	Sigf.Fx('core', 'exp_grd_grenade_lod', p, { scale = 1.0 })
	for _, f in ipairs(foesIn(c, p, 8.0)) do
		hurt(f.ped, 75 * c.mul, c.ped, colOf(c))
		Lol.slow(f.ped, 3000)
		knock(f.ped, norm2(f.pos - p), 5.0)
	end
	hitThings(c.team, p, 6.0, 35 * c.mul, colOf(c), c.ped)
	fx.bursts[#fx.bursts + 1] = { p = p - vector3(0, 0, 0.9), to = now() + 700, col = colOf(c), r = 16.0 }
end
function KIT.tank.r(c)
	Sigf.Sound('baron_roar', GetEntityCoords(c.ped), { range = 100.0, volume = 0.8 })
	banner(c.isPlayer and 'WARLORD ROAR!' or (c.name .. ' ROARS'), '#ffd070', 1.8)
	local p = GetEntityCoords(c.ped)
	fx.novas[#fx.novas + 1] = { c = c, pos = p, t0 = now(), warm = 500, col = colOf(c), r = 8.0, dmg = 0 }
	for _, f in ipairs(foesIn(c, p, 17.0)) do
		local dd = norm2(p - f.pos)
		if f.champ and f.ped == PlayerPedId() then
			SetEntityVelocity(f.ped, dd.x * 14.0, dd.y * 14.0, 2.0)
		else
			SetPedToRagdoll(f.ped, 1500, 1500, 0, false, false, false)
			SetEntityVelocity(f.ped, dd.x * 16.0, dd.y * 16.0, 3.0)
		end
		hurt(f.ped, 80 * c.mul, c.ped, colOf(c))
		Sigf.After(0.5, function() if alive(f.ped) then stun(f.ped, 1200) end end)
	end
end

-- ---------- healer: Lumi ----------
local function healAround(c, pos, r, amount)
	for _, ped in ipairs(Lol.allies(c.team, pos, r)) do
		local mx = GetEntityMaxHealth(ped)
		SetEntityHealth(ped, math.min(mx, GetEntityHealth(ped) + amount))
		Sigf.Text3D('+' .. amount, GetEntityCoords(ped) + vector3(0, 0, 0.8), 1.0, { color = { 110, 255, 140 }, scale = 0.5 })
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], GetEntityCoords(ped) + vector3(0, 0, 0.5), { scale = 1.0 })
	end
end
function KIT.healer.q(c, aim)
	Sigf.Sound('q_cast', GetEntityCoords(c.ped), { range = 80.0, volume = 0.7 })
	local d = aimDir(c, aim) faceDir(c, d)
	arrow(c, d, 32.0, 40.0, 70, { stop = true, rad = 1.8, hcol = { 255, 220, 240 },
		onHit = function(f, q) healAround(c, f.pos, 8.0, 40) end,
		onEnd = function(q) Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], q.pos, { scale = 1.6 }) end })
end
function KIT.healer.w(c)
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local p = GetEntityCoords(c.ped)
	healAround(c, p, 11.0, 130)
	Sigf.Light(p + vector3(0, 0, 1), { 140, 255, 160 }, 14.0, 8.0, 1.0)
	fx.bursts[#fx.bursts + 1] = { p = p - vector3(0, 0, 0.9), to = now() + 700, col = { 140, 255, 160 }, r = 22.0 }
	fx.domes[#fx.domes + 1] = { c = c, to = now() + 1500, born = now(), col = { 140, 255, 160 } }
end
function KIT.healer.e(c)
	Sigf.Sound('e_dash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local p = GetEntityCoords(c.ped)
	for _, ped in ipairs(Lol.allies(c.team, p, 15.0)) do
		Lol.haste(ped, 4500)
		local ch = champOf(ped)
		if ch then ch.hasteUntil = now() + 4500 end
		SetPedArmour(ped, math.min(100, GetPedArmour(ped) + 25))
		Sigf.Fx(Sigf.FX.firework[1], Sigf.FX.firework[2], GetEntityCoords(ped) + vector3(0, 0, 2.0), { scale = 0.6 })
	end
	fx.bursts[#fx.bursts + 1] = { p = p - vector3(0, 0, 0.9), to = now() + 700, col = { 255, 230, 120 }, r = 28.0 }
end
function KIT.healer.r(c)
	Sigf.Sound('r_cast', nil, { volume = 0.7 })
	banner(c.isPlayer and 'SANCTUARY!' or (c.name .. ' RAISES SANCTUARY'), '#ffc8ec', 1.8)
	local p = GetEntityCoords(c.ped)
	p = vector3(p.x, p.y, p.z)
	zone(c, p, 9.5, 6.0, { 255, 200, 240 }, 0.5, function(z)
		for _, ped in ipairs(Lol.allies(c.team, z.pos, z.r)) do
			local mx = GetEntityMaxHealth(ped)
			SetEntityHealth(ped, math.min(mx, GetEntityHealth(ped) + 30))
		end
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], z.pos + vector3((math.random() - 0.5) * 12, (math.random() - 0.5) * 12, 0.5), { scale = 1.2 })
		for _, f in ipairs(foesIn(c, z.pos, z.r)) do hurt(f.ped, 22 * c.mul, c.ped, { 255, 200, 240 }) end
	end, 'heal')
end

-- ---------- pyromancer: Cinder ----------
function KIT.pyro.q(c, aim)
	Sigf.Sound('r_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.6 })
	local d = aimDir(c, aim) faceDir(c, d)
	for i = 1, 9 do
		Sigf.After(i * 0.15, function()
			if not alive(c.ped) then return end
			local p = GetEntityCoords(c.ped)
			local dd = norm2(GetEntityForwardVector(c.ped))
			local sd = vector3(-dd.y, dd.x, 0.0)
			-- a widening stream of real flames
			for k = 1, 5 do
				local reach = 1.6 + k * 1.7
				local q = p + dd * reach + sd * ((math.random() - 0.5) * reach * 0.35) + vector3(0, 0, -0.6)
				Sigf.Fx('core', 'ent_sht_flame', q, { scale = 0.6 + k * 0.2, loop = true, life = 0.5 })
			end
			Sigf.Fx('core', 'exp_grd_molotov_lod', p + dd * 8.5 + vector3(0, 0, -0.5), { scale = 0.6 })
			Sigf.Light(p + dd * 5.0 + vector3(0, 0, 0.8), { 255, 140, 30 }, 12.0, 8.0, 0.25)
			for _, f in ipairs(foesIn(c, p, 10.5)) do
				if dot(norm2(f.pos - p), dd) > 0.74 then
					hurt(f.ped, 20 * c.mul, c.ped, { 255, 150, 40 })
					Sigf.Fx('core', 'ent_sht_flame', f.ped, { loop = true, life = 1.2, scale = 0.8, offset = vector3(0, 0, 0.2) })
				end
			end
			hitThings(c.team, p + dd * 5.0, 3.5, 8 * c.mul, { 255, 150, 40 }, c.ped)
		end)
	end
end
function KIT.pyro.w(c)
	Sigf.Sound('brute_nova', GetEntityCoords(c.ped), { range = 80.0, volume = 0.7 })
	local p = GetEntityCoords(c.ped)
	for k = 0, 7 do
		local a = k * 0.785
		Sigf.Fx('core', 'exp_grd_molotov_lod', p + vector3(math.cos(a) * 3.5, math.sin(a) * 3.5, 0.0), { scale = 0.9 })
	end
	Sigf.Light(p + vector3(0, 0, 1), { 255, 120, 30 }, 16.0, 10.0, 0.6)
	for _, f in ipairs(foesIn(c, p, 6.0)) do
		hurt(f.ped, 55 * c.mul, c.ped, { 255, 150, 40 })
		knock(f.ped, norm2(f.pos - p), 7.0)
		Sigf.Fx('core', 'ent_sht_flame', f.ped, { loop = true, life = 2.0, scale = 1.0 })
	end
	hitThings(c.team, p, 5.0, 25 * c.mul, { 255, 150, 40 }, c.ped)
	fx.bursts[#fx.bursts + 1] = { p = p - vector3(0, 0, 0.9), to = now() + 700, col = { 255, 130, 30 }, r = 14.0 }
end
function KIT.pyro.e(c, aim)
	Sigf.Sound('q_cast', GetEntityCoords(c.ped), { range = 80.0, volume = 0.8 })
	local d = aimDir(c, aim) faceDir(c, d)
	local function blast(pos)
		boom(pos, 0, { scale = 0.0, shake = 0.4 })
		Sigf.Fx('core', 'exp_grd_molotov', pos, { scale = 1.2 })
		Sigf.Light(pos + vector3(0, 0, 1.0), { 255, 130, 30 }, 16.0, 10.0, 0.5)
		Sigf.Sound('r_hit', pos, { range = 80.0, volume = 0.5 })
		for _, f in ipairs(foesIn(c, pos, 5.0)) do
			hurt(f.ped, 60 * c.mul, c.ped, { 255, 150, 40 })
			knock(f.ped, norm2(f.pos - pos), 6.0)
			Sigf.Fx('core', 'ent_sht_flame', f.ped, { loop = true, life = 1.5, scale = 0.8 })
		end
		hitThings(c.team, pos, 4.5, 40 * c.mul, { 255, 150, 40 }, c.ped)
	end
	arrow(c, d, 30.0, 40.0, 70, { stop = true, rad = 1.7, col = { 255, 150, 40 }, hcol = { 255, 150, 40 }, onEnd = function(q) blast(q.pos) end })
end
function KIT.pyro.r(c, aim)
	Sigf.Sound('r_cast', nil, { volume = 0.7 })
	banner(c.isPlayer and 'INFERNO!' or (c.name .. ' LIGHTS THE INFERNO'), '#ff9a40', 1.8)
	local p = GetEntityCoords(c.ped)
	local tgt = aim or crosshair(c, 24.0) or (p + aimDir(c) * 12.0)
	faceDir(c, norm2(tgt - p))
	tgt = vector3(tgt.x, tgt.y, gz(tgt.x, tgt.y, p.z))
	zone(c, tgt, 8.5, 0.7, { 255, 120, 30 }, 99.0, function() end, 'tele')
	Sigf.After(0.7, function()
		boom(tgt, 0, { scale = 0.0, shake = 0.8 })
		Sigf.Fx('core', 'exp_grd_molotov', tgt, { scale = 2.5 })
		zone(c, tgt, 8.5, 4.5, { 255, 110, 20 }, 0.5, function(z)
			for k = 1, 3 do
				local a, rr = math.random() * 6.283, math.sqrt(math.random()) * z.r
				Sigf.Fx('core', 'ent_sht_flame', z.pos + vector3(math.cos(a) * rr, math.sin(a) * rr, 0.0), { scale = 1.3, loop = true, life = 0.9 })
			end
			for _, f in ipairs(foesIn(c, z.pos, z.r)) do
				hurt(f.ped, 32 * c.mul, c.ped, { 255, 150, 40 })
				Sigf.Fx('core', 'ent_sht_flame', f.ped, { loop = true, life = 0.8, scale = 0.7 })
			end
			hitThings(c.team, z.pos, z.r - 2.0, 12 * c.mul, { 255, 150, 40 }, c.ped)
		end, 'fire')
	end)
end

-- ---------- stormcaller: Voltaire ----------
function KIT.storm.q(c, aim)
	Sigf.Sound('turret_zap', GetEntityCoords(c.ped), { range = 80.0, volume = 0.9 })
	local f, p, d = nearestFoe(c, 30.0, aim)
	faceDir(c, d)
	local from = p + vector3(0, 0, 1.2)
	if not f then
		bolt(from, from + d * 18.0, { 170, 215, 255 }, 250)
		return
	end
	local hit, cur, dmg = { [f.ped] = true }, f, 75
	for i = 1, 4 do
		bolt(from, cur.pos + vector3(0, 0, 0.9), { 200, 235, 255 }, 380)
		hurt(cur.ped, dmg * c.mul, c.ped, { 170, 215, 255 })
		knock(cur.ped, norm2(cur.pos - p), 2.5)
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], cur.pos + vector3(0, 0, 0.9), { scale = 1.6 })
		Sigf.Sound('q_hit', cur.pos, { range = 60.0, volume = 0.5 })
		from = cur.pos + vector3(0, 0, 0.9)
		local nxt
		for _, g in ipairs(foesIn(c, cur.pos, 11.0)) do
			if not hit[g.ped] and (not nxt or g.d < nxt.d) then nxt = g end
		end
		if not nxt then break end
		hit[nxt.ped] = true
		cur, dmg = nxt, dmg - 12
	end
end
function KIT.storm.w(c)
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.7 })
	local p = GetEntityCoords(c.ped)
	zone(c, p, 7.0, 4.5, { 150, 210, 255 }, 0.5, function(z)
		Sigf.Fx('core', 'ent_amb_elec_crackle', z.pos + vector3((math.random() - 0.5) * 10, (math.random() - 0.5) * 10, 0.3), { scale = 1.2 })
		for _, f in ipairs(foesIn(c, z.pos, z.r)) do
			Lol.slow(f.ped, 900)
			hurt(f.ped, 16 * c.mul, c.ped, { 170, 215, 255 })
			bolt(z.pos + vector3(0, 0, 0.6), f.pos + vector3(0, 0, 0.6), { 170, 215, 255 }, 160)
		end
	end, 'static')
end
function KIT.storm.e(c, aim)
	Sigf.Sound('e_dash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local d = aimDir(c, aim) faceDir(c, d)
	local a = GetEntityCoords(c.ped)
	local to = a + d * 11.0
	to = vector3(to.x, to.y, gz(to.x, to.y, a.z))
	strike(c, a, 3.5, 45, { 160, 210, 255 })
	SetEntityCoords(c.ped, to.x, to.y, to.z + 0.4, false, false, false, false)
	Sigf.After(0.12, function() strike(c, to, 3.5, 45, { 160, 210, 255 }) end)
end
function KIT.storm.r(c, aim)
	Sigf.Sound('r_cast', nil, { volume = 0.8 })
	banner(c.isPlayer and 'TEMPEST!' or (c.name .. ' CALLS THE TEMPEST'), '#9fd4ff', 1.8)
	local p = GetEntityCoords(c.ped)
	local ctr = aim or crosshair(c, 22.0) or (p + aimDir(c) * 12.0)
	ctr = vector3(ctr.x, ctr.y, gz(ctr.x, ctr.y, p.z))
	zone(c, ctr, 12.0, 0.7, { 140, 200, 255 }, 99.0, function() end, 'tele')
	for i = 1, 14 do
		Sigf.After(0.5 + i * 0.22, function()
			if not alive(c.ped) then return end
			local list = foesIn(c, ctr, 14.0)
			local pos
			if #list > 0 and i % 2 == 1 then pos = list[math.random(#list)].pos
			else
				local a, rr = math.random() * 6.283, math.sqrt(math.random()) * 9.0
				pos = ctr + vector3(math.cos(a) * rr, math.sin(a) * rr, 0.0)
			end
			strike(c, vector3(pos.x, pos.y, gz(pos.x, pos.y, ctr.z)), 3.6, 62, { 160, 210, 255 })
		end)
	end
end

-- ---------- zones, slows and hastes ----------
Sigf.Frame(function(dt)
	if not match or not match.running then return end
	local t0 = now()
	for ped, to in pairs(SLOW) do
		if t0 > to or not DoesEntityExist(ped) then SLOW[ped] = nil else SetPedMoveRateOverride(ped, 0.45) end
	end
	for ped, to in pairs(HASTE) do
		if t0 > to or not DoesEntityExist(ped) then HASTE[ped] = nil
		elseif ped ~= PlayerPedId() then SetPedMoveRateOverride(ped, 1.4) end
	end
	for i = #ZONES, 1, -1 do
		local z = ZONES[i]
		if t0 > z.to then table.remove(ZONES, i)
		else
			local fade = math.min(1.0, (z.to - t0) / 500.0, (t0 - z.born) / 300.0)
			local pulse = 1.0 + math.sin(t0 / 200.0) * 0.03
			ring(z.pos - vector3(0, 0, 0.85), z.r * 2.0 * pulse, z.col, math.floor(70 * fade), 0.12)
			ring(z.pos - vector3(0, 0, 0.85), z.r * 1.2, z.col, math.floor(50 * fade), 0.12)
			DrawLightWithRange(z.pos.x, z.pos.y, z.pos.z + 1.5, z.col[1], z.col[2], z.col[3], z.r * 1.6, 3.0 * fade)
			if t0 >= z.nextT then
				z.nextT = t0 + z.every
				Sigf.Safe('zone', z.onTick, z)
			end
		end
	end
end, 'lol_champs')

-- ---------- each champion's own look: a held prop and a particle aura ----------
local DRESS = {
	bastion  = { prop = 'prop_riot_shield', bone = 18905, off = vector3(0.1, 0.05, 0.0), rot = vector3(0.0, 90.0, 0.0) },
	voltaire = { prop = 'prop_cs_walking_stick', bone = 57005, off = vector3(0.08, 0.0, -0.1), rot = vector3(0.0, 0.0, 0.0),
	             aura = { 'core', 'ent_amb_elec_crackle', 0.5, vector3(0, 0, 0.1) } },
	cinder   = { aura = { 'core', 'ent_sht_flame', 0.22, vector3(0, 0, -0.55) } },
}
function Lol.Dress(c)
	local d = DRESS[c.id]
	if not d or not c.ped or not DoesEntityExist(c.ped) or c.remote then return end
	if c.dressPed == c.ped then return end
	c.dressPed = c.ped
	if c.dressProp then Sigf.Remove(c.dressProp) c.dressProp = nil end
	if d.aura then c.dressFx = Sigf.Fx(d.aura[1], d.aura[2], c.ped, { loop = true, scale = d.aura[3], offset = d.aura[4] }) end
	if d.prop then
		local e = Sigf.Prop(d.prop, GetEntityCoords(c.ped) + vector3(0, 0, 2.0), { frozen = false, life = 0 })
		if e then
			SetEntityCollision(e, false, false)
			Sigf.Attach(e, c.ped, d.bone, d.off, d.rot)
			c.dressProp = e
		end
	end
end

-- ---------- what the AI champions do with each kit ----------
Lol.AI = {}
Lol.AI.ranger = function(c, best, list, hp)
	if best.d < 62.0 then Lol.Q(c, best.pos) end
	if best.d < 18.0 then Lol.E(c, best.pos) end
	if best.d < 8.0 then Lol.W(c) end
	if best.champ and best.d < 55.0 and #list >= 1 then Lol.R(c, best.pos) end
end
Lol.AI.assassin = function(c, best, list, hp)
	if best.champ and best.d < 20.0 then Lol.E(c, best.pos) end
	if best.d < 9.0 then Lol.Q(c, best.pos) end
	if best.d < 6.0 and hp < 0.65 then Lol.W(c) end
	if best.d < 12.0 and (#list >= 2 or best.champ) then Lol.R(c, best.pos) end
end
Lol.AI.tank = function(c, best, list, hp)
	if best.d < 5.5 then Lol.Q(c, best.pos) end
	if best.d < 7.0 then Lol.E(c, best.pos) end
	if best.d < 14.0 and #list >= 2 then Lol.R(c, best.pos) end
	if hp < 0.7 or #list >= 3 then Lol.W(c) end
end
Lol.AI.healer = function(c, best, list, hp)
	if best.d < 28.0 then Lol.Q(c, best.pos) end
	local hurtMates = 0
	for _, ped in ipairs(Lol.allies(c.team, GetEntityCoords(c.ped), 11.0)) do
		if GetEntityHealth(ped) < GetEntityMaxHealth(ped) * 0.75 then hurtMates = hurtMates + 1 end
	end
	if hurtMates >= 2 or hp < 0.5 then Lol.W(c) end
	if #list >= 3 then Lol.E(c) end
	if #list >= 3 and best.d < 12.0 then Lol.R(c, best.pos) end
end
Lol.AI.pyro = function(c, best, list, hp)
	if best.d < 9.0 then Lol.Q(c, best.pos) end
	if best.d < 5.5 then Lol.W(c) end
	if best.d < 26.0 and best.d > 7.0 then Lol.E(c, best.pos) end
	if best.d < 20.0 and (#list >= 2 or best.champ) then Lol.R(c, best.pos) end
end
Lol.AI.storm = function(c, best, list, hp)
	if best.d < 27.0 then Lol.Q(c, best.pos) end
	if best.d < 6.0 then Lol.W(c) end
	if best.d > 14.0 and best.champ then Lol.E(c, best.pos) end
	if best.d < 22.0 and (#list >= 2 or best.champ) then Lol.R(c, best.pos) end
end
Lol.RANGE = { mage = 32.0, brute = 32.0, ranger = 60.0, assassin = 24.0, tank = 14.0, healer = 30.0, pyro = 24.0, storm = 28.0 }
end

-- ---------- the frame: draws and moves every effect ----------
local function landLeap(d, np)
	local c = d.c
	boom(np, 0, { scale = 0.0, shake = 0.5 })
	Sigf.Fx('core', 'exp_grd_grenade_lod', np, { scale = 1.2 })
	Sigf.Sound('brute_nova', np, { range = 80.0, volume = 0.6 })
	for _, f in ipairs(Lol.foes(c.team, np, 5.5)) do
		hurt(f.ped, 75 * c.mul, c.ped, { 230, 120, 255 })
		knock(f.ped, norm2(f.pos - np), 8.0)
	end
	hitThings(c.team, np, 4.0, 25 * c.mul, { 230, 120, 255 }, c.ped)
	fx.bursts[#fx.bursts + 1] = { p = np - vector3(0, 0, 0.9), to = now() + 700, col = { 230, 120, 255 }, r = 11.0 }
end

local function frame(dt)
	local t0 = now()
	local cam = GetFinalRenderedCamCoord()
	local me = PlayerPedId()
	-- structures: glow, beam of light, ring, health bar
	for _, s in ipairs(S) do
		if s.alive and #(s.pos - cam) < 130.0 then
			local c = COL[s.team]
			local flash = (s.hitAt and t0 - s.hitAt < 150) and 1.0 or 0.0
			local vuln = vulnerable(s)
			DrawLightWithRange(s.pos.x, s.pos.y, s.pos.z + s.top - 1.0, c[1], c[2], c[3], 16.0 + flash * 8, 5.0 + flash * 6)
			DrawMarker(1, s.pos.x, s.pos.y, s.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.7, 70.0, c[1], c[2], c[3], vuln and 28 or 12, false, false, 2, false, nil, nil, false)
			ring(s.pos + vector3(0, 0, 0.05), s.r * 2.6, c, vuln and 90 or 50, 0.2)
			if not vuln then
				local pulse = 0.5 + 0.5 * math.sin(t0 / 400.0)
				DrawMarker(28, s.pos.x, s.pos.y, s.pos.z + s.top * 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s.r * 2.3, s.r * 2.3, s.top * 1.15,
					170, 200, 255, math.floor(14 + 14 * pulse), false, false, 2, false, nil, nil, false)
			end
			bar(s.pos + vector3(0, 0, s.top + 1.2), s.hp / s.max, s.kind == 'nexus' and 0.09 or 0.065, c)
		end
	end
	for _, team in ipairs({ 'blue', 'red' }) do
		local fp = fountainPos(team)
		if #(fp - cam) < 140.0 then
			local c = COL[team]
			ring(fp + vector3(0, 0, 0.1), 19.0, c, 38, 0.1)
			ring(fp + vector3(0, 0, 0.1), 16.0 + math.sin(t0 / 500.0), { 255, 255, 255 }, 22, 0.1)
			DrawLightWithRange(fp.x, fp.y, fp.z + 2.0, c[1], c[2], c[3], 12.0, 3.0)
		end
	end
	-- minions: team ring and health bar
	for ped, m in pairs(M) do
		if alive(ped) then
			local p = GetEntityCoords(ped)
			if #(p - cam) < 75.0 then
				local c = COL[m.team]
				ring(p - vector3(0, 0, 0.95), 1.1, c, 150, 0.15)
				bar(p + vector3(0, 0, 1.15), hpFrac(ped, m.max), m.kind == 'super' and 0.05 or 0.032, c)
			end
		end
	end
	for ped, j in pairs(JG) do
		if alive(ped) then
			local p = GetEntityCoords(ped)
			if #(p - cam) < 75.0 then
				local big = j.key == 'yeti' or j.key == 'yule'
				ring(p - vector3(0, 0, 0.95), big and 2.0 or 1.1, COL.neutral, 140, 0.15)
				bar(p + vector3(0, 0, big and 1.5 or 1.0), hpFrac(ped, j.max), big and 0.06 or 0.034, COL.neutral)
				if big then label(p + vector3(0, 0, 1.75), MOBS[j.key].name, COL.neutral, 0.28) end
			end
		end
	end
	-- champions
	for _, c in ipairs(CH) do
		if c.ped and alive(c.ped) then
			local p = GetEntityCoords(c.ped)
			local col = COL[c.team]
			if #(p - cam) < 100.0 then
				ring(p - vector3(0, 0, 0.95), 1.8, c.isPlayer and { 90, 255, 150 } or col, 190, 0.2)
				if not c.isPlayer then
					DrawLightWithRange(p.x, p.y, p.z + 1.0, col[1], col[2], col[3], 5.0, 2.5)
					bar(p + vector3(0, 0, 1.3), hpFrac(c.ped, c.hpmax + 40), 0.07, col)
					label(p + vector3(0, 0, 1.5), c.lv .. '  ' .. c.name, col, 0.32)
				end
			end
		end
	end
	if BOSS and BOSS.alive and #(BOSS.pos - cam) < 160.0 then
		local flash = (BOSS.hitAt and t0 - BOSS.hitAt < 150) and 1.0 or 0.0
		DrawLightWithRange(BOSS.pos.x, BOSS.pos.y, BOSS.pos.z + 5.0, 190, 70, 255, 18.0 + flash * 8, 6.0 + flash * 6)
		ring(BOSS.pos + vector3(0, 0, 0.1), 15.0, { 190, 70, 255 }, 40, 0.2)
		bar(BOSS.pos + vector3(0, 0, BOSS.top + 1.5), BOSS.hp / BOSS.max, 0.12, { 190, 90, 255 })
		label(BOSS.pos + vector3(0, 0, BOSS.top + 2.1), 'VOID NASHOR', { 220, 160, 255 }, 0.4)
	end
	-- turret / minion / boss beams
	for i = #fx.beams, 1, -1 do
		local b = fx.beams[i]
		if t0 > b.to then table.remove(fx.beams, i)
		else
			local w = b.w or 1
			for ox = -w, w do
				for oy = (w > 1 and -w or 0), (w > 1 and w or 0) do
					DrawLine(b.a.x + ox * 0.03, b.a.y + oy * 0.03, b.a.z, b.b.x + ox * 0.03, b.b.y + oy * 0.03, b.b.z, b.col[1], b.col[2], b.col[3], 255)
				end
			end
			if not b.nos then sphere(b.b, 0.5, b.col, 160) end
		end
	end
	-- Q: starbolt
	for i = #fx.projs, 1, -1 do
		local q = fx.projs[i]
		local step = q.speed * dt
		q.pos = q.pos + q.dir * step
		q.dist = q.dist + step
		table.insert(q.trail, 1, q.pos)
		if #q.trail > 9 then q.trail[10] = nil end
		local done = q.dist > q.max
		for _, f in ipairs(Lol.foes(q.c.team, q.pos, q.rad or 2.4)) do
			if not q.hit[f.ped] then
				q.hit[f.ped] = true
				hurt(f.ped, q.dmg, q.c.ped, q.hcol or { 120, 210, 255 })
				knock(f.ped, q.dir, q.kb or 6.0)
				if q.onHit then q.onHit(f, q) end
				if q.stop then done = true end
				Sigf.Sound('q_hit', f.pos, { range = 60.0, volume = 0.7 })
				Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], f.pos + vector3(0, 0, 0.8), { scale = 1.8 })
				Sigf.Fx(Sigf.FX.blood[1], Sigf.FX.blood[2], f.pos + vector3(0, 0, 0.9), { scale = 1.0 })
				Sigf.Shake(0.15, 'SMALL_EXPLOSION_SHAKE')
			end
		end
		for _, s in ipairs(S) do
			if s.alive and s.team ~= q.c.team and dist2(s.pos, q.pos) < s.r + 1.0 and q.pos.z < s.pos.z + s.top then
				hurtStruct(s, q.dmg * 0.9, q.col, q.c.ped)
				Sigf.Fx('core', 'exp_grd_grenade', q.pos, { scale = 1.0 })
				done = true
			end
		end
		if BOSS and BOSS.alive and dist2(BOSS.pos, q.pos) < BOSS.r + 1.0 and q.pos.z < BOSS.pos.z + BOSS.top then
			Lol.hurtBoss(q.dmg * 0.9, q.col, q.c.ped)
			Sigf.Sound('q_hit', q.pos, { range = 60.0, volume = 0.7 })
			done = true
		end
		local c = q.col
		sphere(q.pos, 0.16, { 255, 255, 255 }, 255)
		sphere(q.pos, 0.3, c, 150)
		for k, tp in ipairs(q.trail) do sphere(tp, 0.28 - k * 0.022, c, math.max(10, 120 - k * 12)) end
		DrawLightWithRange(q.pos.x, q.pos.y, q.pos.z, c[1], c[2], c[3], 10.0, 8.0)
		if done then if q.onEnd then q.onEnd(q) end table.remove(fx.projs, i) end
	end
	-- W: aegis dome (also the brute's mantle)
	for i = #fx.domes, 1, -1 do
		local d = fx.domes[i]
		if t0 > d.to or not alive(d.c.ped) then table.remove(fx.domes, i)
		else
			local p = GetEntityCoords(d.c.ped)
			local age = math.min(1.0, (t0 - d.born) / 250)
			local pulse = 1.0 + math.sin(t0 / 120.0) * 0.04
			local fade = math.min(1.0, (d.to - t0) / 600)
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0 * age, 6.0 * age, 0.1, d.col[1], d.col[2], d.col[3], math.floor(90 * fade), false, false, 2, true, nil, nil, false)
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.2 * age, 3.2 * age, 2.4, d.col[1], d.col[2], d.col[3], math.floor(80 * fade), false, false, 2, false, nil, nil, false)
			for k = 0, 3 do
				local r = (3.4 - math.abs(k - 1.2) * 0.45) * age * pulse
				DrawMarker(1, p.x, p.y, p.z - 0.9 + k * 0.62, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, 0.22, 190, 235, 255, math.floor(210 * fade), false, false, 2, false, nil, nil, false)
			end
			DrawLightWithRange(p.x, p.y, p.z + 1, d.col[1], d.col[2], d.col[3], 8.0, 4.0 * fade)
		end
	end
	-- E: dash (phase) or leap
	for i = #fx.dashes, 1, -1 do
		local d = fx.dashes[i]
		local T = d.mode == 'leap' and 0.6 or 0.28
		d.t = d.t + dt / T
		local k = math.min(1.0, d.t)
		if alive(d.c.ped) then
			local np = GetEntityCoords(d.c.ped)
			local sp = d.len / T
			SetEntityVelocity(d.c.ped, d.d.x * sp, d.d.y * sp, d.mode == 'leap' and 8.5 * (1.0 - 2.0 * k) or 0.0)
			if d.mode == 'phase' then
				Sigf.Fx('core', 'ent_dst_gen_gobstop', np - vector3(0, 0, 0.8), { scale = 0.8 })
				for _, f in ipairs(Lol.foes(d.c.team, np, 2.6)) do
					if not d.hit[f.ped] then
						d.hit[f.ped] = true
						hurt(f.ped, d.dmg * d.c.mul, d.c.ped, { 190, 255, 220 })
						knock(f.ped, d.d, 6.0)
					end
				end
				if not d.ring then d.ring = true fx.bursts[#fx.bursts + 1] = { p = np - vector3(0, 0, 0.9), to = t0 + 700, col = d.col, r = 5.0 } end
			elseif k >= 1.0 and not d.landed then
				d.landed = true
				landLeap(d, np)
			end
		end
		if k >= 1.0 then table.remove(fx.dashes, i) end
	end
	for i = #fx.bursts, 1, -1 do
		local b = fx.bursts[i]
		if t0 > b.to then table.remove(fx.bursts, i)
		else
			local f = (b.to - t0) / 700.0
			ring(b.p, b.r * (1.2 - f), b.col, math.floor(150 * f), 0.12)
		end
	end
	-- brute Q: a fan of dark energy
	for i = #fx.slashes, 1, -1 do
		local s = fx.slashes[i]
		local age = (t0 - s.t0) / 320.0
		if age > 1.0 then table.remove(fx.slashes, i)
		else
			local base = math.atan2(s.dir.y, s.dir.x)
			for k = -3, 3 do
				local a = base + k * 0.2
				for r = 1, 3 do
					local q = s.pos + vector3(math.cos(a), math.sin(a), 0) * (r * 2.6 * (0.4 + age)) + vector3(0, 0, 0.9)
					sphere(q, 1.0 - age * 0.6, s.col, math.floor(150 * (1 - age)))
				end
			end
		end
	end
	-- R (brute): oblivion nova
	for i = #fx.novas, 1, -1 do
		local n = fx.novas[i]
		local age = t0 - n.t0
		if age < n.warm then
			local f = age / n.warm
			ring(n.pos - vector3(0, 0, 0.9), n.r * 2.0, n.col, math.floor(60 + 60 * f), 0.3)
			DrawMarker(1, n.pos.x, n.pos.y, n.pos.z - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, n.r * 2.0 * f, n.r * 2.0 * f, 0.4, 240, 200, 255, 120, false, false, 2, true, nil, nil, false)
		else
			if not n.fired then n.fired = true n.pos = alive(n.c.ped) and GetEntityCoords(n.c.ped) or n.pos novaImpact(n) end
			if age > n.warm + 800 then table.remove(fx.novas, i)
			else
				local f = (age - n.warm) / 800.0
				ring(n.pos - vector3(0, 0, 0.9), n.r * 2.0 * (0.3 + f), n.col, math.floor(180 * (1 - f)), 0.5)
			end
		end
	end
	-- R (mage): starfall (telegraph, then meteors)
	for i = #fx.rings, 1, -1 do
		local r = fx.rings[i]
		local age = t0 - r.t0
		if age < r.warm then
			local f = age / r.warm
			DrawMarker(1, r.pos.x, r.pos.y, r.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 17.0, 17.0, 0.3, 255, 90, 30, math.floor(70 + 90 * f), false, false, 2, false, nil, nil, false)
			DrawMarker(1, r.pos.x, r.pos.y, r.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 17.0 * f, 17.0 * f, 0.4, 255, 200, 80, 120, false, false, 2, true, nil, nil, false)
		else
			if not r.fired then
				r.fired = true
				for k = 1, 11 do
					local a, rad = math.random() * 6.283, math.sqrt(math.random()) * 7.0
					local tp = r.pos + vector3(math.cos(a) * rad, math.sin(a) * rad, 0.0)
					if k <= 2 then tp = r.pos + vector3(math.random() - 0.5, math.random() - 0.5, 0) * 2.0 end
					fx.meteors[#fx.meteors + 1] = { c = r.c, tgt = tp, t0 = t0 + k * 140, fall = 650 }
				end
			end
			if age > r.warm + 2200 then table.remove(fx.rings, i)
			else DrawMarker(1, r.pos.x, r.pos.y, r.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 17.0, 17.0, 0.3, 255, 90, 30, 60, false, false, 2, false, nil, nil, false) end
		end
	end
	for i = #fx.meteors, 1, -1 do
		local m = fx.meteors[i]
		if t0 >= m.t0 then
			local f = (t0 - m.t0) / m.fall
			if not m.ent and not m.failed then
				m.ent = Sigf.Prop('prop_rock_1_a', m.tgt + vector3(-10, 0, 45), { collision = false, life = 4 })
				if m.ent then
					SetEntityLodDist(m.ent, 500)
					m.fx = Sigf.Fx('core', 'ent_sht_flame', m.ent, { loop = true, scale = 3.0, life = 3 })
					m.fx2 = Sigf.Fx('core', 'exp_grd_molotov_lod', m.ent, { loop = true, scale = 1.0, life = 3 })
				else m.failed = true end
			end
			local p = vector3(m.tgt.x - 10.0 * (1 - f), m.tgt.y, m.tgt.z + 45.0 * (1 - f) * (1 - f) + 0.5)
			if m.ent and DoesEntityExist(m.ent) then SetEntityCoordsNoOffset(m.ent, p.x, p.y, p.z, false, false, false) end
			if f >= 1.0 then
				if m.fx then Sigf.StopFx(m.fx) end
				if m.fx2 then Sigf.StopFx(m.fx2) end
				if m.ent then Sigf.Remove(m.ent) end
				meteorImpact(m.c, m.tgt)
				table.remove(fx.meteors, i)
			else
				DrawLightWithRange(p.x, p.y, p.z, 255, 140, 40, 14.0, 9.0)
			end
		end
	end
	-- the hero: invincible in the demo, mortal at home; the carbine hurts buildings and the boss
	local hero = CH.hero
	if hero and hero.isPlayer then
		if god() then
			SetPlayerInvincible(PlayerId(), true)
			SetEntityInvincible(me, true)
			SetEntityProofs(me, true, true, true, true, true, true, true, true)
			if GetEntityHealth(me) < GetEntityMaxHealth(me) and not IsPedDeadOrDying(me, true) then SetEntityHealth(me, GetEntityMaxHealth(me)) end
			if IsPedRagdoll(me) then
				Lol.ragAt = Lol.ragAt or t0
				if t0 - Lol.ragAt > 700 then
					SetPedCanRagdoll(me, true)
					ClearPedTasksImmediately(me)
					Lol.ragAt = nil
					SetTimeout(300, function() SetPedCanRagdoll(PlayerPedId(), false) end)
				end
			else Lol.ragAt = nil end
		elseif alive(me) then
			local hs = hero.ms + ((hero.hasteUntil or 0) > t0 and 0.35 or 0.0)
			SetPedMoveRateOverride(me, 1.0 + hs)
			SetRunSprintMultiplierForPlayer(PlayerId(), 1.0 + math.min(0.49, hs))
		end
		if alive(me) and IsPedShooting(me) then
			local ok, ip = GetPedLastWeaponImpactCoord(me)
			local mp = GetEntityCoords(me)
			local fwd = GetEntityForwardVector(me)
			for _, s in ipairs(S) do
				if s.alive and s.team ~= hero.team then
					local hit = false
					if ok and ip and dist2(ip, s.pos) < s.r + 1.5 and ip.z < s.pos.z + s.top + 1.0 then hit = true
					else
						local to = s.pos - mp
						if #to < 45.0 and #to > 0.1 and dot(norm2(to), norm2(fwd)) > 0.95 then hit = true end
					end
					if hit then hurtStruct(s, 4.5 * hero.mul, { 255, 255, 255 }, me) end
				end
			end
			if BOSS and BOSS.alive and ok and ip and dist2(ip, BOSS.pos) < BOSS.r + 1.2 and ip.z < BOSS.pos.z + BOSS.top then
				Lol.hurtBoss(5.0 * hero.mul, { 255, 255, 255 }, me)
			end
		end
	end
end


-- ---------- champion brains ----------
local function frontAlly(c)
	local ln = LANES[c.lane]
	local best, bp
	for ped, m in pairs(M) do
		if m.team == c.team and m.lane == c.lane and alive(ped) then
			local prog = laneProgress(ln, GetEntityCoords(ped))
			if c.team == 'red' then prog = ln.len - prog end
			if not bp or prog > bp then best, bp = ped, prog end
		end
	end
	return best and GetEntityCoords(best)
end

local function turretNear(team, p, range)
	for _, s in ipairs(S) do
		if s.alive and s.team ~= team and (s.kind == 'turret') and dist2(s.pos, p) < range then return s end
	end
end

local function goTo(c, p, speed)
	if now() > (c.cmd or 0) then
		c.cmd = now() + 1800
		TaskGoToCoordAnyMeans(c.ped, p.x, p.y, p.z, speed or 2.0, 0, false, 786603, 0.0)
	end
end

local function think(c)
	if c.isPlayer or c.remote or c.dead or not alive(c.ped) then return end
	local t0 = now()
	local ped = c.ped
	local p = GetEntityCoords(ped)
	local ln = LANES[c.lane]
	local hp = (GetEntityHealth(ped) - 100) / c.hpmax
	local home = fountainPos(c.team)
	-- retreat to the fountain to heal
	if c.retreat then
		if hp > 0.85 or dist2(p, home) < 6.0 and hp > 0.7 then c.retreat = false
		else
			goTo(c, home, 3.0)
			if hp < 0.4 then Lol.W(c) end
			return
		end
	elseif hp < 0.3 then
		c.retreat = true
		Lol.W(c)
		return
	end
	-- spend gold
	if c.gold >= 350 then autoBuy(c) end
	local list = Lol.foes(c.team, p, 32.0, true)
	local best
	for _, f in ipairs(list) do
		local w = f.d - (f.champ and 5.0 or 0.0)
		if not best or w < best.w then best = f best.w = w end
	end
	local mates = #Lol.allies(c.team, p, 14.0) - 1
	local tur = turretNear(c.team, p, 25.0)
	-- do not dive a turret alone: fall back to the lane
	if tur and mates < 3 then
		local prog = laneProgress(ln, p)
		local back = lanePos(ln, clamp(prog + (c.team == 'blue' and -14.0 or 14.0), 0.0, ln.len), 0)
		goTo(c, back, 3.0)
		if best and best.d < 24.0 then Lol.Q(c, best.pos) end
		return
	end
	if best then
		local ai = Lol.AI and Lol.AI[c.kit]
		if ai then Sigf.Safe('ai', ai, c, best, list, hp)
		else
			if best.d < 32.0 then Lol.Q(c, best.pos) end
			if (#list >= 3 or (best.champ and best.d < 20.0)) and best.d < 24.0 then Lol.R(c, best.pos) end
			if best.d > 15.0 and best.champ and math.random() < 0.35 then Lol.E(c, best.pos, 9.0) end
			if hp < 0.55 or #list >= 4 then Lol.W(c) end
		end
		if c.tgt ~= best.ped or t0 > (c.cmd or 0) then
			c.tgt, c.cmd = best.ped, t0 + 2500
			TaskCombatPed(ped, best.ped, 0, 16)
		end
		return
	end
	local st, sd = targetStruct(c.team, p)
	if st and sd < 16.0 and mates >= 1 then
		Lol.Q(c, st.pos)
		if sd < 11.0 and mates >= 2 then Lol.R(c, st.pos) end
		if t0 > (c.cmd or 0) then
			c.cmd = t0 + 1500
			TaskShootAtCoord(ped, st.pos.x, st.pos.y, st.pos.z + 2.5, 1500, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
		end
		hurtStruct(st, 10 * c.mul, COL[c.team], ped)
		fx.beams[#fx.beams + 1] = { a = p + vector3(0, 0, 1.3), b = st.pos + vector3(0, 0, 2.5), col = COL[c.team], to = t0 + 150 }
		return
	end
	-- march with the minions of the lane
	local fa = frontAlly(c)
	local prog = laneProgress(ln, p)
	local goal = fa
	if not goal then
		local own = lanePos(ln, c.team == 'blue' and ln.len * 0.30 or ln.len * 0.70, 0)
		goal = own
	end
	if #(p - goal) > 7.0 then goTo(c, goal, 2.4) end
end

-- ---------- fountains, passive gold, respawns ----------
local function baseTick()
	for _, c in ipairs(CH) do
		if c.ped and alive(c.ped) and not c.dead then
			local p = GetEntityCoords(c.ped)
			addGold(c, c.isPlayer and 1.6 or 1.5)
			if dist2(p, fountainPos(c.team)) < 10.0 and not c.remote then
				local mx = GetEntityMaxHealth(c.ped)
				SetEntityHealth(c.ped, math.min(mx, GetEntityHealth(c.ped) + math.floor(c.hpmax * 0.10)))
				SetPedArmour(c.ped, math.max(GetPedArmour(c.ped), 40))
			end
			local ef = fountainPos(foe(c.team))
			if dist2(p, ef) < 15.0 and not (god() and c.isPlayer) then
				fx.beams[#fx.beams + 1] = { a = ef + vector3(0, 0, 7.0), b = p + vector3(0, 0, 1.0), col = COL[foe(c.team)], to = now() + 300 }
				hurt(c.ped, 110, nil, COL[foe(c.team)])
			end
		end
	end
	if not match.over then
		for _, c in ipairs(CH) do
			if c.isPlayer then
				if c.dead and match.running and now() >= c.respawnAt then Lol.respawn(c) end
			elseif c.remote then
				if c.dead and now() >= (c.respawnAt or 0) + 3000 then c.dead = false end
			elseif c.dead and now() >= (c.respawnAt or 0) and not match.over then
				if c.ped then Sigf.Remove(c.ped) end
				c.dead, c.retreat, c.cmd = false, false, 0
				spawnChamp(c)
				recalc(c)
			end
		end
	end
	for _, c in ipairs(CH) do
		if c.buff and now() > c.buff.to then c.buff = nil recalc(c) end
	end
end

-- ---------- deaths ----------
local function nameOfSource(killer)
	local kc = killer and champOf(killer)
	return kc
end

function Lol.respawn(c)
	c.dead = false
	c.retreat = false
	spawnChamp(c)
	recalc(c)
	Sigf.Nui({ respawn = false })
	c.ready = { q = 0, w = 0, e = 0, r = now() + 4000 }
	banner('YOU HAVE RESPAWNED', '#7aff9a', 2)
	if Lol.NET.on then TriggerServerEvent('lol:back') end
end

local function championDied(c, killer)
	if c.dead then return end
	c.dead = true
	c.deaths = c.deaths + 1
	c.respawnAt = now() + math.floor((5.0 + c.lv * 1.8) * 1000)
	local foeTeam = foe(c.team)
	match.kills[foeTeam] = match.kills[foeTeam] + 1
	local kc = nameOfSource(killer)
	local p = c.ped and DoesEntityExist(c.ped) and GetEntityCoords(c.ped) or fountainPos(c.team)
	Sigf.Sound('champ_kill', p, { range = 120.0, volume = 0.9 })
	if kc and kc.team == foeTeam then
		kc.kills = kc.kills + 1
		addGold(kc, 300, p)
		addXp(kc, 120)
		for _, a in ipairs(CH) do if a.team == foeTeam and a ~= kc and alive(a.ped) and #(GetEntityCoords(a.ped) - p) < 40.0 then addGold(a, 100) addXp(a, 60) end end
		feed(kc.name .. ' slew ' .. c.name, kc.team)
		if kc.isPlayer then Lol.quest('kill') end
	else
		feed(c.name .. ' was executed', foeTeam)
		shareXp(foeTeam, p, 80, 40.0)
	end
	if c.isPlayer then
		banner(match.fb and 'YOU HAVE BEEN SLAIN' or 'FIRST BLOOD FOR THE VOID!', '#ff7a5a', 2.5)
		Sigf.Nui({ respawn = { sec = (c.respawnAt - now()) / 1000.0 } })
	elseif not match.fb then
		banner(foeTeam == 'blue' and 'FIRST BLOOD!' or 'FIRST BLOOD FOR THE VOID!', foeTeam == 'blue' and '#ffd45a' or '#ff7a5a', 2.5)
	elseif kc then
		banner(kc.isPlayer and ('YOU SLEW ' .. c.name) or (c.name .. ' HAS BEEN SLAIN'), kc.team == 'blue' and '#ffd45a' or '#ff7a5a', 2.0)
	end
	match.fb = true
	if c.ped and not c.isPlayer and not c.remote then
		Sigf.After(4.0, function() if c.dead and c.ped then Sigf.Remove(c.ped) end end)
	end
	if c.isPlayer and Lol.NET.on then
		local kcm = kc and (kc.isPlayer and 0 or kc.remote) or 0
		TriggerServerEvent('lol:died', kcm)
	end
end

function Lol.bossSlain(by)
	local kc = by and champOf(by)
	local team = kc and kc.team or 'blue'
	match.buff = { team = team, to = now() + 70000 }
	banner((team == 'blue' and 'ORDER' or 'VOID') .. ' HAS SLAIN THE VOID NASHOR!', team == 'blue' and '#7ac8ff' or '#ff7a5a', 4)
	feed((team == 'blue' and 'Order' or 'Void') .. ' slew the Void Nashor', team)
	Sigf.Sound('buff_get', nil, { volume = 0.9 })
	for _, c in ipairs(CH) do
		if c.team == team then addGold(c, 300) addXp(c, 200) recalc(c) end
	end
	Sigf.Text3D('EMPOWERED MINIONS', fountainPos(team) + vector3(0, 0, 4.0), 5, { color = COL[team], scale = 0.8 })
	if kc and kc.isPlayer then Lol.quest('boss') end
	match.bossDead = now()
end

Sigf.OnKill(function(ped, killer)
	local p = GetEntityCoords(ped)
	local m, j, c = M[ped], JG[ped], champOf(ped)
	local kc = nameOfSource(killer)
	if c then championDied(c, killer) return end
	if m then
		m.dead = true
		minionCount = math.max(0, minionCount - 1)
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 0.8), { scale = 1.4 })
		Sigf.Sound('minion_die', p, { range = 50.0, volume = 0.4 })
		local killTeam = foe(m.team)
		if kc and kc.team == killTeam then
			addGold(kc, m.def.gold, p)
			if kc.isPlayer then Lol.quest('minion') end
		end
		shareXp(killTeam, p, m.def.xp)
	elseif j then
		local def = MOBS[j.key]
		local cp = j.camp
		Sigf.Sound('camp_hit', p, { range = 60.0, volume = 0.8 })
		local last = true
		for _, o in ipairs(cp.mobs) do if o ~= ped and alive(o) then last = false end end
		if kc then
			addGold(kc, cp.def.gold / #cp.mobs, p)
			if last then
				if cp.def.buff then
					local b = BUFFS[cp.def.buff]
					kc.buff = { id = cp.def.buff, to = now() + b.sec * 1000 }
					recalc(kc)
					if kc.isPlayer then
						banner(b.text, '#' .. string.format('%02x%02x%02x', b.color[1], b.color[2], b.color[3]), 3.5)
						Sigf.Sound('buff_get', nil, { volume = 0.8 })
						Lol.quest('jungle')
					end
				elseif kc.isPlayer then Lol.quest('jungle') end
			end
		end
		shareXp(kc and kc.team or 'blue', p, cp.def.xp / #cp.mobs, 22.0)
	end
end)

-- ---------- quests ----------
local QUESTS = {
	{ id = 'minion', text = 'Slay 6 minions', need = 6 },
	{ id = 'shop',   text = 'Buy an item at the shop (press B)', need = 1 },
	{ id = 'jungle', text = 'Slay a jungle monster for its buff', need = 1 },
	{ id = 'turret', text = 'Destroy an enemy turret', need = 1 },
	{ id = 'kill',   text = 'Slay an enemy champion', need = 1 },
	{ id = 'boss',   text = 'Slay the Void Nashor', need = 1 },
	{ id = 'nexus',  text = 'Destroy the Void Nexus', need = 1 },
}
local qdone = {}
local function questShow()
	for i, q in ipairs(QUESTS) do
		if (qdone[q.id] or 0) < q.need then
			Sigf.Nui({ quest = { text = q.text, n = qdone[q.id] or 0, need = q.need, step = i, total = #QUESTS } })
			return
		end
	end
	Sigf.Nui({ quest = false })
end
function Lol.quest(id)
	for _, q in ipairs(QUESTS) do
		if q.id == id and (qdone[id] or 0) < q.need then
			qdone[id] = (qdone[id] or 0) + 1
			if qdone[id] >= q.need then
				banner('OBJECTIVE COMPLETE: ' .. q.text:upper(), '#7aff9a', 2.5)
				Sigf.Sound('levelup', nil, { volume = 0.5 })
			end
			questShow()
			return
		end
	end
end
function Lol.questReset() qdone = {} questShow() end


-- ---------- hud ----------
local function mapUV(p)
	local u, v = toLane(p)                  -- lane coordinates relative to the map centre
	return 0.5 + u / MAP_W, 0.5 - v / MAP_H
end

local function buildMap()
	local ss, us = {}, {}
	for _, s in ipairs(S) do
		if s.alive then
			local u, v = mapUV(s.pos)
			ss[#ss + 1] = { u, v, s.team == 'red' and 1 or 0, s.kind == 'nexus' and 'n' or 't', s.hp / s.max }
		end
	end
	for ped, m in pairs(M) do
		if alive(ped) then
			local u, v = mapUV(GetEntityCoords(ped))
			us[#us + 1] = { u, v, m.team == 'red' and 1 or 0, 'm' }
		end
	end
	for ped in pairs(JG) do
		if alive(ped) then
			local u, v = mapUV(GetEntityCoords(ped))
			us[#us + 1] = { u, v, 0, 'j' }
		end
	end
	for _, c in ipairs(CH) do
		if alive(c.ped) then
			local u, v = mapUV(GetEntityCoords(c.ped))
			us[#us + 1] = { u, v, c.team == 'red' and 1 or 0, c.isPlayer and 'h' or 'c' }
		end
	end
	if BOSS and BOSS.alive then
		local u, v = mapUV(BOSS.pos)
		us[#us + 1] = { u, v, 0, 'b' }
	end
	return { w = MAP_ASPECT, h = 1.0, s = ss, u = us }
end

local hudTick = 0
local function sendHud()
	local h = CH.hero
	if not h then return end
	hudTick = hudTick + 1
	local t0 = now()
	local cd, cdm = {}, {}
	for _, k in ipairs({ 'q', 'w', 'e', 'r' }) do
		cd[k] = math.max(0, (h.ready[k] - t0) / 1000.0)
		cdm[k] = (h.cdTotal and h.cdTotal[k]) or CD[h.kit][k]
	end
	local hp = alive(h.ped) and (GetEntityHealth(h.ped) - 100) or 0
	local nb, nr = S.nexus and S.nexus.blue, S.nexus and S.nexus.red
	local lo, hi = XP_NEED[h.lv], XP_NEED[h.lv + 1] or (XP_NEED[h.lv] + 1)
	local buff
	if h.buff and t0 < h.buff.to then buff = { name = BUFFS[h.buff.id].name, sec = (h.buff.to - t0) / 1000.0 }
	elseif match.buff and match.buff.team == h.team and t0 < match.buff.to then buff = { name = 'VOID EMPOWERED', sec = (match.buff.to - t0) / 1000.0 } end
	local near = false
	if (HOME or DEMO) and h.ped and (alive(h.ped) or h.dead) then near = h.dead or dist2(GetEntityCoords(h.ped), fountainPos(h.team)) < 18.0 end
	local d = {
		nb = nb and math.max(0, nb.hp) or 0, nbm = nb and nb.max or 1, nr = nr and math.max(0, nr.hp) or 0, nrm = nr and nr.max or 1,
		kb = match.kills.blue, kr = match.kills.red, t = (t0 - match.t0) / 1000.0,
		keys = (HOME and 'QZXC') or 'QWER', gold = math.floor(h.gold), lv = h.lv, xp = h.lv >= MAX_LV and 1.0 or clamp((h.xp - lo) / (hi - lo), 0.0, 1.0),
		name = h.name, cid = h.id, abil = Lol.CHAMP[h.id or 'aurelia'].abil, col = h.r.col, hp = hp, hpmax = h.hpmax, cd = cd, cdm = cdm, items = h.items, buff = buff or false, shopNear = near,
		stats = { dmg = '+' .. math.floor((h.mul - 1) * 100 + 0.5) .. '%', ms = '+' .. math.floor(h.ms * 100 + 0.5) .. '%',
			cdr = math.floor(h.cdr * 100 + 0.5) .. '%', ls = math.floor(h.ls * 100 + 0.5) .. '%' },
	}
	if hudTick % 2 == 0 then d.map = buildMap() end
	if hudTick % 7 == 1 then
		local r = {}
		for _, c in ipairs(CH) do r[#r + 1] = { name = c.name, lv = c.lv, k = c.kills, d = c.deaths, team = c.team == 'red' and 1 or 0, dead = c.dead and true or false } end
		d.roster = r
	end
	hud.near = near
	Sigf.Nui({ hud = d })
end

-- ---------- shop ----------
local function shopPayload(open)
	local items = {}
	for i, it in ipairs(ITEMS) do items[i] = { id = it.id, name = it.name, cost = it.cost, desc = it.desc, buy = tostring(i) } end
	local h = CH.hero
	return { open = open, gold = h and math.floor(h.gold) or 0, items = items, owned = h and h.items or {} }
end

function Lol.toggleShop()
	local h = CH.hero
	if not (h and h.isPlayer) then return end
	if hud.shopOpen then
		hud.shopOpen = false
		Sigf.Nui({ shop = { open = false } })
		return
	end
	if not hud.near then
		banner('THE SHOP IS AT YOUR BASE (BLUE FOUNTAIN)', '#ffd45a', 2.5)
		return
	end
	hud.shopOpen = true
	Sigf.Sound('shop_open', nil, { volume = 0.7 })
	Sigf.Nui({ shop = shopPayload(true) })
end

function Lol.buy(i)
	local h = CH.hero
	if not (h and h.isPlayer and hud.shopOpen) then return end
	local it = ITEMS[i]
	if not it then return end
	if itemOwned(h, it.id) then banner('YOU ALREADY OWN ' .. it.name:upper(), '#f0e6d2', 1.5) return end
	if h.gold < it.cost then banner('NOT ENOUGH GOLD', '#ff7a5a', 1.5) return end
	if #h.items >= 6 then banner('YOUR INVENTORY IS FULL', '#ff7a5a', 1.5) return end
	if buyItem(h, it.id) then
		Lol.quest('shop')
		Sigf.Nui({ shop = shopPayload(true) })
		Sigf.After(0.15, function() Sigf.Nui({ shop = { bought = it.id } }) end)
	end
end

-- ---------- player controls ----------
local function playerCast(k)
	local c = CH.hero
	if not (c and c.isPlayer) or c.dead then return end
	if Lol.Cast(c, k) and Lol.NET.on then
		local p = GetEntityCoords(c.ped)
		Lol.netCast(k, crosshair(c, 30.0) or (p + aimDir(c) * 20.0))
	end
end

function Lol.flash(c)
	if not c or not alive(c.ped) or now() < (c.flashAt or 0) then return false end
	c.flashAt = now() + 40000
	local p = GetEntityCoords(c.ped)
	local d = aimDir(c)
	local q = p + d * 11.0
	q = vector3(q.x, q.y, gz(q.x, q.y, p.z))
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 1), { scale = 2.5 })
	SetEntityCoords(c.ped, q.x, q.y, q.z + 0.5, false, false, false, false)
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], q + vector3(0, 0, 1), { scale = 2.5 })
	Sigf.Sound('e_dash', q, { range = 60.0, volume = 0.6 })
	return true
end

function Lol.recall()
	local c = CH.hero
	if not (c and c.isPlayer) or c.dead or not alive(c.ped) then return end
	if c.recall then return end
	c.recall = { t0 = now(), pos = GetEntityCoords(c.ped), hp = GetEntityHealth(c.ped) }
	banner('RECALLING...  STAY STILL', '#9ad0ff', 4.5)
	Sigf.Sound('recall', nil, { volume = 0.7 })
end

local function recallTick()
	local c = CH.hero
	if not (c and c.recall) then return end
	if not alive(c.ped) then c.recall = nil return end
	local p = GetEntityCoords(c.ped)
	if #(p - c.recall.pos) > 2.0 or GetEntityHealth(c.ped) < c.recall.hp - 1 then
		c.recall = nil
		banner('RECALL CANCELLED', '#ff7a5a', 1.5)
		return
	end
	Sigf.Light(p + vector3(0, 0, 1), { 120, 200, 255 }, 8.0, 5.0, 0.25)
	if now() - c.recall.t0 > 4500 then
		c.recall = nil
		local f = fountainPos(c.team)
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 1), { scale = 2.5 })
		SetEntityCoords(c.ped, f.x, f.y, f.z + 1.0, false, false, false, false)
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], f + vector3(0, 0, 1), { scale = 2.5 })
		banner('YOU HAVE RETURNED TO THE FOUNTAIN', '#9ad0ff', 2.0)
	end
end

RegisterCommand('lol_q', function() playerCast('q') end, false)
RegisterCommand('lol_w', function() playerCast('w') end, false)
RegisterCommand('lol_e', function() playerCast('e') end, false)
RegisterCommand('lol_r', function() playerCast('r') end, false)
RegisterCommand('lol_shop', function() Lol.toggleShop() end, false)
RegisterCommand('lol_recall', function() Lol.recall() end, false)
RegisterCommand('lol_flash', function() local c = CH.hero if c and c.isPlayer then Lol.flash(c) end end, false)
RegisterKeyMapping('lol_q', 'Summoner: Q Starbolt', 'keyboard', 'Q')
RegisterKeyMapping('lol_w', 'Summoner: W Aegis', 'keyboard', 'Z')
RegisterKeyMapping('lol_e', 'Summoner: E Phase Dash', 'keyboard', 'X')
RegisterKeyMapping('lol_r', 'Summoner: R Starfall', 'keyboard', 'C')
RegisterKeyMapping('lol_shop', 'Summoner: Open the item shop', 'keyboard', 'B')
RegisterKeyMapping('lol_recall', 'Summoner: Recall to the fountain', 'keyboard', 'H')
RegisterKeyMapping('lol_flash', 'Summoner: Flash', 'keyboard', 'G')
for i = 1, 8 do
	RegisterCommand('lol_buy' .. i, function() Lol.buy(i) end, false)
	RegisterKeyMapping('lol_buy' .. i, 'Summoner: Shop item ' .. i, 'keyboard', tostring(i))
end

-- ---------- match flow ----------
local DECO = {}
local function buildDeco()
	for _, team in ipairs({ 'blue', 'red' }) do
		local u = team == 'blue' and -N + 9.0 or N - 9.0
		local p = W(u, 12.0)
		skin('sigf_shop')
		local e = Sigf.Prop('sigf_shop', p, { ground = true, heading = L.dirHeading + (team == 'blue' and 200.0 or 20.0) })
		if e then DECO[#DECO + 1] = e end
	end
end

local function cleanup()
	if Lol.PoroClear then Lol.PoroClear() end
	if Lol.DrakeClear then Lol.DrakeClear() end
	for i = #DECO, 1, -1 do Sigf.Remove(DECO[i]) DECO[i] = nil end
	for ped in pairs(M) do Sigf.Remove(ped) end
	for k in pairs(M) do M[k] = nil end
	for ped in pairs(JG) do Sigf.Remove(ped) end
	for k in pairs(JG) do JG[k] = nil end
	for i = #CAMPS, 1, -1 do CAMPS[i] = nil end
	for _, s in ipairs(S) do Sigf.Remove(s.ent) if s.rubble then Sigf.StopFx(s.rubble) end end
	for k in pairs(S) do S[k] = nil end
	for _, c in ipairs(CH) do if c.ped and not c.isPlayer and not c.remote then Sigf.Remove(c.ped) end end
	for k in pairs(CH) do CH[k] = nil end
	if BOSS then Sigf.Remove(BOSS.ent) BOSS = nil end
	for k, v in pairs(fx) do for i = #v, 1, -1 do v[i] = nil end end
	minionCount = 0
	for k in pairs(LANES) do LANES[k] = nil end
end

function Lol.FullReset() cleanup() Sigf.Nui({ ['end'] = false }) end

local BASE
local function layout()
	BASE = BASE or (HOME and vector3(1712.0, 3255.0, 41.0) or Sigf.Arena())
	local base = BASE
	local ang = math.rad(12.0)
	local dir = vector3(math.cos(ang), math.sin(ang), 0.0)
	local c = base + vector3(-116.0, -24.0, 0.0)
	local ok, z = GetGroundZFor_3dCoord(c.x, c.y, base.z + 40.0, false)
	L = { c = vector3(c.x, c.y, ok and z or base.z), dir = dir, side = vector3(-dir.y, dir.x, 0.0), dirHeading = GetHeadingFromVector_2d(dir.x, dir.y) }
	Lol.L = L
end

function Lol.Finish(blueWins)
	local myTeam = CH.hero and CH.hero.team or 'blue'
	local won = blueWins == (myTeam == 'blue')
	banner(won and 'THE ENEMY NEXUS HAS BEEN DESTROYED' or 'YOUR NEXUS HAS BEEN DESTROYED', won and '#ffd45a' or '#ff6a50', 4)
	if won then Lol.quest('nexus') Sigf.After(2.0, function() Sigf.Sound('victory', nil, { volume = 0.8 }) end) end
	local nx = S.nexus and (blueWins and S.nexus.red or S.nexus.blue)
	if nx then
		local look = nx.pos + vector3(0, 0, 5.0)
		if DEMO then Sigf.Cinematic(nx.pos + L.side * 16.0 - L.dir * (blueWins and 14.0 or -14.0) + vector3(0, 0, 6.0), look, 6.0, 55.0)
		else Sigf.Focus(look, 7) Lol.focusUntil = now() + 7000 end
	end
	Sigf.After(1.8, function()
		Sigf.Nui({ ['end'] = won and 'VICTORY' or 'DEFEAT', sec = 9 })
		Sigf.PostFx(won and 'SuccessMichael' or 'DeathFailOut', 3)
	end)
	local loser = blueWins and 'red' or 'blue'
	for ped, m in pairs(M) do
		if m.team == loser and alive(ped) then
			Sigf.After(math.random() * 2.5, function() if alive(ped) then Sigf.Fx('core', 'exp_grd_grenade', GetEntityCoords(ped), { scale = 0.8 }) SetEntityHealth(ped, 0) end end)
		end
	end
	if not Lol.NET.on then Sigf.After(18.0, function() Lol.NewMatch() end) end
end

-- A player's own game: there is no stage, so this resource spawns the player, makes the teams and clears the world.
local function setupGroups()
	local _, a = AddRelationshipGroup('SIGF_A')
	local _, b = AddRelationshipGroup('SIGF_B')
	SetRelationshipBetweenGroups(5, a, b)
	SetRelationshipBetweenGroups(5, b, a)
	local player = GetHashKey('PLAYER')
	SetRelationshipBetweenGroups(1, a, player)
	SetRelationshipBetweenGroups(1, player, a)
	SetRelationshipBetweenGroups(5, b, player)
	SetRelationshipBetweenGroups(5, player, b)
end

local function prepareHome()
	local base = vector3(1712.0, 3255.0, 41.0)
	local spot = vector3(base.x - 116.0, base.y - 24.0, base.z + 2.0)
	while not NetworkIsPlayerActive(PlayerId()) do Wait(200) end
	local model = GetHashKey('u_m_y_rsranger_01')
	RequestModel(model)
	local t = GetGameTimer() + 5000
	while not HasModelLoaded(model) and GetGameTimer() < t do Wait(50) end
	if GetResourceState('spawnmanager') == 'started' then
		pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
		pcall(function() exports.spawnmanager:spawnPlayer({ x = spot.x, y = spot.y, z = spot.z, heading = 90.0, model = 'u_m_y_rsranger_01', skipFade = true }) end)
		Wait(1500)
	else
		if HasModelLoaded(model) then SetPlayerModel(PlayerId(), model) end
		RequestCollisionAtCoord(spot.x, spot.y, spot.z)
		NetworkResurrectLocalPlayer(spot.x, spot.y, spot.z, 90.0, true, false)
	end
	ShutdownLoadingScreen()
	ShutdownLoadingScreenNui()
	DoScreenFadeIn(300)
	local me = PlayerPedId()
	FreezeEntityPosition(me, false)
	SetEntityVisible(me, true, false)
	SetEntityCollision(me, true, true)
	SetMaxWantedLevel(0)
	ClearPlayerWantedLevel(PlayerId())
	SetPoliceIgnorePlayer(PlayerId(), true)
	DisplayRadar(false)
	NetworkOverrideClockTime(14, 0, 0)
	SetWeatherTypeNowPersist('EXTRASUNNY')
	setupGroups()
	RequestCollisionAtCoord(spot.x, spot.y, spot.z)
	SetEntityCoords(me, spot.x, spot.y, spot.z, false, false, false, false)
	t = GetGameTimer() + 8000
	while not HasCollisionLoadedAroundEntity(me) and GetGameTimer() < t do RequestCollisionAtCoord(spot.x, spot.y, spot.z) Wait(100) end
end


-- ---------- the roster: who plays on which team ----------
local SLOT_LANE = { 'mid', 'top', 'bot', 'top', 'bot' }
local DEMO_PICKS = {
	blue = { 'aurelia', 'bastion', 'vesper', 'cinder', 'lumi' },
	red  = { 'voltaire', 'kael', 'shade', 'vesper', 'bastion' },
}
-- spec = { blue = { { champ = 'vesper', hero = true, human = 3 }, ... }, red = { ... } }; empty slots are filled by the AI
function Lol.BuildRoster(spec)
	spec = spec or {}
	local out, size = {}, Lol.TEAM_SIZE or 5
	for _, team in ipairs({ 'blue', 'red' }) do
		local arr, used = {}, {}
		-- players keep the slot the server gave them (slot 1 mid, 2 top, 3 bottom, 4 top, 5 bottom)
		for _, e in ipairs(spec[team] or {}) do
			local i = e.slot
			if not i or i < 1 or i > size or arr[i] then
				i = 1
				while arr[i] do i = i + 1 end
			end
			if i <= size then arr[i] = e used[e.champ] = true end
		end
		local pool = {}
		if DEMO then for _, id in ipairs(DEMO_PICKS[team]) do if not used[id] then pool[#pool + 1] = id end end
		else for _, ch in ipairs(Lol.CHAMPS) do if not used[ch.id] then pool[#pool + 1] = ch.id end end end
		for i = 1, size do
			if not arr[i] and #pool > 0 then
				arr[i] = { champ = table.remove(pool, DEMO and 1 or math.random(#pool)) }
			end
		end
		for i = 1, size do
			local e = arr[i]
			if e then
				local ch = Lol.CHAMP[e.champ] or Lol.CHAMPS[1]
				out[#out + 1] = { team = team, name = e.name or ch.name, lane = SLOT_LANE[i] or 'mid', kit = ch.kit, hero = e.hero, human = e.human,
					model = ch.model, weapon = ch.weapon, col = ch.col, id = ch.id, slot = i }
			end
		end
	end
	return out
end

function Lol.NewMatch()
	cleanup()
	match = { over = false, t0 = now(), wave = 0, kills = { blue = 0, red = 0 }, running = true, fb = false }
	hud.shopOpen = false
	Sigf.Nui({ shop = { open = false }, respawn = false })
	layout()
	buildLanes()
	buildStructures()
	if Lol.applyHpSync then Lol.applyHpSync() end
	buildDeco()
	for _, r in ipairs(Lol.BuildRoster(Lol.spec or (PLAYER_HERO and { blue = { { champ = Lol.myPick or 'aurelia', hero = true } } } or nil))) do newChamp(r) end
	for i, c in ipairs(CH) do
		Sigf.After((i - 1) * 0.3, function() if match.running then spawnChamp(c, true) end end)
	end
	buildCamps()
	if Lol.PoroStart then Lol.PoroStart() end
	if Lol.DrakeStart then Lol.DrakeStart() end
	Sigf.Battle({ enabled = false })
	Sigf.Focus(L.c, 4)
	Sigf.Nui({ title = { big = "SUMMONER'S RIFT", small = 'LOS SANTOS', sec = 4.5 } })
	Lol.questReset()
	Sigf.After(4.5, function()
		if not match.over and not DEMO then banner('THE VOID IS BREACHING LOS SANTOS. HOLD THE LINE!', '#ffd45a', 4) end
	end)
	local mine = match
	local function loop()
		Sigf.After(WAVE_SEC, function()
			if match == mine and not mine.over then spawnWave() loop() end
		end)
	end
	Sigf.After(FIRST_WAVE, function() if match == mine then spawnWave() loop() end end)
	Sigf.After(DEMO and 3.0 or 150.0, function() if match == mine and not BOSS then spawnBoss() end end)
end

-- ---------- multiplayer: lobby, teams, champion select, shared casts and building health ----------
-- Every client runs the minions, jungle and bots; the server (server.lua) shares the players, building health and objectives.
do
local NET = Lol.NET
local sel = { open = false, idx = 1, picked = nil }
local lobby = { phase = 'lobby', players = {}, left = -1 }
local lastCount

local function champBySrc(src)
	for _, c in ipairs(CH) do
		if c.remote == src or (c.isPlayer and src == NET.me) then return c end
	end
end
Lol.champBySrc = champBySrc

local function pushSel()
	local list = {}
	for _, p in ipairs(lobby.players or {}) do
		list[#list + 1] = { name = p.name, team = p.team, champ = p.champ, me = p.src == NET.me }
	end
	if sel.open then Sigf.Nui({ selChamps = Lol.champList() }) end
	Sigf.Nui({ sel = { open = sel.open, idx = sel.idx, picked = sel.picked, left = lobby.left, phase = lobby.phase, players = list } })
end

function Lol.champList()
	local out = {}
	for _, ch in ipairs(Lol.CHAMPS) do
		out[#out + 1] = { id = ch.id, name = ch.name, title = ch.title, role = ch.role, col = ch.col, abil = ch.abil }
	end
	return out
end

function Lol.OpenLobby()
	NET.me = GetPlayerServerId(PlayerId())
	sel.open = true
	sel.picked = nil
	pushSel()
	TriggerServerEvent('lol:hello')
end

local function closeSelect()
	sel.open = false
	pushSel()
end

RegisterCommand('lol_left', function() if sel.open then sel.idx = (sel.idx - 2) % #Lol.CHAMPS + 1 pushSel() end end, false)
RegisterCommand('lol_right', function() if sel.open then sel.idx = sel.idx % #Lol.CHAMPS + 1 pushSel() end end, false)
RegisterCommand('lol_confirm', function()
	if not sel.open then return end
	local id = Lol.CHAMPS[sel.idx].id
	if sel.picked == id then TriggerServerEvent('lol:go')
	else
		sel.picked = id
		TriggerServerEvent('lol:pick', id, GetPlayerName(PlayerId()))
	end
	pushSel()
end, false)
RegisterKeyMapping('lol_left', 'Summoner: previous champion', 'keyboard', 'LEFT')
RegisterKeyMapping('lol_right', 'Summoner: next champion', 'keyboard', 'RIGHT')
RegisterKeyMapping('lol_confirm', 'Summoner: pick this champion / start now', 'keyboard', 'RETURN')

local function specFrom(list)
	local spec = { blue = {}, red = {} }
	table.sort(list, function(a, b) return a.team == b.team and a.slot < b.slot or a.team < b.team end)
	local low
	for _, p in ipairs(list) do
		spec[p.team][#spec[p.team] + 1] = { champ = p.champ, name = p.name, human = p.src, hero = p.src == NET.me, slot = p.slot }
		if not low or p.src < low then low = p.src end
	end
	NET.auth = low == NET.me
	return spec
end

local function beginNet(list, id, offset)
	closeSelect()
	NET.on = true
	NET.id = id
	Lol.spec = specFrom(list)
	math.randomseed(id * 7919)
	Lol.NewMatch()
	math.randomseed(GetGameTimer())
	if offset and offset > 0 then match.t0 = now() - offset * 1000 end
end

RegisterNetEvent('lol:lobby', function(data)
	lobby = data
	if sel.open then pushSel() end
	if data.phase == 'playing' and data.running and sel.open then
		Sigf.Nui({ banner = 'A MATCH IS RUNNING: PICK A CHAMPION TO JUMP IN', color = '#ffd45a', sec = 3 })
	end
end)
RegisterNetEvent('lol:full', function() banner('BOTH TEAMS ARE FULL', '#ff7a5a', 3) end)
RegisterNetEvent('lol:start', function(data) beginNet(data.players, data.id, 0) end)
RegisterNetEvent('lol:late', function(d)
	if d.src == NET.me then
		local list = {}
		for _, p in ipairs(lobby.players or {}) do if p.src ~= NET.me then list[#list + 1] = p end end
		list[#list + 1] = { src = d.src, name = d.name, team = d.team, slot = d.slot, champ = d.champ }
		beginNet(list, d.id, d.t)
		return
	end
	if not NET.on then return end
	-- a bot of that slot becomes the new player
	local n = 0
	for _, c in ipairs(CH) do
		if c.team == d.team then
			n = n + 1
			if n == d.slot and not c.remote and not c.isPlayer then
				if c.ped and DoesEntityExist(c.ped) then Sigf.Remove(c.ped) end
				local ch = Lol.CHAMP[d.champ]
				c.remote, c.ped, c.name, c.kit, c.id = d.src, nil, d.name, ch.kit, ch.id
				c.r = { team = c.team, name = d.name, lane = c.lane, kit = ch.kit, model = ch.model, weapon = ch.weapon, col = ch.col, id = ch.id }
				c.ready = { q = 0, w = 0, e = 0, r = 0 }
				banner(d.name .. ' HAS JOINED THE RIFT', '#7aff9a', 2.5)
				feed(d.name .. ' joined as ' .. ch.name, c.team)
				break
			end
		end
	end
end)
RegisterNetEvent('lol:left', function(src)
	local c = champBySrc(src)
	if c and c.remote then
		feed(c.name .. ' left the game', c.team)
		c.remote, c.ped, c.dead = nil, nil, false      -- the bot takes over
		spawnChamp(c, true)
	end
end)
RegisterNetEvent('lol:reset', function()
	if NET.on or match.running then
		match.running = false
		Lol.FullReset()
	end
	NET.on = false
	Lol.OpenLobby()
end)

-- ability casts of the other players are replayed here
RegisterNetEvent('lol:cast', function(src, k, ax, ay, az)
	if not NET.on or src == NET.me then return end
	local c = champBySrc(src)
	if not c or not c.ped or not DoesEntityExist(c.ped) then return end
	c.ready[k] = 0
	c.dead = false
	Lol.Cast(c, k, vector3(ax, ay, az))
end)
function Lol.netCast(k, aim)
	if NET.on then TriggerServerEvent('lol:cast', k, aim.x, aim.y, aim.z) end
end

RegisterNetEvent('lol:died', function(src, killer)
	if not NET.on or src == NET.me then return end
	local c = champBySrc(src)
	if not c or c.dead then return end
	local kc = killer ~= 0 and champBySrc(killer)
	if killer ~= 0 and killer == NET.me then kc = CH.hero end
	championDied(c, kc and kc.ped or nil)
end)
RegisterNetEvent('lol:back', function(src)
	local c = champBySrc(src)
	if c and src ~= NET.me then c.dead = false end
end)
RegisterNetEvent('lol:stat', function(src, lv, gold)
	local c = champBySrc(src)
	if c and src ~= NET.me then c.lv = lv c.gold = gold end
end)

-- building health comes from the server
RegisterNetEvent('lol:sh', function(id, left, src)
	if id:sub(1, 5) == 'drake' then Lol.drakeNet(id, left, src) return end
	if id:sub(1, 4) == 'boss' then
		if BOSS and BOSS.id == id and BOSS.alive then
			BOSS.hp = left
			if left <= 0 then
				local c = champBySrc(src)
				Lol.killBoss(c and c.ped or nil)
			end
		end
		return
	end
	for _, s in ipairs(S) do
		if s.id == id then
			s.hp = left
			s.hitAt = now()
			Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], s.pos + vector3(0, 0, 2.5 + math.random() * 2), { scale = 1.5 })
			if left <= 0 and s.alive and not match.over then
				local c = champBySrc(src)
				s.by = c and c.ped or nil
				if s.kind == 'nexus' then match.over = true end
				destroyStruct(s)
			end
			return
		end
	end
end)
RegisterNetEvent('lol:hpsync', function(hp)
	Lol.pendingHp = hp
end)
function Lol.applyHpSync()
	if not Lol.pendingHp then return end
	for _, s in ipairs(S) do
		local left = Lol.pendingHp[s.id]
		if left then
			s.hp = left
			if left <= 0 and s.alive then s.alive = false Sigf.Remove(s.ent) end
		end
	end
	Lol.pendingHp = nil
end
RegisterNetEvent('lol:over', function(winner)
	if match.over then return end
	match.over = true
end)

-- one hit on a building, reported to the server (everybody sees the same health)
function Lol.netStructHit(s, dmg, by)
	local me = PlayerPedId()
	local owner = by and champOf(by)
	if owner and owner.remote then return end             -- its player reports it
	if by ~= me and not NET.auth then return end           -- bots, minions and turrets: the first player reports them
	TriggerServerEvent('lol:sh', s.id, math.floor(dmg + 0.5), s.max)
end

-- my own level and my deaths are told to the others
Sigf.Every(3.0, function()
	local h = CH.hero
	if NET.on and h and h.isPlayer then TriggerServerEvent('lol:stat', h.lv, math.floor(h.gold)) end
end, 'lol_net_stat')

-- remote players: find their game ped; a remote player who is not near enough yet has none
Sigf.Every(0.5, function()
	if not NET.on then return end
	for _, c in ipairs(CH) do
		if c.remote then
			local pid = GetPlayerFromServerId(c.remote)
			c.ped = pid ~= -1 and GetPlayerPed(pid) or nil
			if c.ped and not DoesEntityExist(c.ped) then c.ped = nil end
		end
	end
end, 'lol_net_resolve')

-- friendly fire between players is undone
local lastHp = 0
Sigf.Every(0.1, function()
	local me = PlayerPedId()
	if NET.on and DoesEntityExist(me) then lastHp = GetEntityHealth(me) end
end, 'lol_net_hp')
AddEventHandler('gameEventTriggered', function(name, args)
	if not NET.on or name ~= 'CEventNetworkEntityDamage' then return end
	local victim, attacker = args[1], args[2]
	if victim ~= PlayerPedId() or not attacker or attacker == victim or not IsPedAPlayer(attacker) then return end
	local ac, me = champOf(attacker), CH.hero
	if ac and me and ac.team == me.team then
		SetEntityHealth(victim, math.max(GetEntityHealth(victim), lastHp))
	end
end)

function Lol.netBossHit(dmg, by)
	if not (BOSS and BOSS.alive) then return end
	local owner = by and champOf(by)
	if owner and owner.remote then return end
	if by ~= PlayerPedId() and not NET.auth then return end
	TriggerServerEvent('lol:sh', BOSS.id, math.floor(dmg + 0.5), BOSS.max)
end

function Lol.netObjHit(id, dmg, max, by)
	local owner = by and champOf(by)
	if owner and owner.remote then return end
	if by ~= PlayerPedId() and not NET.auth then return end
	TriggerServerEvent('lol:sh', id, math.floor(dmg + 0.5), max)
end

function Lol.NetOver() return NET.on end
end

-- ---------- timers ----------
local function startup()
	Sigf.Frame(frame, 'lol_frame')
	Sigf.Every(0.5, function()
		if not match.running then return end
		for ped, m in pairs(M) do
			if not DoesEntityExist(ped) then M[ped] = nil minionCount = math.max(0, minionCount - 1)
			elseif IsPedDeadOrDying(ped, true) then
				m.deadAt = m.deadAt or now()
				if now() - m.deadAt > 4500 then Sigf.Remove(ped) M[ped] = nil end
			else
				Sigf.Safe('minion', minionTick, ped, m)
			end
		end
		if not match.over then
			for _, c in ipairs(CH) do Sigf.Safe('think', think, c) end
			Sigf.Safe('jungle', jungleTick)
			Sigf.Safe('boss', bossTick)
		end
	end, 'lol_units')
	Sigf.Every(1.2, function() if match.running and not match.over then turretTick() end end, 'lol_turrets')
	Sigf.Every(1.0, function()
		if not match.running then return end
		baseTick()
		if not DEMO and BOSS and not BOSS.alive and match.bossDead and now() - match.bossDead > 240000 then
			BOSS = nil match.bossDead = nil spawnBoss()
		end
		if not (HOME or DEMO) and now() > (Lol.focusUntil or 0) then
			-- the stream camera follows the busiest lane
			local best, bn = nil, 0
			for name, ln in pairs(LANES) do
				local n, sum = 0, vector3(0, 0, 0)
				for ped, m in pairs(M) do
					if m.lane == name and alive(ped) then n = n + 1 sum = sum + GetEntityCoords(ped) end
				end
				for _, c in ipairs(CH) do
					if c.lane == name and alive(c.ped) then n = n + 3 sum = sum + GetEntityCoords(c.ped) * 3 end
				end
				if n > bn then best, bn = sum / n, n end
			end
			Sigf.Focus(best or L.c, 3)
		end
	end, 'lol_misc')
	Sigf.Every(0.2, function()
		if not match.running then return end
		recallTick()
		local h = CH.hero
		if h and h.isPlayer and not god() and not h.dead and IsPedDeadOrDying(h.ped, true) then
			championDied(h, GetPedSourceOfDeath(h.ped))
		end
		if h and h.dead and h.isPlayer then
			Sigf.Nui({ respawn = { sec = math.max(0, (h.respawnAt - now()) / 1000.0) } })
		end
		if hud.shopOpen and not hud.near then hud.shopOpen = false Sigf.Nui({ shop = { open = false } }) end
	end, 'lol_player')
	Sigf.Every(0.15, function() if match.running then sendHud() end end, 'lol_hud')
	if HOME then
		CreateThread(function()
			while true do
				Wait(0)
				SetPedDensityMultiplierThisFrame(0.0)
				SetVehicleDensityMultiplierThisFrame(0.0)
				SetRandomVehicleDensityMultiplierThisFrame(0.0)
				SetParkedVehicleDensityMultiplierThisFrame(0.0)
				SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
				HideHudComponentThisFrame(1) HideHudComponentThisFrame(3) HideHudComponentThisFrame(4)
				HideHudComponentThisFrame(6) HideHudComponentThisFrame(7) HideHudComponentThisFrame(9)
			end
		end)
	end
end

-- In the recorded demo the match starts with the recording, so the demo steps and the match stay in step.
local recSeen, started = false, false
local function begin()
	if started then return end
	started = true
	Lol.NewMatch()
end
RegisterNetEvent('sigf:rec', function() recSeen = true if L then begin() end end)
Sigf.After(1.5, function()
	CreateThread(function()
		if HOME then prepareHome() end
		layout()
		startup()
		if HOME then Lol.OpenLobby() elseif not DEMO or recSeen then begin() end
	end)
end)
if DEMO then Sigf.After(150, begin) end

do
-- ---------- poros: the fluffy mascots of the Rift ----------
-- A herd of Poros hops around the lanes, every champion has one as a pet, the crowned Poro King sits by the river.
-- Anything that hits them (carbine bullets, Starbolt, meteors) pops them for gold; the King's fall starts a Poro Rain.
local PORO, KING, HATS = {}, nil, {}
local POROS_WILD = DEMO and 9 or 12
local PORO_FACE = 180.0

local function poroPos(p) return vector3(p.x, p.y, p.z + p.zz) end

local function poroPlace(p, heading)
	local x, y, z = p.x, p.y, p.z + p.zz
	if p.rx then
		SetEntityCoordsNoOffset(p.ent, x, y, z, false, false, false)
		SetEntityRotation(p.ent, p.rx, p.rz or 0.0, heading + PORO_FACE, 2, true)
		return
	end
	local sc = p.scale or 1.0
	local h = math.rad(heading + PORO_FACE)
	SetEntityMatrix(p.ent, -math.sin(h) * sc, math.cos(h) * sc, 0.0, math.cos(h) * sc, math.sin(h) * sc, 0.0, 0.0, 0.0, sc, x, y, z)
end

local function poroNew(x, y, opts)
	opts = opts or {}
	skin('sigf_poro')
	local z = gz(x, y, L.c.z)
	local ent = Sigf.Prop('sigf_poro', vector3(x, y, z + (opts.drop or 0.0)), { frozen = true, life = 900, heading = 0.0 })
	if not ent then return nil end
	local p = { ent = ent, x = x, y = y, z = z, zz = opts.drop or 0.0, vz = 0.0, state = opts.drop and 'fall' or 'idle',
		phase = math.random(), head = math.random(0, 359) + 0.0, pet = opts.pet, wild = not opts.pet, tx = x, ty = y, next = 0, gt = 0, side = 1.0,
		scale = opts.scale or (opts.pet and 0.85 or (1.0 + math.random() * 0.9)) }
	PORO[#PORO + 1] = p
	poroPlace(p, p.head)
	return p
end

local function poroPoof(pos, scale)
	-- a burst of white fluff
	Sigf.Fx('core', 'ent_sht_feathers', pos, { scale = (scale or 1.5) * 1.2 })
	Sigf.Fx('core', 'ent_sht_feathers', pos + vector3(0, 0, 0.5), { scale = (scale or 1.5) * 0.8 })
end

-- a shower of tiny Poros: the fluff of a pop
local function poroBurst(pos, n, speed)
	for i = 1, n do
		local p = poroNew(pos.x, pos.y, { scale = 0.28 + math.random() * 0.2 })
		if p then
			p.wild = false
			p.state, p.mini, p.t, p.life = 'fly', true, 0.0, 0.9 + math.random() * 0.5
			p.zz = math.max(0.0, pos.z - p.z)
			local a, sp = math.random() * 6.283, (0.4 + math.random() * 0.6) * (speed or 5.0)
			p.vx, p.vy, p.vz = math.cos(a) * sp, math.sin(a) * sp, 3.0 + math.random() * (speed or 5.0)
			p.rx, p.rz = 0.0, 0.0
		end
	end
end

-- poros fall from the sky around (cx, cy)
function Lol.PoroRain(n, cx, cy, spread)
	local mine = match
	for i = 1, n do
		Sigf.After(i * 0.12, function()
			if match ~= mine or mine.over then return end
			local a, r = math.random() * 6.283, math.sqrt(math.random()) * spread
			poroNew(cx + math.cos(a) * r, cy + math.sin(a) * r, { drop = 14.0 + math.random() * 12.0 })
		end)
	end
end

local function poroPop(p, by)
	if p.state == 'fly' then return end
	p.state = 'fly'
	p.t = 0.0
	p.vx, p.vy, p.vz = (math.random() - 0.5) * 6.0, (math.random() - 0.5) * 6.0, 9.0
	p.rx, p.rz = 0.0, 0.0
	local pos = poroPos(p)
	Sigf.Sound('poro_squeak', pos, { volume = 0.7 })
	poroBurst(pos + vector3(0, 0, 0.3), 6, 5.0)
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], pos + vector3(0, 0, 0.4), { scale = 1.2 })
	local c = (by and champOf and champOf(by)) or CH.hero
	if c then
		addGold(c, 25, pos)
		if c.isPlayer then Sigf.Text3D('PORO!', pos + vector3(0, 0, 1.6), 1.2, { color = { 255, 255, 255 }, scale = 0.6 }) end
	end
end

local KING_HP = DEMO and 9 or 14
local function kingSpawn()
	if KING or not L then return end
	skin('sigf_poro_king')
	local pos = W(-12.0, 15.0)
	local ent = Sigf.Prop('sigf_poro_king', pos, { ground = true, heading = L.dirHeading + 180.0 + PORO_FACE, life = 900 })
	if not ent then return end
	KING = { ent = ent, pos = pos, hp = KING_HP, wobT = 0, hitAt = 0, heading = GetEntityHeading(ent) }
	Sigf.Fx(Sigf.FX.firework[1], Sigf.FX.firework[2], pos + vector3(0, 0, 6), { scale = 2.0 })
	if not DEMO then banner('THE PORO KING HAS ARRIVED', '#ffe08a', 3) end
end

local function kingHit(by)
	if not KING then return end
	KING.hp = KING.hp - 1
	KING.wobT = now()
	local top = KING.pos + vector3(0, 0, 3.0)
	Sigf.Sound('poro_squeak', KING.pos, { volume = 0.9 })
	poroBurst(top + vector3((math.random() - 0.5) * 3.0, (math.random() - 0.5) * 3.0, math.random() * 1.5), 3, 6.0)
	Sigf.Text3D('SQUEAK!', top + vector3((math.random() - 0.5) * 2.0, 0, 1.2), 1.0, { color = { 255, 255, 255 }, scale = 0.7 })
	Sigf.Light(top, { 255, 255, 255 }, 10.0, 6.0, 0.15)
	Sigf.Shake(0.15)
	local c = (by and champOf and champOf(by)) or CH.hero
	if c then addGold(c, 10, top) end
	if KING.hp <= 0 then
		local pos = KING.pos
		Sigf.Remove(KING.ent) KING = nil
		poroPoof(pos + vector3(0, 0, 2.5), 3.0)
		poroBurst(pos + vector3(0, 0, 3.0), 26, 9.0)
		Sigf.Fx(Sigf.FX.firework[1], Sigf.FX.firework[2], pos + vector3(0, 0, 6), { scale = 3.0 })
		banner('THE PORO KING HAS FALLEN: PORO RAIN!', '#ffe08a', 3.5)
		if c then addGold(c, 150, pos) end
		Lol.PoroRain(DEMO and 20 or 24, pos.x, pos.y, 22.0)
		local mine = match
		Sigf.After(DEMO and 40 or 90, function() if match == mine and not mine.over then kingSpawn() end end)
	end
end

-- called with the impact point of anything that can hurt: bullets, bolts, meteors
function Lol.poroHit(pos, radius, by)
	for _, p in ipairs(PORO) do
		if p.wild and p.state == 'idle' and #(poroPos(p) + vector3(0, 0, 0.45 * p.scale) - pos) < radius + 0.75 * p.scale then poroPop(p, by) end
	end
	if KING and #(vector3(KING.pos.x, KING.pos.y, 0.0) - vector3(pos.x, pos.y, 0.0)) < radius + 2.6 and pos.z - KING.pos.z < 5.8 + radius then
		if now() - KING.hitAt > 120 then KING.hitAt = now() kingHit(by) end
	end
end

local function poroFrame(dt)
	if not match or not match.running or not L then return end
	local me = PlayerPedId()
	if IsPedShooting(me) then
		local ok, c = GetPedLastWeaponImpactCoord(me)
		if ok then Lol.poroHit(c, 0.2, me) end
	end
	-- spells that fly (arrows, bolts, orbs, fireballs) pop Poros and chip the King too
	for _, q in ipairs(fx.projs) do Lol.poroHit(q.pos, (q.rad or 1.0) * 0.5, q.c and q.c.ped) end
	local t = now() / 1000.0
	for i = #PORO, 1, -1 do
		local p = PORO[i]
		if not DoesEntityExist(p.ent) then table.remove(PORO, i)
		elseif p.state == 'fall' then
			p.vz = p.vz - 22.0 * dt
			p.zz = p.zz + p.vz * dt
			if p.zz <= 0.0 then
				p.zz = 0.0
				if p.vz < -5.0 then
					if not p.landed then p.landed = true poroPoof(vector3(p.x, p.y, p.z + 0.2), 0.8) end
					p.vz = -p.vz * 0.42
				else p.vz = 0.0 p.state = 'idle' end
			end
			poroPlace(p, p.head)
		elseif p.state == 'fly' then
			p.t = p.t + dt
			p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
			p.vz = p.vz - 16.0 * dt
			p.zz = p.zz + p.vz * dt
			p.rx, p.rz = p.rx + 520.0 * dt, p.rz + 300.0 * dt
			poroPlace(p, p.head)
			if p.mini then
				if p.zz <= 0.0 and p.t > 0.3 or p.t > (p.life or 1.2) then
					Sigf.Remove(p.ent)
					table.remove(PORO, i)
				end
			elseif p.t > 0.75 then
				poroPoof(poroPos(p), 1.2)
				Sigf.Remove(p.ent)
				table.remove(PORO, i)
			end
		else
			-- idle: wander (wild) or follow the owner (pet)
			local mx, my = p.x, p.y
			if p.pet then
				local o = p.pet
				if alive(o) then
					local op, f = GetEntityCoords(o), GetEntityForwardVector(o)
					mx, my = op.x + f.x * 0.8 - f.y * p.side * 1.6, op.y + f.y * 0.8 + f.x * p.side * 1.6
					if #(vector3(p.x, p.y, 0.0) - vector3(op.x, op.y, 0.0)) > 25.0 then p.x, p.y = mx, my end
				end
			else
				if t > p.next then
					local a, r = math.random() * 6.283, 4.0 + math.random() * 14.0
					p.tx, p.ty = p.x + math.cos(a) * r, p.y + math.sin(a) * r
					local u, v = toLane(vector3(p.tx, p.ty, 0.0))
					if math.abs(u) > N - 6.0 or math.abs(v) > 38.0 then p.tx, p.ty = L.c.x, L.c.y end
					p.next = t + 3.0 + math.random() * 4.0
				end
				mx, my = p.tx, p.ty
			end
			local dx, dy = mx - p.x, my - p.y
			local d = math.sqrt(dx * dx + dy * dy)
			local moving = d > 0.7
			if moving then
				local speed = p.pet and clamp(d * 1.6, 1.6, 8.0) or 2.1
				p.x, p.y = p.x + dx / d * speed * dt, p.y + dy / d * speed * dt
				p.head = GetHeadingFromVector_2d(dx, dy)
			end
			p.phase = p.phase + dt * (moving and 1.7 or 0.5)
			p.zz = math.abs(math.sin(p.phase * 3.1416)) * (moving and 0.5 or 0.07)
			p.gt = p.gt - dt
			if p.gt <= 0 then p.gt = 0.3 p.z = gz(p.x, p.y, p.z) end
			p.rx = nil
			poroPlace(p, p.head)
		end
	end
	-- the Poro King: jiggle, name and health bar
	if KING and DoesEntityExist(KING.ent) then
		local w = math.max(0.0, 1.0 - (now() - KING.wobT) / 700.0)
		SetEntityRotation(KING.ent, math.sin(t * 28.0) * 7.0 * w, math.cos(t * 23.0) * 5.0 * w, KING.heading, 2, true)
		local head = KING.pos + vector3(0, 0, 6.6)
		if #(head - GetFinalRenderedCamCoord()) < 120.0 then
			label(head + vector3(0, 0, 0.5), 'PORO KING', { 255, 224, 138 }, 0.5)
			bar(head, KING.hp / KING_HP, 0.09, { 255, 200, 60 })
		end
	elseif KING then KING = nil end
end

local function poroTick()
	if not match or not match.running or match.over or not L then return end
	-- keep the wild herd topped up: new ones drop from the sky
	local wild = 0
	for _, p in ipairs(PORO) do if p.wild then wild = wild + 1 end end
	if wild < POROS_WILD then
		local w = W((math.random() - 0.5) * 2.0 * (N - 12.0), (math.random() - 0.5) * 40.0)
		poroNew(w.x, w.y, { drop = 25.0 })
	end
	-- every living champion keeps a pet Poro
	local pets = {}
	for i = #PORO, 1, -1 do
		local p = PORO[i]
		if p.pet then
			if DoesEntityExist(p.pet) then pets[p.pet] = true
			else Sigf.Remove(p.ent) table.remove(PORO, i) end
		end
	end
	for i, c in ipairs(CH) do
		if c.ped and DoesEntityExist(c.ped) and not pets[c.ped] and not c.dead then
			local cp = GetEntityCoords(c.ped)
			local p = poroNew(cp.x + 1.0, cp.y + 1.0, { pet = c.ped })
			if p then p.side = (i % 2 == 0) and 1.1 or -1.1 end
		end
	end
end

-- silly hats so minions read at a glance: cones for casters, hard hats for warriors, buckets for the big ones
local function hatKind(m)
	if m.kind == 'caster' then return 'prop_roadcone02a', vector3(0.0, 0.0, 0.1)
	elseif m.kind == 'super' then return 'prop_bucket_01a', vector3(0.0, 0.02, 0.2)
	else return 'prop_hard_hat_01', vector3(0.0, 0.03, 0.1) end
end

local function hatTick()
	if not match or not match.running then return end
	for ped, m in pairs(M) do
		local h = HATS[ped]
		if alive(ped) then
			if not h or not DoesEntityExist(h) then
				local model, off = hatKind(m)
				local e = Sigf.Prop(model, GetEntityCoords(ped) + vector3(0, 0, 2.0), { frozen = false, life = 200 })
				if e then
					SetEntityCollision(e, false, false)
					Sigf.Attach(e, ped, 31086, off, vector3(0, 0, 0))
					HATS[ped] = e
				end
			end
		elseif h then
			Sigf.Remove(h) HATS[ped] = nil
		end
	end
	for ped, h in pairs(HATS) do
		if not M[ped] then Sigf.Remove(h) HATS[ped] = nil end
	end
end

function Lol.PoroClear()
	for i = #PORO, 1, -1 do Sigf.Remove(PORO[i].ent) PORO[i] = nil end
	if KING then Sigf.Remove(KING.ent) KING = nil end
	for ped, h in pairs(HATS) do Sigf.Remove(h) HATS[ped] = nil end
end

-- the match begins: a first Poro Rain, the King, and a pet for every champion
function Lol.PoroStart()
	local mine = match
	local c0 = W(DEMO and -30.0 or -25.0, 0.0)
	Sigf.After(0.6, function() if match == mine then Lol.PoroRain(DEMO and 26 or 14, c0.x, c0.y, DEMO and 20.0 or 24.0) end end)
	Sigf.After(1.5, function() if match == mine then kingSpawn() end end)
	Sigf.After(2.5, function()
		if match ~= mine then return end
		for i, c in ipairs(CH) do
			if c.ped and DoesEntityExist(c.ped) then
				local cp = GetEntityCoords(c.ped)
				local p = poroNew(cp.x + 1.0, cp.y + 1.0, { pet = c.ped })
				if p then p.side = (i % 2 == 0) and 1.1 or -1.1 end
			end
		end
	end)
end

-- on the stream, the camera drops by the Poro King now and then
if not HOME and not DEMO then
	Sigf.Every(40, function()
		if match and match.running and not match.over and KING and now() > (Lol.focusUntil or 0) then
			Sigf.Focus(KING.pos + vector3(0, 0, 3.0), 8)
			Lol.focusUntil = now() + 8000
		end
	end, 'lol_poro_cam')
end
Sigf.After(DEMO and 99999 or 7.0, function()
	if not HOME and not DEMO and KING then Sigf.Focus(KING.pos + vector3(0, 0, 3.0), 8) Lol.focusUntil = now() + 8000 end
end)
Sigf.Frame(poroFrame, 'lol_poro')
Sigf.Every(2.0, function() Sigf.Safe('poroTick', poroTick) end, 'lol_poro_tick')
Sigf.Every(0.8, function() Sigf.Safe('hatTick', hatTick) end, 'lol_hats')
function Lol.Poro() return PORO, KING end
end

-- ---------- the Rift Drakes: an objective in the bottom river, every kill empowers the whole team ----------
-- A fire drake and an ocean drake take turns. Hit it with anything (carbine, arrows, spells); when it falls every champion
-- of the killing team gets stronger for the rest of the match, and the team earns gold.
do
local DRAKE
local TYPES = {
	{ key = 'fire',  model = 'sigf_drake_fire',  name = 'INFERNO DRAKE', col = { 255, 120, 40 }, text = 'INFERNO SOUL: +7% damage for the rest of the match' },
	{ key = 'ocean', model = 'sigf_drake_ocean', name = 'OCEAN DRAKE',   col = { 80, 200, 255 }, text = 'OCEAN SOUL: +7% damage and +4% speed for the rest of the match' },
}
local FACE = 180.0
local serial = 0

local function drakeSpawn()
	if DRAKE or not L or not match.running or match.over then return end
	serial = serial + 1
	local ty = TYPES[(serial - 1) % 2 + 1]
	skin(ty.model)
	local pos = W(0.0, -0.62 * T)
	local ent = Sigf.Prop(ty.model, pos, { ground = true, heading = L.dirHeading + 90.0 + FACE })
	if not ent then return end
	local hp = DEMO and 520 or 1500
	DRAKE = { id = 'drake' .. serial, ent = ent, pos = GetEntityCoords(ent), hp = hp, max = hp, alive = true, ty = ty, r = 3.6, top = 4.6, atk = 0, born = now(),
		heading = GetEntityHeading(ent), base = GetEntityCoords(ent) }
	if not DEMO then banner('THE ' .. ty.name .. ' HAS APPEARED IN THE SOUTH RIVER', '#' .. string.format('%02x%02x%02x', ty.col[1], ty.col[2], ty.col[3]), 3.5) end
	feed('The ' .. ty.name:lower():gsub('^%l', string.upper) .. ' has appeared', 'blue')
	Sigf.Sound('baron_roar', DRAKE.pos, { range = 200.0, volume = 0.8 })
	Sigf.Shake(0.2)
	Sigf.Fx(Sigf.FX.firework[1], Sigf.FX.firework[2], DRAKE.pos + vector3(0, 0, 8), { scale = 2.0 })
end

local function drakeKilled(by)
	local d = DRAKE
	if not d or not d.alive then return end
	d.alive = false
	local kc = by and champOf(by)
	local team = kc and kc.team or (CH.hero and CH.hero.team) or 'blue'
	local p = d.pos
	Sigf.Sound('baron_die', p, { range = 220.0, volume = 0.9 })
	Sigf.Shake(0.7)
	for i = 0, 4 do
		Sigf.After(i * 0.3, function()
			local q = p + vector3(math.random(-3, 3), math.random(-3, 3), 1.0 + i * 0.9)
			boom(q, 4, { scale = 0.6, shake = 0.9 })
			Sigf.Fx('core', 'exp_grd_molotov', q, { scale = 1.4 })
			Sigf.Light(q, d.ty.col, 18.0, 10.0, 0.5)
		end)
	end
	local ent = d.ent
	Sigf.After(2.5, function() Sigf.Remove(ent) end)
	match.drk = match.drk or { blue = 0, red = 0 }
	match.drk[team] = match.drk[team] + 1
	local n = match.drk[team]
	for _, c in ipairs(CH) do
		if c.team == team then addGold(c, 150) addXp(c, 100) recalc(c) end
	end
	banner((team == 'blue' and 'ORDER' or 'VOID') .. ' SLEW THE ' .. d.ty.name .. '  (x' .. n .. ')', team == 'blue' and '#7ac8ff' or '#ff7a5a', 4)
	feed((team == 'blue' and 'Order' or 'Void') .. ' slew the ' .. d.ty.name:lower() .. ' (x' .. n .. ')', team)
	Sigf.Sound('buff_get', nil, { volume = 0.8 })
	Sigf.Text3D('DRAKE SOUL x' .. n, fountainPos(team) + vector3(0, 0, 4.0), 5, { color = d.ty.col, scale = 0.8 })
	if kc and kc.isPlayer then Lol.quest('drake') end
	DRAKE = nil
	local mine = match
	Sigf.After(DEMO and 40 or 150, function() if match == mine and not mine.over then drakeSpawn() end end)
	d.dead = { at = now(), ent = ent }
	DRAKE = nil
end
Lol.drakeKilled = drakeKilled

function Lol.hurtDrake(dmg, col, by)
	local d = DRAKE
	if not (d and d.alive) then return end
	d.hitAt = now()
	d.agro = now() + 10000
	Sigf.Text3D(tostring(math.floor(dmg)), d.pos + vector3(math.random() * 2 - 1, math.random() * 2 - 1, 4.5), 0.9, { color = col or { 255, 255, 255 }, scale = 0.6 })
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], d.pos + vector3(math.random() * 3 - 1.5, math.random() * 3 - 1.5, 1.5 + math.random() * 2), { scale = 1.6 })
	Sigf.Sound('camp_hit', d.pos, { range = 80.0, volume = 0.5 })
	d.by = by or d.by
	if Lol.NET.on then Lol.netObjHit(d.id, dmg, d.max, by) return end
	d.hp = d.hp - dmg
	if d.hp <= 0 then drakeKilled(d.by) end
end
function Lol.drakeNet(id, left, src)
	local d = DRAKE
	if not (d and d.id == id and d.alive) then return end
	d.hp = left
	if left <= 0 then
		local c = Lol.champBySrc and Lol.champBySrc(src)
		drakeKilled(c and c.ped or nil)
	end
end
function Lol.Drake() return DRAKE end
function Lol.SpawnDrake() if not DRAKE then drakeSpawn() end end

local function drakeFrame(dt)
	local d = DRAKE
	if not d or not d.alive or not DoesEntityExist(d.ent) then return end
	local t0 = now()
	local t = t0 / 1000.0
	-- idle motion: a slow sway of the whole body
	SetEntityRotation(d.ent, math.sin(t * 1.3) * 2.0, math.sin(t * 0.9) * 2.5, d.heading, 2, true)
	local cam = GetFinalRenderedCamCoord()
	if #(d.pos - cam) < 160.0 then
		local flash = (d.hitAt and t0 - d.hitAt < 150) and 1.0 or 0.0
		local c = d.ty.col
		DrawLightWithRange(d.pos.x, d.pos.y, d.pos.z + 3.0, c[1], c[2], c[3], 14.0 + flash * 8, 4.0 + flash * 6)
		ring(d.pos + vector3(0, 0, 0.1), 11.0, c, 40, 0.2)
		bar(d.pos + vector3(0, 0, d.top + 1.4), d.hp / d.max, 0.11, c)
		label(d.pos + vector3(0, 0, d.top + 2.0), d.ty.name, c, 0.4)
	end
	-- gunfire of the player
	local me = PlayerPedId()
	if IsPedShooting(me) then
		local ok, ip = GetPedLastWeaponImpactCoord(me)
		if ok and ip and dist2(ip, d.pos) < d.r + 1.5 and ip.z < d.pos.z + d.top + 1.0 then
			local h = CH.hero
			Lol.hurtDrake(4.5 * (h and h.mul or 1.0), { 255, 255, 255 }, me)
		end
	end
end

local function drakeTick()
	local d = DRAKE
	if not d or not d.alive then return end
	local t0 = now()
	local list = Lol.foes('neutral', d.pos, 24.0, true)
	local target
	for _, f in ipairs(list) do if not target or f.d < target.d then target = f end end
	if target and t0 > d.atk then
		d.atk = t0 + 2200
		d.n = (d.n or 0) + 1
		local from = d.pos + vector3(0, 0, 3.6)
		if d.n % 3 == 0 then
			Sigf.Sound('baron_roar', d.pos, { range = 120.0, volume = 0.6 })
			Sigf.Marker(1, d.pos + vector3(0, 0, 0.2), vector3(13.0, 13.0, 0.2), { d.ty.col[1], d.ty.col[2], d.ty.col[3], 90 }, 0.7)
			Sigf.After(0.7, function()
				if not d.alive then return end
				boom(d.pos + vector3(0, 0, 0.5), 0, { scale = 0.0, shake = 0.5 })
				Sigf.Fx('core', 'exp_grd_molotov', d.pos + vector3(0, 0, 0.5), { scale = 1.6 })
				for _, f in ipairs(Lol.foes('neutral', d.pos, 6.5, true)) do
					hurt(f.ped, f.champ and 60 or 110, nil, d.ty.col)
					knock(f.ped, norm2(f.pos - d.pos), 8.0)
				end
			end)
		else
			Sigf.Sound('baron_spit', d.pos, { range = 100.0, volume = 0.7 })
			fx.beams[#fx.beams + 1] = { a = from, b = target.pos + vector3(0, 0, 1.0), col = d.ty.col, to = t0 + 400 }
			Sigf.Light(from, d.ty.col, 14.0, 9.0, 0.4)
			Sigf.Fx('core', d.ty.key == 'fire' and 'exp_grd_molotov_lod' or 'exp_grd_bzgas_smoke', target.pos + vector3(0, 0, 0.5), { scale = 1.0 })
			hurt(target.ped, target.champ and 42 or 100, nil, d.ty.col)
			knock(target.ped, norm2(target.pos - d.pos), 3.0)
		end
		SetEntityHeading(d.ent, GetHeadingFromVector_2d(target.pos.x - d.pos.x, target.pos.y - d.pos.y) + FACE)
		d.heading = GetEntityHeading(d.ent)
	elseif not target and d.hp < d.max and t0 > (d.agro or 0) then
		d.hp = math.min(d.max, d.hp + d.max * 0.01)
	end
end

Sigf.Frame(drakeFrame, 'lol_drake')
Sigf.Every(0.5, function() Sigf.Safe('drakeTick', drakeTick) end, 'lol_drake_tick')
-- the first drake arrives a little after the Void Nashor; the next ones follow the match clock
function Lol.DrakeStart()
	local mine = match
	Sigf.After(DEMO and 5.0 or 90.0, function() if match == mine and not mine.over then drakeSpawn() end end)
end
function Lol.DrakeClear()
	if DRAKE then Sigf.Remove(DRAKE.ent) DRAKE = nil end
	serial = 0
end

-- the projectiles and spells find the drake through hitThings; arrows through here:
Sigf.Frame(function(dt)
	local d = DRAKE
	if not d or not d.alive then return end
	for _, q in ipairs(fx.projs) do
		if not q.hitDrake and dist2(d.pos, q.pos) < d.r + (q.rad or 1.0) and q.pos.z < d.pos.z + d.top then
			q.hitDrake = true
			Lol.hurtDrake(q.dmg * 0.9, q.col, q.c.ped)
			if q.stop then q.dist = q.max + 1 end
		end
	end
end, 'lol_drake_proj')
end

-- ---------- for demo.lua ----------
function Lol.ChampById(team, id)
	for _, c in ipairs(CH) do if c.team == team and c.id == id then return c end end
end
-- cast right now, whatever the cooldown (the demo shows each ability when it wants to)
function Lol.Force(c, k, aim)
	if not c or not alive(c.ped) then return false end
	c.ready[k] = 0
	c.dead = false
	return Lol.Cast(c, k, aim)
end
-- put an AI champion somewhere (its ped is local)
function Lol.Bring(c, pos, faceTo)
	if not c or not alive(c.ped) or c.isPlayer then return end
	SetEntityCoords(c.ped, pos.x, pos.y, pos.z + 0.5, false, false, false, false)
	if faceTo then local d = norm2(faceTo - pos) SetEntityHeading(c.ped, GetHeadingFromVector_2d(d.x, d.y)) end
end
function Lol.PoroKing() local _, k = Lol.Poro() return k end
function Lol.SetKit(c, id)
	local ch = Lol.CHAMP[id]
	if not c or not ch then return end
	c.kit, c.id, c.name = ch.kit, ch.id, ch.name
	c.r.col = ch.col
	c.ready = { q = 0, w = 0, e = 0, r = 0 }
	if c.isPlayer then
		-- the player puts on the champion's look
		local mh = GetHashKey(pickModel(ch.model))
		if GetEntityModel(PlayerPedId()) ~= mh then
			RequestModel(mh)
			local t = GetGameTimer() + 3000
			while not HasModelLoaded(mh) and GetGameTimer() < t do Wait(0) end
			if HasModelLoaded(mh) then SetPlayerModel(PlayerId(), mh) SetPedCanRagdoll(PlayerPedId(), not DEMO) end
		end
		c.ped = PlayerPedId()
		recalc(c)
		SetPedMaxHealth(c.ped, 100 + c.hpmax)
		SetEntityHealth(c.ped, 100 + c.hpmax)
		SetPedArmour(c.ped, 40)
		equip(c)
		Lol.Dress(c)
	end
	recalc(c)
end
-- a lane minion that is only there to be hit (the demo)
function Lol.Dummy(team, pos, kind)
	local k = KINDS[kind or 'warrior']
	local ped = Sigf.Ped(k[team], pos + vector3(0, 0, 0.6), { enemy = team == 'red', weapon = k.weapon, health = 400, fight = false, life = 40,
		heading = GetHeadingFromVector_2d(L.dir.x * (team == 'red' and -1 or 1), L.dir.y * (team == 'red' and -1 or 1)) })
	if ped then
		SetPedKeepTask(ped, true)
		M[ped] = { team = team, kind = kind or 'warrior', lane = 'mid', born = now(), def = k, max = 400 }
		minionCount = minionCount + 1
	end
	return ped
end
function Lol.Champ(team) if team == 'blue' or team == nil then return CH.hero end for _, c in ipairs(CH) do if c.team == team then return c end end end
function Lol.Struct(kind, team, lane, tier)
	if kind == 'nexus' then return S.nexus and S.nexus[team] end
	for _, s in ipairs(S) do
		if s.kind == kind and s.team == team and (not lane or s.lane == lane) and (not tier or s.tier == tier) then return s end
	end
end
function Lol.HurtStruct(s, dmg) if s then hurtStruct(s, dmg, { 255, 255, 255 }, PlayerPedId()) end end
function Lol.Match() return match end
function Lol.Boss() return BOSS end
function Lol.AutoBuy() local h = CH.hero if h then autoBuy(h) end end
function Lol.SpawnBoss() if not BOSS then spawnBoss() end end
function Lol.HurtBoss(dmg) Lol.hurtBoss(dmg, { 255, 255, 255 }, PlayerPedId()) end
function Lol.At(u, v) return W(u, v) end
function Lol.LaneAt(name, frac, lat) local ln = LANES[name] return ln and lanePos(ln, ln.len * frac, lat or 0) end
function Lol.Fountain(team) return fountainPos(team) end
function Lol.LookAtPoint(p)
	local me = PlayerPedId()
	local d = norm2(p - GetEntityCoords(me))
	SetEntityHeading(me, GetHeadingFromVector_2d(d.x, d.y))
	if DEMO then Sigf.After(0.15, function() SetGameplayCamRelativeHeading(0.0) end) end      -- the camera comes back behind the hero
end
function Lol.Warp(p, headingTo)
	local me = PlayerPedId()
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], GetEntityCoords(me), { scale = 2.5 })
	SetEntityCoords(me, p.x, p.y, p.z + 0.5, false, false, false, false)
	if headingTo then Lol.LookAtPoint(headingTo) end
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 1), { scale = 2.5 })
end
-- the demo hero's aim point: the nearest enemy ahead, else the enemy building, else down the lane
function Lol.AimEnemy(team)
	local c = Lol.Champ(team or 'blue')
	if not c or not alive(c.ped) then return L.c + L.dir * 20.0 end
	local p = GetEntityCoords(c.ped)
	local best
	for _, f in ipairs(Lol.foes(c.team, p, 40.0, true)) do
		local ahead = dot(f.pos - p, L.dir) * (c.team == 'blue' and 1 or -1)
		if ahead > -2.0 and (not best or f.d < best.d) then best = f end
	end
	if best then return best.pos end
	local st = targetStruct(c.team, p)
	return st and st.pos or (L.c + L.dir * 20.0)
end
function Lol.Mortalize()
	Lol.mortal = true
	local me = PlayerPedId()
	SetPlayerInvincible(PlayerId(), false)
	SetEntityInvincible(me, false)
	SetEntityProofs(me, false, false, false, false, false, false, false, false)
	SetPedCanRagdoll(me, true)
end
