if game:GetService("RunService"):IsServer() then
	return require(script.server)
else
	local server = script:FindFirstChild("server")
	if server then
		server:Destroy()
	end
	return require(script.client)
end
