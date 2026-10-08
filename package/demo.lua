-- Demo: League of Legends takes over Los Santos. The player is the champion Aurelia; the match starts with the recording (client.lua).
local function hero() return Lol.Champ('blue') end
local function cap(text, sec) Sigf.Text(text, sec or 4, { y = 0.27, size = 50, color = '#ffe08a' }) end
local function at(u, v) return Lol.At(u, v) end
local function up(p, z) return p + vector3(0, 0, z) end
local function redTurret(tier) return Lol.Struct('turret', 'red', 'mid', tier) end
local function look(p) if p then Lol.LookAtPoint(p) end end
local function cast(k, aim) local h = hero() if h then Lol.Force(h, k, aim) end end
local function shot(from, to, sec, fov) Sigf.Cinematic(from, to, sec, fov or 58.0) end
local function ahead(d) return GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, d, 0.0) end

Sigf.Demo(0.3, function() Sigf.Pilot(false) end)

-- 1. Poro rain and hatted minions
Sigf.Demo(0.4, function() shot(up(at(-48, 3), 2.6), up(at(-30, 0), 7.5), 4.4, 74.0) end)
Sigf.Demo(0.8, function() cap('LEAGUE OF LEGENDS TAKES OVER LOS SANTOS', 3.0) end)
Sigf.Demo(3.4, function() cap('PORO RAIN: the Rift mascots fall from the sky', 2.4) end)
Sigf.Demo(5.6, function()
	cap('Minions wear silly hats and fight in lanes', 3.0)
	local best
	for _, f in ipairs(Lol.foes('blue', at(-8, 0), 45.0, true)) do
		if not best or f.d < best.d then best = f end
	end
	if best then shot(best.pos + vector3(3.6, -3.2, 1.5), best.pos + vector3(0, 0, 1.5), 3.4, 42.0)
	else shot(up(at(-30, -10), 5.0), up(at(-14, 0), 1.5), 3.4, 60.0) end
end)

-- 2. Shoot the Poro King with the carbine
Sigf.Demo(9.4, function()
	Sigf.Pilot(false)
	local k = Lol.PoroKing()
	if not k then return end
	local away = at(-16, 4) - k.pos
	away = away / #away
	Lol.Warp(k.pos + away * 9.0, k.pos)
	cap('Shoot the PORO KING: every bullet pops him', 3.4)
end)
Sigf.Demo(10.6, function()
	local k = Lol.PoroKing()
	if k then look(k.pos) Sigf.Shoot(7, k.pos + vector3(0, 0, 2.0)) end
end)
Sigf.Demo(12.0, function()
	local k = Lol.PoroKing()
	if not k then return end
	local me = GetEntityCoords(PlayerPedId())
	local away = me - k.pos
	away = away / #away
	shot(me + Lol.L.side * 3.8 + away * 2.5 + vector3(0, 0, 1.7), k.pos + vector3(0, 0, 2.8), 4.8, 58.0)
end)
-- if some bullets miss, the carbine still lands on cue (the same call the gunfire makes)
for i = 0, 11 do
	Sigf.Demo(14.2 + i * 0.3, function()
		local k = Lol.PoroKing()
		if k and Lol.poroHit then Lol.poroHit(k.pos + vector3(0, 0, 2.0), 0.3, PlayerPedId()) end
	end)
end

-- 3. Eight champions, each with their own spells: the hero borrows each kit in turn, in the open desert south of the lanes
local function stagePos() return at(-30, -74) end
Sigf.Demo(17.4, function() cap('8 CHAMPIONS, 32 SPELLS', 2.4) end)

local function beat(t, id, caption, casts)
	Sigf.Demo(t, function()
		local h = hero()
		if not h then return end
		Lol.SetKit(h, id)
		cap(caption, 3.2)
		Lol.Warp(stagePos(), stagePos() + Lol.L.dir * 30.0)
		Sigf.After(0.3, function()
			local base, side = ahead(12), Lol.L.side
			for i = 1, 4 do Lol.Dummy('red', base + side * ((i - 2.5) * 2.4) + Lol.L.dir * (i % 2) * 2.0) end
			shot(GetOffsetFromEntityInWorldCoords(PlayerPedId(), 5.5, -2.5, 1.7), up(ahead(9.0), 1.1), 3.6, 56.0)
		end)
	end)
	for _, c in ipairs(casts) do
		Sigf.Demo(t + c[1], function() Lol.Force(hero(), c[2], ahead(10)) end)
	end
