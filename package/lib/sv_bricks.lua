-- SIGF bricks, server part. The stream runs one client: put the mod in client.lua; server.lua is only for what
-- must be on the server (other players on a real server, saved data). Sigf.Log/Every/After/Safe work here too.
Sigf = Sigf or {}

-- To all clients: Sigf.ToClients('my_event', data) <-> RegisterNetEvent('my_event', fn) in client.lua.
function Sigf.ToClients(event, ...) TriggerClientEvent(event, -1, ...) end
