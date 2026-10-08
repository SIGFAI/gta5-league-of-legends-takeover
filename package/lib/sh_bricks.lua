-- SIGF bricks, shared part (client and server). Copied by the kit into the mod resource as lib/: do not edit in a mod.
-- Nothing here runs game code at load time: only definitions.
Sigf = Sigf or {}
Sigf.IsServer = IsDuplicityVersion()

-- Stream stage: 'idle' | 'mod' | 'demo' on the stream, '' on a player's own server (the stage bits stay off).
function Sigf.Stage() return GetConvar('sigf_stage', '') end

function Sigf.Log(line)
	line = tostring(line)
	print(line)
	if not Sigf.IsServer then TriggerServerEvent('sigf:log', line) end
end

-- Runs fn; an error is reported (SIGF_ERROR, fails the check) instead of breaking the caller. Same message once.
local reported = {}
function Sigf.Safe(where, fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		local msg = tostring(err)
		if not reported[where .. msg] then
			reported[where .. msg] = true
			Sigf.Log('SIGF_ERROR ' .. GetCurrentResourceName() .. ' ' .. where .. ': ' .. msg)
		end
		return nil
	end
	return err
end

-- Timers. Every/After/Frame return a name for Sigf.Stop(name). Errors inside are reported, the timer keeps going.
-- Starting a timer with the name of a running one replaces it (Fn.Hud(true) twice = one HUD loop).
local timers, nextId = {}, 0
local function start(name, prefix)
	nextId = nextId + 1
	name = name or (prefix .. nextId)
	local token = {}
	timers[name] = token
	return name, function() return timers[name] == token end, function() if timers[name] == token then timers[name] = nil end end
end

function Sigf.Every(sec, fn, name)
	local alive
	name, alive = start(name, 'every')
	CreateThread(function()
		while alive() do
			Wait(math.max(0, math.floor(sec * 1000)))
			if not alive() then break end
			Sigf.Safe('Every ' .. name, fn)
		end
	end)
	return name
end

function Sigf.After(sec, fn, name)
	local alive, done
	name, alive, done = start(name, 'after')
	SetTimeout(math.max(0, math.floor(sec * 1000)), function()
		if alive() then
			done()
			Sigf.Safe('After ' .. name, fn)
		end
	end)
	return name
end

function Sigf.Stop(name) if name then timers[name] = nil end end

-- Every frame (client) until it returns false or is stopped: Sigf.Frame(function(dt) ... end).
-- All of them run in one shared thread (lights, markers, sprites, fades: dozens at once cost one coroutine).
local frames, pending, frameThread = {}, {}, false
function Sigf.Frame(fn, name)
	local alive, done
	name, alive, done = start(name, 'frame')
	pending[#pending + 1] = { fn = fn, alive = alive, done = done, where = 'Frame ' .. name }
	if not frameThread then
		frameThread = true
		CreateThread(function()
			local last = GetGameTimer()
			while true do
				Wait(0)
				local now = GetGameTimer()
				local dt = (now - last) / 1000.0
				last = now
				for i = 1, #pending do frames[#frames + 1] = pending[i] end   -- added during the last frame
				pending = {}
				local keep = {}
				for _, f in ipairs(frames) do
					if f.alive() then
						if Sigf.Safe(f.where, f.fn, dt) == false then f.done() else keep[#keep + 1] = f end
					end
				end
				frames = keep
			end
		end)
	end
	return name
end

function Sigf.Rand(a, b) return a + math.random() * (b - a) end
function Sigf.Pick(t) return t[math.random(1, #t)] end
function Sigf.Hash(name) return type(name) == 'number' and name or GetHashKey(name) end