end
beat(19.8, 'cinder', 'CINDER: a cone of real fire, then a fireball', { { 1.4, 'q' }, { 2.8, 'e' } })
beat(23.4, 'voltaire', 'VOLTAIRE: chain lightning and a tempest', { { 1.3, 'q' }, { 2.4, 'r' } })
beat(27.0, 'vesper', 'VESPER: a hawkshot that stuns the line', { { 1.3, 'r' }, { 2.6, 'e' } })
beat(30.6, 'shade', 'SHADE: blink strike and death lotus', { { 1.3, 'e' }, { 2.4, 'r' } })

-- 4. The Rift Drake: a team-wide soul
Sigf.Demo(34.6, function()
	Sigf.Pilot(false)
	local h = hero()
	Lol.SetKit(h, 'aurelia')
	local d = Lol.Drake()
	Lol.Warp(at(-6, -0.62 * 40.0 + 15.0), d and d.pos or at(0, -25))
	cap('Slay the RIFT DRAKE for a team-wide soul', 3.2)
end)
Sigf.Demo(35.4, function()
	local d = Lol.Drake()
	if d then look(d.pos) Sigf.Shoot(8, d.pos + vector3(0, 0, 3.0)) cast('q', d.pos) end
end)
Sigf.Demo(37.0, function() local d = Lol.Drake() if d then cast('r', d.pos) shot(d.pos + vector3(-17, 11, 7.0), d.pos + vector3(0, 0, 3.0), 4.5, 60.0) end end)
Sigf.Demo(39.8, function() local d = Lol.Drake() if d then cast('q', d.pos) end end)
Sigf.Demo(43.4, function() local d = Lol.Drake() if d and d.alive then Lol.hurtDrake(99999, { 255, 255, 255 }, PlayerPedId()) end end)

-- 5. Take the turrets and the nexus
Sigf.Demo(48.4, function()
	Sigf.Pilot(false)
	local t = redTurret(1)
	Lol.Warp(Lol.LaneAt('mid', 0.55, 0), t and t.pos)
	cap('Break the enemy turret', 2.8)
end)
Sigf.Demo(49.2, function() local t = redTurret(1) if t then look(t.pos) Sigf.Shoot(5, t.pos + vector3(0, 0, 3.0)) cast('q', t.pos) end end)
Sigf.Demo(51.2, function() local t = redTurret(1) if t then cast('r', t.pos) end end)
Sigf.Demo(53.6, function() local t = redTurret(1) if t and t.alive then Lol.HurtStruct(t, 9999) end end)
Sigf.Demo(55.2, function()
	local t = redTurret(2)
	Lol.Warp(Lol.LaneAt('mid', 0.70, 0), t and t.pos)
	cap('Now the inner turret', 2.4)
end)
Sigf.Demo(56.0, function() local t = redTurret(2) if t then look(t.pos) Sigf.Shoot(4, t.pos + vector3(0, 0, 3.0)) cast('q', t.pos) end end)
Sigf.Demo(58.4, function() local t = redTurret(2) if t and t.alive then Lol.HurtStruct(t, 9999) end end)
Sigf.Demo(59.6, function()
	local n = Lol.Struct('nexus', 'red')
	Lol.Warp(Lol.LaneAt('mid', 0.88, 0), n and n.pos)
	cap('Destroy the Nexus to win!', 3.0)
end)
Sigf.Demo(60.6, function() local n = Lol.Struct('nexus', 'red') if n then look(n.pos) Sigf.Shoot(6, n.pos + vector3(0, 0, 3.0)) cast('q', n.pos) end end)
Sigf.Demo(62.4, function() local n = Lol.Struct('nexus', 'red') if n then cast('r', n.pos) end end)
Sigf.Demo(65.0, function() local n = Lol.Struct('nexus', 'red') if n and n.alive then Lol.HurtStruct(n, 99999) end end)
Sigf.Demo(72.0, function() Sigf.Pilot(true) end)
