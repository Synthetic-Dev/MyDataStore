local Comm = require(script.Parent.Parent.Comm)
local Promise = require(script.Parent.Parent.Promise)
local Signal = require(script.Parent.Parent.Signal)

local MyDataStoreClient = { }

MyDataStoreClient.Data = nil
MyDataStoreClient._loaded = false

-- Signals
MyDataStoreClient.Update = Signal.new()
MyDataStoreClient.Loaded = Signal.new()

-- API
function MyDataStoreClient:Get(...)
	local drill = { ...; }
	return Promise.new(function(resolve, reject)
		self
			:OnLoad()
			:andThen(function()
				local scope = self.Data
				for _, key in pairs(drill) do
					scope = scope[key]
				end

				resolve(scope)
			end)
			:catch(reject)
	end)
end

function MyDataStoreClient:GetMultiple(...)
	local promises = { }
	for _, drill in pairs({ ...; }) do
		table.insert(promises, self:Get(table.unpack(drill)))
	end
	return Promise.all(promises)
end

function MyDataStoreClient:Set(...)
	local drill = { ...; }

	self
		:OnLoad()
		:andThen(function()
			local scope = self.Data
			local value = drill[#drill]
			table.remove(drill, #drill)

			local context
			for index, key in pairs(drill) do
				if index == #drill then
					scope[key] = value
					context = key
				else
					scope = scope[key]
				end
			end

			self.Update:Fire(context)
		end)
		:catch(warn)
end

function MyDataStoreClient:Increment(...)
	local drill = { ...; }

	self
		:OnLoad()
		:andThen(function()
			local scope = self.Data
			local value = drill[#drill]

			if type(value) == "number" then
				table.remove(drill, #drill)
			else
				value = 1
			end

			local context
			for index, key in pairs(drill) do
				if index == #drill then
					scope[key] = (scope[key] or 0) + value
					context = key
				else
					scope = scope[key]
				end
			end

			self.Update:Fire(context)
		end)
		:catch(warn)
end

function MyDataStoreClient:OnLoad(timeout)
	if self._loaded then
		return Promise.resolve()
	end

	return Promise.new(function(resolve, reject)
		task.delay(timeout or 60, function()
			if not self._loaded then
				if timeout then
					reject("Data didn't load within timeout")
				end

				warn("Possible infinite yield for data")
			end
		end)

		while not self._loaded do
			self.Loaded:Wait()
		end

		resolve()
	end)
end

function MyDataStoreClient:_init(data)
	self.Data = data
	self._loaded = true
	self.Loaded:Fire()

	warn("MyDataStore Client initiated with data:", data)
end

function MyDataStoreClient:Start()
	if not script.Parent:WaitForChild("remotes", 5) then
		error("MyDataStore Server was not started before client")
	end

	self._comm =
		Comm.ClientComm.new(script.Parent, true, "remotes"):BuildObject()

	self._comm.Delete:Connect(function(data)
		self.Data = data
		self.Update:Fire()
	end)

	self._comm.Set:Connect(function(...)
		self:Set(...)
	end)

	self._comm.Increment:Connect(function(...)
		self:Increment(...)
	end)

	self._comm
		:Init()
		:andThen(function(data)
			self:_init(data)
		end)
		:catch(function(err)
			warn("MyDataStore Client failed to init, ", err)
		end)
end

return MyDataStoreClient
