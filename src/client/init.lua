local Knit = require(script.Parent.Parent.Knit)
local Promise = require(script.Parent.Parent.Promise)
local Signal = require(script.Parent.Parent.Signal)

local DataStore
local ClientStore = Knit.CreateController({ Name = "ClientStore"; })

ClientStore.Data = nil
ClientStore.Loaded = false

-- Events
ClientStore.Update = Signal.new()

-- API
function ClientStore:Get(...)
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

function ClientStore:GetMultiple(...)
	local promises = { }
	for _, drill in pairs({ ...; }) do
		table.insert(promises, self:Get(table.unpack(drill)))
	end
	return Promise.all(promises)
end

function ClientStore:Set(...)
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

function ClientStore:Increment(...)
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

function ClientStore:OnLoad(timeout)
	return Promise.new(function(resolve, reject)
		local start = os.clock()
		local yieldSent = false
		while not self.Loaded do
			if os.clock() - start > (timeout or 60) then
				if timeout then
					reject("Data didn't load within timeout")
				end

				if not yieldSent then
					warn("Possible infinite yield for data")
					yieldSent = true
				end
			end

			task.wait()
		end

		resolve()
	end)
end

function ClientStore:Init(data)
	self.Data = data
	self.Loaded = true
	warn("ClientStore initiated with data:", data)
end

function ClientStore:KnitInit()
	DataStore = Knit.GetService("DataStore")

	DataStore.Delete:Connect(function(data)
		self.Data = data
		self.Update:Fire()
	end)

	DataStore.Set:Connect(function(...)
		self:Set(...)
	end)

	DataStore.Increment:Connect(function(...)
		self:Increment(...)
	end)
end

function ClientStore:KnitStart()
	DataStore:Init():andThen(function(data)
		self:Init(data)
	end)
end

return ClientStore
