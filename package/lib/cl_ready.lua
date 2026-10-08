-- Last client file of the mod resource: every file above it has run. Tells the stage (check.ps1 waits for SIGF_READY).
CreateThread(function()
	Wait(500)
	TriggerServerEvent('sigf:ready')
end)
