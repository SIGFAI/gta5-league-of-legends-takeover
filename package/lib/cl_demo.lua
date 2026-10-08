-- SIGF demo helpers (client): demo.lua plays the mod for the recorded clip. Inert outside the stream's demo stage.
Sigf = Sigf or {}
local steps, started = {}, false

-- Sigf.Demo(sec, fn): fn runs `sec` seconds after the recording starts.
function Sigf.Demo(sec, fn) steps[#steps + 1] = { sec = sec, fn = fn } end

local function start()
	if started or Sigf.Stage() ~= 'demo' then return end
	started = true
	Sigf.Log('SIGF_DEMO_STEPS ' .. #steps)
	for i, s in ipairs(steps) do Sigf.After(s.sec, s.fn, 'demo' .. i) end
end

RegisterNetEvent('sigf:rec', start)
CreateThread(function()
	Wait(1000)
	TriggerServerEvent('sigf:hello')   -- the recording may have started before this version loaded
end)

-- Autopilot (the stage's): walks to the nearest enemy and shoots. Off while you stage a moment, then back on.
function Sigf.Pilot(on) TriggerEvent('sigf:pilot', on) end

-- Gives the player a weapon and holds it. tint: 0 normal, 1 green, 2 gold, 3 pink, 4 army, 5 police blue, 6 orange, 7 platinum.
function Sigf.Give(weapon, tint)
	local me, h = PlayerPedId(), Sigf.Hash(weapon)
	GiveWeaponToPed(me, h, 9999, false, true)
	SetPedInfiniteAmmo(me, true, h)
	SetCurrentPedWeapon(me, h, true)
	if tint then SetPedWeaponTintIndex(me, h, tint) end
end

-- An enemy appears `dist` metres in front of the player (model and opts as Sigf.Ped).
function Sigf.BringPed(dist, model, opts)
	opts = opts or {}
	if opts.enemy == nil then opts.enemy = true end
	local p = Sigf.Front(dist or 10.0)
	local me = GetEntityCoords(PlayerPedId())
	opts.heading = opts.heading or GetHeadingFromVector_2d(me.x - p.x, me.y - p.y)
	return Sigf.Ped(model or 'g_m_y_famca_01', p + vector3(0, 0, 0.5), opts)
end

-- Turn to face an entity or a position (the camera follows: it stays behind the player).
function Sigf.LookAt(target, sec)
	local me = PlayerPedId()
	local ms = math.floor((sec or 1) * 1000)
	if type(target) == 'number' then TaskTurnPedToFaceEntity(me, target, ms)
	else TaskTurnPedToFaceCoord(me, target.x, target.y, target.z, ms) end
end

-- Shoot for `sec` seconds at an entity or a position (default: straight ahead).
function Sigf.Shoot(sec, target)
	local me = PlayerPedId()
	local ms = math.floor((sec or 1) * 1000)
	target = target or GetOffsetFromEntityInWorldCoords(me, 0.0, 15.0, 0.5)
	if type(target) == 'number' then TaskShootAtEntity(me, target, ms, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
	else TaskShootAtCoord(me, target.x, target.y, target.z, ms, GetHashKey('FIRING_PATTERN_FULL_AUTO')) end
end

-- Walk (or run, speed 2-3) straight ahead for `sec` seconds; negative speed walks back.
function Sigf.Walk(sec, speed)
	local me = PlayerPedId()
	speed = speed or 1.0
	local dist = math.abs(speed) * 1.5 * (sec or 1)
	local p = GetOffsetFromEntityInWorldCoords(me, 0.0, speed >= 0 and dist or -dist, 0.0)
	TaskGoStraightToCoord(me, p.x, p.y, p.z, math.abs(speed), math.floor((sec or 1) * 1000), GetEntityHeading(me), 0.5)
end

function Sigf.Jump() TaskJump(PlayerPedId(), false) end

-- The player kills a ped (credited to the player in Sigf.OnKill).
Sigf._killer = Sigf._killer or {}
function Sigf.KillByHost(ped)
	if not DoesEntityExist(ped) then return end
	Sigf._killer[ped] = PlayerPedId()
	SetEntityHealth(ped, 0)
end

-- Drive: the player gets into a vehicle and drives to a point (or wanders).
function Sigf.Drive(veh, to, speed)
	local me = PlayerPedId()
	TaskWarpPedIntoVehicle(me, veh, -1)
	if to then TaskVehicleDriveToCoord(me, veh, to.x, to.y, to.z, speed or 25.0, 0, GetEntityModel(veh), 786603, 4.0, true)
	else TaskVehicleDriveWander(me, veh, speed or 25.0, 786603) end
end

-- Scripted camera for `sec` seconds: from `from`, looking at an entity or a position, then back behind the player.
function Sigf.Cinematic(from, target, sec, fov)
	local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
	SetCamCoord(cam, from.x, from.y, from.z)
	SetCamFov(cam, fov or 50.0)
	if type(target) == 'number' then PointCamAtEntity(cam, target, 0.0, 0.0, 0.5, true)
	else PointCamAtCoord(cam, target.x, target.y, target.z) end
	RenderScriptCams(true, true, 600, true, true)
	SetTimeout(math.floor((sec or 3) * 1000), function()
		RenderScriptCams(false, true, 600, true, true)
		DestroyCam(cam, false)
	end)
end

-- Play an animation (catalog: animDictsCompact.json). flag 1 = loop, 48 = upper body only, 0 = once.
function Sigf.Anim(ped, dict, clip, sec, flag)
	RequestAnimDict(dict)
	local t = GetGameTimer() + 3000
	while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
	if not HasAnimDictLoaded(dict) then Sigf.Log('SIGF_ERROR animation did not load: ' .. dict) return end
	TaskPlayAnim(ped, dict, clip, 4.0, -4.0, sec and math.floor(sec * 1000) or -1, flag or 0, 0.0, false, false, false)
end
