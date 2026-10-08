-- SIGF bricks, client part: tested building blocks for GTA V (FiveM, CfxLua 5.4). Copied into the mod as lib/.
-- Positions are vector3 (x east, y north, z up, metres). A player is 1.8 m tall. Headings in degrees.
-- Call them from timers, events or threads, never at load time (the world may not be there yet).
Sigf = Sigf or {}
local tracked = {}          -- ped -> true: peds whose deaths fire Sigf.OnKill (Sigf.Ped + the stage's fighters)
local owned = {}            -- entity -> expiry ms (0 = never): cleaned by the lifetime thread
local killFns, spawnFns = {}, {}

-- ---------- lookup ----------
function Sigf.Host() return PlayerPedId() end

local function stageCall(name)
	local ok, r = pcall(exports.sigf_stage[name])
	if ok then return r end
	return nil
end

-- Centre of the arena (stream stage) or the player's position (a player's own game).
function Sigf.Arena() return stageCall('arena') or GetEntityCoords(PlayerPedId()) end

-- Where the stream is looking now: the orbit camera's point outside the demo, the player in the demo.
function Sigf.Action() return stageCall('action') or GetEntityCoords(PlayerPedId()) end

-- Living peds (not the stream player); optional filter(ped) -> bool.
function Sigf.Peds(filter)
	local out, me = {}, PlayerPedId()
	for _, ped in ipairs(GetGamePool('CPed')) do
		if ped ~= me and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) and (not filter or filter(ped)) then out[#out + 1] = ped end
	end
	return out
end

-- The stage's battle fighters (living), and the side of a fighter ('a' or 'b', nil for others).
function Sigf.Fighters() return stageCall('fighters') or {} end

function Sigf.Near(pos, radius, filter)
	return Sigf.Peds(function(ped) return #(GetEntityCoords(ped) - pos) <= radius and (not filter or filter(ped)) end)
end

-- Ground point near center (random within `within` metres). Needs the world streamed there (near the camera).
function Sigf.Ground(center, within)
	center = center or Sigf.Action()
	for _ = 1, 12 do
		local a, r = math.random() * 6.2832, math.random() * (within or 0)
		local x, y = center.x + math.cos(a) * r, center.y + math.sin(a) * r
		local ok, z = GetGroundZFor_3dCoord(x, y, center.z + 50.0, false)
		if ok then return vector3(x, y, z) end
	end
	return center
end

-- Ground point `dist` metres in front of the player (demo) or of the camera's look point.
function Sigf.Front(dist)
	local me = PlayerPedId()
	local stage = Sigf.Stage()
	local p = GetOffsetFromEntityInWorldCoords(me, 0.0, dist or 5.0, 0.0)
	if stage ~= 'demo' and stage ~= '' then p = Sigf.Action() end
	return Sigf.Ground(p, 0)
end

-- ---------- spawning ----------
function Sigf.LoadModel(name)
	local h = Sigf.Hash(name)
	if not IsModelInCdimage(h) then Sigf.Log('SIGF_ERROR unknown model: ' .. tostring(name)) return nil end
	RequestModel(h)
	local t = GetGameTimer() + 8000
	while not HasModelLoaded(h) and GetGameTimer() < t do Wait(0) end
	if not HasModelLoaded(h) then Sigf.Log('SIGF_ERROR model did not load: ' .. tostring(name)) return nil end
	return h
end

local function own(ent, life)
	if ent and ent ~= 0 then owned[ent] = (life and life > 0) and (GetGameTimer() + math.floor(life * 1000)) or 0 end
	return ent
end

-- Ped. opts: weapon, health (hit points above death, 100 = a normal man), armor, life (s, 0 = forever),
-- enemy (true = fights the player and side A; false = fights with them; nil = not in the battle), heading,
-- accuracy (0-100), fight (true: attacks its enemies at once), outfit { [component] = { drawable, texture } }.
function Sigf.Ped(model, pos, opts)
	opts = opts or {}
	local h = Sigf.LoadModel(model)
	if not h then return nil end
	local ped = CreatePed(4, h, pos.x, pos.y, pos.z, (opts.heading or math.random(0, 359)) + 0.0, false, true)
	SetModelAsNoLongerNeeded(h)
	if opts.outfit then for comp, v in pairs(opts.outfit) do SetPedComponentVariation(ped, comp, v[1], v[2] or 0, 0) end end
	if opts.health then SetPedMaxHealth(ped, 100 + opts.health) SetEntityHealth(ped, 100 + opts.health) end
	if opts.armor then SetPedArmour(ped, opts.armor) end
	if opts.weapon then GiveWeaponToPed(ped, Sigf.Hash(opts.weapon), 999, false, true) end
	SetPedAccuracy(ped, opts.accuracy or 25)
	SetPedFleeAttributes(ped, 0, false)
	SetPedCombatAttributes(ped, 46, true)
	SetPedDropsWeaponsWhenDead(ped, false)
	if opts.enemy ~= nil then
		SetPedRelationshipGroupHash(ped, GetHashKey(opts.enemy and 'SIGF_B' or 'SIGF_A'))
	end
	if opts.fight ~= false and opts.enemy ~= nil then TaskCombatHatedTargetsAroundPed(ped, 100.0, 0) end
	tracked[ped] = true
	own(ped, opts.life)
	Sigf.Log('SIGF_SPAWN ' .. tostring(model))
	for _, fn in ipairs(spawnFns) do Sigf.Safe('OnSpawn', fn, ped) end
	return ped
end

-- Object (prop). opts: life, heading, frozen (default true), collision (default true), ground (snap to ground),
-- alpha (0-255), rot (vector3 degrees).
function Sigf.Prop(model, pos, opts)
	opts = opts or {}
	local h = Sigf.LoadModel(model)
	if not h then return nil end
	local obj = CreateObject(h, pos.x, pos.y, pos.z, false, false, false)
	SetModelAsNoLongerNeeded(h)
	if opts.rot then SetEntityRotation(obj, opts.rot.x, opts.rot.y, opts.rot.z, 2, true)
	else SetEntityHeading(obj, (opts.heading or 0.0) + 0.0) end
	if opts.ground then PlaceObjectOnGroundProperly(obj) end
	FreezeEntityPosition(obj, opts.frozen ~= false)
	if opts.collision == false then SetEntityCollision(obj, false, false) end
	if opts.alpha then SetEntityAlpha(obj, opts.alpha, false) end
	return own(obj, opts.life)
end

-- Vehicle. opts: life, color = { r, g, b }, color2, plate, driver (ped model: drives around), locked.
function Sigf.Vehicle(model, pos, heading, opts)
	opts = opts or {}
	local h = Sigf.LoadModel(model)
	if not h then return nil end
	local veh = CreateVehicle(h, pos.x, pos.y, pos.z, (heading or 0.0) + 0.0, false, false)
	SetModelAsNoLongerNeeded(h)
	SetVehicleOnGroundProperly(veh)
	if opts.color then SetVehicleCustomPrimaryColour(veh, opts.color[1], opts.color[2], opts.color[3]) end
	if opts.color2 then SetVehicleCustomSecondaryColour(veh, opts.color2[1], opts.color2[2], opts.color2[3]) end
	if opts.plate then SetVehicleNumberPlateText(veh, opts.plate) end
	if opts.driver then
		local d = Sigf.Ped(opts.driver, pos, { life = opts.life })
		if d then SetPedIntoVehicle(d, veh, -1) TaskVehicleDriveWander(d, veh, 25.0, 786603) end
	end
	return own(veh, opts.life)
end

function Sigf.Remove(ent)
	if type(ent) == 'number' and DoesEntityExist(ent) then
		SetEntityAsMissionEntity(ent, true, true)
		DeleteEntity(ent)
	end
	owned[ent] = nil
	tracked[ent] = nil
end

function Sigf.Teleport(ent, pos, heading)
	SetEntityCoords(ent, pos.x, pos.y, pos.z, false, false, false, false)
	if heading then SetEntityHeading(ent, heading + 0.0) end
end

-- Attach ent to another entity (bone = ped bone id such as 31086 head, 24818 spine, 57005 right hand; 0 = root).
function Sigf.Attach(ent, to, bone, offset, rot)
	offset, rot = offset or vector3(0, 0, 0), rot or vector3(0, 0, 0)
	local idx = (bone and bone ~= 0 and IsEntityAPed(to)) and GetPedBoneIndex(to, bone) or 0
	AttachEntityToEntity(ent, to, idx, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
end

-- Visual scale of an object (collision keeps its normal size). Frozen objects only.
function Sigf.ScaleProp(obj, s)
	local f, r, u, p = GetEntityMatrix(obj)
	SetEntityMatrix(obj, f.x * s, f.y * s, f.z * s, r.x * s, r.y * s, r.z * s, u.x * s, u.y * s, u.z * s, p.x, p.y, p.z)
end

-- ---------- events of the mod ----------
-- Sigf.OnKill(function(ped, killer, weaponHash) end): a tracked ped died (yours, and the stage's fighters).
function Sigf.OnKill(fn) killFns[#killFns + 1] = fn end
-- Sigf.OnSpawn(function(ped) end): any ped made by Sigf.Ped, and every battle fighter.
function Sigf.OnSpawn(fn) spawnFns[#spawnFns + 1] = fn end

AddEventHandler('sigf:battleSpawn', function(ped, side)
	tracked[ped] = true
	for _, fn in ipairs(spawnFns) do Sigf.Safe('OnSpawn', fn, ped, side) end
end)

-- The stage's battle: Sigf.Battle({ enabled = false }) to replace it with your own enemies, or change it:
-- { a = 6, b = 2, modelA = 'g_m_y_ballaorig_01', modelB = '...', weaponA = 'WEAPON_SMG', radius = 30.0 }.
function Sigf.Battle(opts) TriggerEvent('sigf:battle', opts) end

-- Point the stream's orbit camera at an entity or a position for `sec` seconds (not in the demo).
function Sigf.Focus(target, sec) TriggerEvent('sigf:focus', target, sec or 5) end

-- ---------- effects ----------
-- Explosion. kind: number (0 grenade, 2 molotov, 4 rocket, 7 car, 29 firework, 38 ray gun, 70 orbital cannon... see the
-- catalog explosionTypesCompact.json) or 0. opts: scale (damage, 1), owner (ped), quiet, invisible, shake (0-2).
function Sigf.Explode(pos, kind, opts)
	opts = opts or {}
	if opts.owner then
		AddOwnedExplosion(opts.owner, pos.x, pos.y, pos.z, kind or 0, opts.scale or 1.0, not opts.quiet, opts.invisible or false, opts.shake or 1.0)
	else
		AddExplosion(pos.x, pos.y, pos.z, kind or 0, opts.scale or 1.0, not opts.quiet, opts.invisible or false, opts.shake or 1.0)
	end
end

local function loadPtfx(asset)
	RequestNamedPtfxAsset(asset)
	local t = GetGameTimer() + 5000
	while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < t do Wait(0) end
	return HasNamedPtfxAssetLoaded(asset)
end

-- Particle effect from the game (catalog: particleEffectsCompact.json lists asset -> effect names).
-- at = vector3 or an entity. opts: scale, loop (keep it running; returns a handle), life (s, for loops),
-- color = { r, g, b } (0-1, loops only), offset (vector3, on entities), rot (vector3).
function Sigf.Fx(asset, effect, at, opts)
	opts = opts or {}
	if not loadPtfx(asset) then Sigf.Log('SIGF_ERROR particle asset did not load: ' .. asset) return nil end
	local s, rot, off = opts.scale or 1.0, opts.rot or vector3(0, 0, 0), opts.offset or vector3(0, 0, 0)
	UseParticleFxAsset(asset)
	local isEnt = type(at) == 'number'
	if not opts.loop then
		if isEnt then
			StartParticleFxNonLoopedOnEntity(effect, at, off.x, off.y, off.z, rot.x, rot.y, rot.z, s, false, false, false)
		else
			StartParticleFxNonLoopedAtCoord(effect, at.x, at.y, at.z, rot.x, rot.y, rot.z, s, false, false, false)
		end
		return nil
	end
	local h
	if isEnt then h = StartParticleFxLoopedOnEntity(effect, at, off.x, off.y, off.z, rot.x, rot.y, rot.z, s, false, false, false)
	else h = StartParticleFxLoopedAtCoord(effect, at.x, at.y, at.z, rot.x, rot.y, rot.z, s, false, false, false, false) end
	if opts.color then SetParticleFxLoopedColour(h, opts.color[1], opts.color[2], opts.color[3], false) end
	if opts.life and opts.life > 0 then SetTimeout(math.floor(opts.life * 1000), function() StopParticleFxLooped(h, false) end) end
	return h
end

function Sigf.StopFx(h) if h then StopParticleFxLooped(h, false) end end

-- Ready-made effects (asset, effect), all base game. Sigf.Fx(Sigf.FX.smoke[1], Sigf.FX.smoke[2], pos).
Sigf.FX = {
	poof      = { 'scr_rcbarry2', 'scr_clown_appears' },             -- colourful smoke burst (appear / vanish)
	firework  = { 'scr_indep_fireworks', 'scr_indep_firework_starburst' },
	sparks    = { 'core', 'ent_brk_sparking_wires' },
	fire      = { 'core', 'ent_sht_flame' },                         -- loop
	smoke     = { 'core', 'exp_grd_bzgas_smoke' },
	blood     = { 'core', 'blood_stab' },
	electric  = { 'core', 'ent_dst_elec_fire_sp' },
	money     = { 'scr_paletoscore', 'scr_paleto_banknotes' },
	flare     = { 'core', 'exp_grd_flare' },
}

-- Draws every frame at a position or on an entity (+ offset) for `life` seconds (0 = until Sigf.Stop(returned name));
-- stops by itself when the entity is gone. draw(p, now) does the drawing.
local function timed(at, life, off, draw)
	local until_ = (life and life > 0) and (GetGameTimer() + life * 1000) or nil
	return Sigf.Frame(function()
		local now = GetGameTimer()
		if until_ and now > until_ then return false end
		local p
		if type(at) == 'number' then
			if not DoesEntityExist(at) then return false end
			p = GetEntityCoords(at)
		else p = at end
		if off then p = p + off end
		draw(p, now)
	end)
end

-- Light for `life` seconds (0 = until Sigf.Stop(returned name)). at = vector3 or entity. color = { r, g, b } 0-255.
function Sigf.Light(at, color, range, intensity, life)
	return timed(at, life, nil, function(p)
		DrawLightWithRange(p.x, p.y, p.z, color[1], color[2], color[3], range or 6.0, intensity or 3.0)
	end)
end

-- Game marker drawn each frame (type 1 cylinder, 2 arrow, 28 sphere...). color = { r, g, b, a }.
function Sigf.Marker(kind, at, scale, color, life, opts)
	opts = opts or {}
	return timed(at, life, nil, function(p)
		DrawMarker(kind, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, scale.x, scale.y, scale.z,
			color[1], color[2], color[3], color[4] or 160, opts.bob or false, opts.face or false, 2, opts.spin or false, nil, nil, false)
	end)
end

-- Camera shake (works with the stream's orbit camera and with the demo camera). kind: SMALL_EXPLOSION_SHAKE,
-- MEDIUM_EXPLOSION_SHAKE, LARGE_EXPLOSION_SHAKE, JOLT_SHAKE, DRUNK_SHAKE (catalog: camShakeTypesCompact.json).
function Sigf.Shake(amp, kind)
	kind = kind or 'MEDIUM_EXPLOSION_SHAKE'
	local c = GetRenderingCam()
	if c and c ~= -1 then ShakeCam(c, kind, amp or 0.5) else ShakeGameplayCam(kind, amp or 0.5) end
end

-- Slow motion: scale 0.2 to 1 for sec real seconds.
function Sigf.Slowmo(scale, sec)
	SetTimeScale(scale)
	CreateThread(function()
		local t = GetGameTimer() + math.floor((sec or 2) * 1000)   -- real time, not slowed down
		while GetGameTimer() < t do Wait(0) end
		SetTimeScale(1.0)
	end)
end

-- Full-screen game filter (catalog: animPostFxNamesCompact.json), e.g. 'DrugsMichaelAliensFight', 'Rampage', 'FocusIn'.
function Sigf.PostFx(name, sec)
	AnimpostfxPlay(name, 0, true)
	SetTimeout(math.floor((sec or 3) * 1000), function() AnimpostfxStop(name) end)
end

-- ---------- generated images ----------
-- mod/img/<name>.png (from image.py) -> a runtime texture: returns the dictionary and name for any native that
-- takes a texture (DrawSprite, DrawMarker), and Sigf.Sprite uses it.
local txd, loaded = nil, {}
function Sigf.Image(name)
	if not txd then txd = CreateRuntimeTxd('sigf_img') end
	if not loaded[name] then
		CreateRuntimeTextureFromImage(txd, name, 'img/' .. name .. '.png')
		loaded[name] = true
	end
	return 'sigf_img', name
end

-- The rendering camera this frame (position, fov, screen aspect), computed once per frame for all sprites.
local view, viewAt = {}, -1
function Sigf.View()
	local f = GetFrameCount()
	if f ~= viewAt then
		viewAt = f
		local rw, rh = GetActualScreenResolution()
		view.cam = GetFinalRenderedCamCoord()
		view.tanHalfFov = math.tan(math.rad(GetFinalRenderedCamFov()) / 2.0)
		view.aspectInv = rh / rw
	end
	return view
end

-- Image floating in the world, always facing the camera, size in metres (height). at = vector3 or entity
-- (follows it, above its head with opts.offset = vector3(0, 0, 1.2)). life in seconds (0 = until Sigf.Stop(id)).
-- opts: frames = { 'imp_walk1', 'imp_walk2' } + fps (animation), color = { r, g, b, a }, flip (mirror), ground (bottom on at).
-- Returns an id for Sigf.Stop(id). Drawn on top of the world (no walls in front): keep sprites on what they mark.
function Sigf.Sprite(img, at, size, life, opts)
	opts = opts or {}
	local frames = opts.frames or { img }
	for _, f in ipairs(frames) do Sigf.Image(f) end
	local col = opts.color or { 255, 255, 255, 255 }
	local off = (opts.offset or vector3(0, 0, 0)) + (opts.ground and vector3(0, 0, size / 2) or vector3(0, 0, 0))
	return timed(at, life, off, function(p, now)
		local v = Sigf.View()
		local dist = #(p - v.cam)
		if dist < 0.5 then return end
		local on, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
		if not on then return end
		local h = size / (2.0 * dist * v.tanHalfFov)
		local w = h * v.aspectInv
		local frame = frames[(math.floor(now / 1000 * (opts.fps or 8)) % #frames) + 1]
		DrawSprite('sigf_img', frame, sx, sy, opts.flip and -w or w, h, 0.0, col[1], col[2], col[3], col[4] or 255)
	end)
end

-- ---------- NUI overlay (lib/nui/hud.html): text, images, sounds ----------
-- Big caption, `sec` seconds. opts: y (0 top - 1 bottom, 0.2), size (px, 64), color ('#ffcc00'), font ('title'|'body').
function Sigf.Text(text, sec, opts)
	opts = opts or {}
	SendNUIMessage({ t = 'text', text = tostring(text), sec = sec or 3, y = opts.y, size = opts.size, color = opts.color, font = opts.font })
end

-- Full-screen image from mod/img (fades out). opts: opacity (0.85), fade (s).
function Sigf.Overlay(img, sec, opts)
	opts = opts or {}
	SendNUIMessage({ t = 'overlay', src = 'img/' .. img .. '.png', sec = sec or 1.5, opacity = opts.opacity, fade = opts.fade })
end

-- Sound from mod/sfx/<name>.ogg (sounds.ps1). pos (optional): quieter with distance from the camera (opts.range, 40 m).
-- opts: volume (0-1), loop (returns an id for Sigf.StopSound), rate (pitch).
local soundId = 0
function Sigf.Sound(name, pos, opts)
	opts = opts or {}
	local vol = opts.volume or 1.0
	if pos then
		local d = #(pos - GetFinalRenderedCamCoord())
		vol = vol * math.max(0.0, 1.0 - d / (opts.range or 40.0))
		if vol <= 0.02 then return nil end
	end
	soundId = soundId + 1
	SendNUIMessage({ t = 'sound', id = soundId, src = 'sfx/' .. name .. '.ogg', volume = vol, loop = opts.loop, rate = opts.rate })
	return soundId
end

function Sigf.StopSound(id) SendNUIMessage({ t = 'stopsound', id = id }) end

-- Music track (one at a time): Sigf.Music('theme', { volume = 0.5 }); Sigf.Music(nil) stops it.
function Sigf.Music(name, opts)
	opts = opts or {}
	SendNUIMessage({ t = 'music', src = name and ('sfx/' .. name .. '.ogg') or nil, volume = opts.volume or 0.5 })
end

-- Built-in game sound (catalog: soundNames.json gives name + set). pos = nil: heard everywhere.
function Sigf.GameSound(name, set, pos)
	if pos then PlaySoundFromCoord(-1, name, pos.x, pos.y, pos.z, set, false, 60, false)
	else PlaySoundFrontend(-1, name, set, true) end
end

-- Your own NUI code: mod/html/mod.js and mod/html/mod.css are loaded by the overlay page.
-- Sigf.Nui({ anything }) -> in mod.js: window.addEventListener('sigfmod', e => e.detail ...).
function Sigf.Nui(data) SendNUIMessage({ t = 'mod', data = data }) end

-- Text floating in the world for `sec` seconds (damage numbers, names). opts: color { r, g, b }, scale (0.5), rise (m/s).
function Sigf.Text3D(text, pos, sec, opts)
	opts = opts or {}
	local t0, life = GetGameTimer(), (sec or 2) * 1000
	local c = opts.color or { 255, 255, 255 }
	return Sigf.Frame(function()
		local age = GetGameTimer() - t0
		if age > life then return false end
		local p = pos + vector3(0, 0, (opts.rise or 0.6) * age / 1000)
		SetDrawOrigin(p.x, p.y, p.z, 0)
		SetTextFont(4)
		SetTextScale(0.0, opts.scale or 0.5)
		SetTextColour(c[1], c[2], c[3], math.floor(255 * (1 - age / life)))
		SetTextOutline()
		SetTextCentre(true)
		BeginTextCommandDisplayText('STRING')
		AddTextComponentSubstringPlayerName(text)
		EndTextCommandDisplayText(0.0, 0.0)
		ClearDrawOrigin()
	end)
end

-- ---------- internal threads ----------
-- Deaths of tracked peds -> Sigf.OnKill; owned entities removed when their life ends.
CreateThread(function()
	while true do
		Wait(200)
		for ped in pairs(tracked) do
			if not DoesEntityExist(ped) then tracked[ped] = nil
			elseif IsPedDeadOrDying(ped, true) then
				tracked[ped] = nil
				local killer = Sigf._killer and Sigf._killer[ped] or GetPedSourceOfDeath(ped)
				local weapon = GetPedCauseOfDeath(ped)
				Sigf.Log('SIGF_KILL ' .. tostring(GetEntityModel(ped)))
				for _, fn in ipairs(killFns) do Sigf.Safe('OnKill', fn, ped, killer, weapon) end
			end
		end
		local now = GetGameTimer()
		for ent, t in pairs(owned) do
			if not DoesEntityExist(ent) then owned[ent] = nil
			elseif t > 0 and now > t then Sigf.Remove(ent) end
		end
	end
end)

-- The mod's entities go away with it (hot reload: the next version starts from a clean arena). The rest of the
-- world (battle, time scale, filters, cameras) is reset by the stage (cl_stage.lua onClientResourceStop).
AddEventHandler('onResourceStop', function(res)
	if res ~= GetCurrentResourceName() then return end
	for ent in pairs(owned) do if DoesEntityExist(ent) then DeleteEntity(ent) end end
end)
