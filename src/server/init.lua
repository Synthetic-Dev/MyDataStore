--Services
local DataStoreService = game:GetService("DataStoreService")

local RunService = game:GetService("RunService")
local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:FindFirstChild("Packages")
if not Packages then
	error("Wally Packages not in ReplicatedStorage")
end

local KnitInstance = Packages:FindFirstChild("Knit")
if not KnitInstance then
	error("MyDataStore requires Knit! Knit could not be found.")
end

local Knit = require(KnitInstance)

local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)

--Components
local util = script.Util

--Modules
local TableUtil = require(util.TableUtil)
local MockDataStoreService = require(util.MockDataStoreService)

local DefaultData = require(script.DefaultData)
local DefaultInfo = require(script.DefaultInfo)
local Globals = require(script.Globals)

--Data
local DataStore = Knit.CreateService({
	Name = "DataStore";
	Client = {
		Set = Knit.CreateSignal();
		Increment = Knit.CreateSignal();
		Delete = Knit.CreateSignal();
	};
})

--Signals
DataStore.SaveLeaderboard = Signal.new()
DataStore.Saved = Signal.new()

--Globals
DataStore.Session = { }
DataStore.Stamps = { }
DataStore.Globals = Globals

--Initialize Datastore
local IsStudio = RunService:IsStudio()

if game.GameId == 0 then
	DataStore.IsUsingMockService = true
elseif IsStudio then
	-- Verify status of the DataStoreService on startup:
	local success, err = pcall(function()
		DataStoreService
			:GetDataStore("__data")
			:UpdateAsync("dss_api_check", function(v)
				return v == nil and true or v
			end)
	end)

	if not success then
		-- Error codes: https://developer.roblox.com/articles/Datastore-Errors
		local errCode = tonumber(err:match("^%d+"))
		if errCode == 502 or errCode == 403 then
			DataStore.IsUsingMockService = true
		elseif errCode == 304 then
			error(
				"DataStoreService API check failed on UpdateAsync (request queue full)"
			)
		else
			error(
				"DataStoreService API error " .. errCode
					or "[Unknown Status]" .. ": " .. err
			)
		end
	end
end

if DataStore.IsUsingMockService then
	warn("Warning: Data will not be saved. Please publish place.")

	DataStoreService = MockDataStoreService
elseif IsStudio and not Globals.SAVE_IN_STUDIO then
	warn(
		"Warning: Data will not be saved. Please enable the SAVE_IN_STUDIO flag."
	)
end

local Store = DataStoreService:GetDataStore(
	Globals.TITLE .. "_" .. Globals.VERSION
)

--Functions
local function dwarn(...)
	if IsStudio and Globals.DEBUG then
		warn(...)
	end
end

local function GetRandomKey(length)
	length = length or 10

	local chars =
		"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQReplicatedStorageTUVWXYZ0123456789"
	local randomString = ""

	local rand = Random.new()

	local charTable = { }
	for c in string.gmatch(chars, ".") do
		table.insert(charTable, c)
	end

	for _ = 1, length do
		randomString = randomString
			.. charTable[rand:NextInteger(1, #charTable)]
	end

	return randomString
end

local function GetDefaultData(player, isFirst)
	local default = TableUtil.Copy(DefaultData)

	local function Prepare(t)
		for key, value in pairs(t) do
			if typeof(value) == "function" then
				t[key] = value(player, isFirst)
			elseif typeof(value) == "table" then
				Prepare(value)
			end
		end
	end

	Prepare(default)
	return default
end

local function NewPlayer(_player, data)
	data._info = TableUtil.Copy(DefaultInfo)

	return data
end

local function KickPlayer(player, message)
	message = message or ""

	if Globals.CAN_KICK then
		player:Kick(message)
	else
		warn("Tried to kick " .. player.Name .. " - " .. message)
	end
end

local function Populate(player, data)
	local default = GetDefaultData(player, false)

	local function AssignTo(set, assign)
		if assign then
			for key, value in pairs(set) do
				if type(value) == "table" then
					if not assign[key] then
						assign[key] = { }
					end

					AssignTo(value, assign[key])
				else
					assign[key] = value
				end
			end
		end
	end

	AssignTo(data, default)
	return default --Reassigned to incorporate data
end

local function Verify(player, data, isFirst)
	if isFirst then
		return data
	end

	if not data._info then
		data._info = TableUtil.Copy(DefaultInfo)
	end

	if data._info.Blacklisted then
		KickPlayer(player, Globals.BLACKLIST_MESSAGE)
	end

	return data
end

local function Load(player)
	--Stamping
	if DataStore.Stamps[player.Name] then
		dwarn(player.Name .. "Already has data.")
		return
	else
		local stamp = os.clock()
		dwarn(player.Name .. " loaded at " .. stamp)
		DataStore.Stamps[player.Name] = stamp
	end

	--Setup
	local userId = player.UserId
	if not userId then
		userId = PlayersService:GetUserIdFromNameAsync(player.Name) --Remote Load
		player.UserId = userId
	end

	--Get Previous Save Keys
	local tries = 0
	local saves = DataStoreService:GetOrderedDataStore(
		Globals.TITLE .. "_SaveKeys_" .. Globals.VERSION,
		"Player_" .. userId
	)

	local function SaveKeys()
		local keys = { }
		local success, pages = pcall(function()
			return saves:GetSortedAsync(false, (Globals.ROLLBACK_CHECKS or 1))
		end)
		if not success then
			warn("Could not locate versions for " .. player.Name .. ".")
			if tries >= Globals.RETRIES_BEFORE_KICK then
				KickPlayer(player, Globals.ERROR_MESSAGE)
			else
				tries = tries + 1
				task.wait(1)
				return SaveKeys()
			end
		else
			for _, set in ipairs(pages:GetCurrentPage()) do
				table.insert(keys, set.key)
			end
			return keys
		end
	end

	local keys = SaveKeys()

	--First Time Player
	local sessionData, isFirst
	if not keys or #keys == 0 then
		isFirst = true
		sessionData = GetDefaultData(player, isFirst)
		sessionData = NewPlayer(player, sessionData)

		--Returning Player
	else
		--Get all the player's data
		tries = 0

		local function GetData(key)
			local success, data = pcall(function()
				return Store:GetAsync("Player_" .. userId .. "_" .. key)
			end)
			if not success then
				warn(
					"Failed to load "
						.. player.Name
						.. "'s data on key: "
						.. key
				)
				if tries >= Globals.RETRIES_BEFORE_KICK then
					KickPlayer(player, Globals.ERROR_MESSAGE)
					return "NONE"
				else
					tries = tries + 1
					task.wait(1)
					return GetData(key)
				end
			else
				return data
			end
		end

		--Find the best data
		local data, best
		for _, key in pairs(keys) do
			local check = GetData(key)
			if check and check == "NONE" then
				return
			end

			if not check then
				--Dead key
				saves:RemoveAsync(key)
				continue
			end

			--print(check)
			local duration = check._info.TimePlayed
			if not best or best < duration then
				data = check
				best = duration
			end

			tries = 0
		end

		if not data then
			warn("Still no data for " .. player.Name)
			return KickPlayer(player, Globals.ERROR_MESSAGE)
		end

		--Setup
		sessionData = Populate(player, data)
	end

	--Set
	if not sessionData then
		warn("No session data for " .. player.Name, sessionData)
		return KickPlayer(player, Globals.ERROR_MESSAGE)
	end

	DataStore.Session[player.Name] = Verify(player, sessionData, isFirst)
	dwarn(player.Name .. "'s Data: ", sessionData)
end

local function Save(player, autosave)
	if IsStudio and not Globals.SAVE_IN_STUDIO then
		return
	end

	--Stamping
	local stamp = DataStore.Stamps[player.Name]
	if not stamp then
		return warn(player.Name .. "'s data is already saved.")
	end

	if not autosave then
		DataStore.Stamps[player.Name] = nil
	else
		DataStore.Stamps[player.Name] = os.clock()
	end

	--Saving
	local data = DataStore.Session[player.Name]
	if not data then
		--Player already removed
		error("No session data found for " .. player.Name)
	end

	if not autosave then
		DataStore.SaveLeaderboard:Fire(player, data)
		DataStore.Session[player.Name] = nil
	end

	--Setup
	local userId = player.UserId
	local saveAttempts = 0
	if not autosave then
		saveAttempts = Globals.SAVE_ATTEMPTS
	end

	--Updates
	local timePlayed = math.floor(data._info.TimePlayed + (os.clock() - stamp))
	data._info.TimePlayed = timePlayed
	data._info.LastPlayed = os.time()

	--Save Key
	local saves = DataStoreService:GetOrderedDataStore(
		Globals.TITLE .. "_SaveKeys_" .. Globals.VERSION,
		"Player_" .. userId
	)
	local key = GetRandomKey()
	local tries = 0

	local function SaveKey()
		local success, err = pcall(function()
			return saves:UpdateAsync(key, function()
				return timePlayed
			end)
		end)
		if not success then
			warn("Could not save versions for " .. player.Name .. ".")
			warn(err)
			if tries >= saveAttempts then
				error(
					"CRITICAL: " .. player.Name .. "'s save key was not saved!"
				)
			else
				tries = tries + 1
				task.wait(tries / 2)
				SaveKey()
			end
		end
	end
	--SaveKey()

	--Save Data
	local function SaveData()
		local success, err = pcall(function()
			return Store:UpdateAsync(
				"Player_" .. userId .. "_" .. key,
				function()
					return data
				end
			)
		end)
		if not success then
			warn("Could not save data for " .. player.Name .. ".")
			warn(err)
			if tries >= saveAttempts then
				--saves:RemoveAsync(key)
				error(
					"CRITICAL: " .. player.Name .. "'s save data was not saved!"
				)
			else
				tries = tries + 1
				task.wait(tries)
				--SaveKey()
			end
		else
			SaveKey()
		end
	end
	SaveData()

	DataStore.Saved:Fire(player)
	warn(player.Name .. "'s data has been sucessfully saved!")
end

--API
DataStore.Load = Load
DataStore.Save = Save

function DataStore:Get(player, ...)
	local args = { ...; }

	return Promise.new(function(resolve, reject)
		if not (typeof(player) == "Instance" and player:IsA("Player")) then
			reject("'player' is not a Player instance")
		end

		self:OnLoad(player):andThen(function()
			local scope = self.Session[player.Name]

			for _, key in pairs(args) do
				scope = scope[key]
			end

			resolve(scope)
		end)
	end)
end

function DataStore:Set(player, ...)
	if not (typeof(player) == "Instance" and player:IsA("Player")) then
		error("'player' is not a Player instance")
	end

	local args = { ...; }

	self:OnLoad(player):andThen(function()
		local scope = self.Session[player.Name]
		local drill = TableUtil.Copy(args)
		local value = drill[#drill]
		table.remove(drill, #drill)

		for index, key in pairs(drill) do
			if index == #drill then
				scope[key] = value

				--[[ Inserting into tables?
				if type(scope[key]) == "table" then
					table.insert(scope[key],value)
				else
					scope[key] = value
				end
				]]
			else
				scope = scope[key]
			end
		end

		self.Client.Set:Fire(player, table.unpack(args))
	end)
end

function DataStore:Increment(player, ...)
	if not (typeof(player) == "Instance" and player:IsA("Player")) then
		error("'player' is not a Player instance")
	end

	local args = { ...; }

	self:OnLoad(player):andThen(function()
		local scope = self.Session[player.Name]
		local drill = TableUtil.Copy(args)
		local value = drill[#drill]

		if type(value) == "number" then
			table.remove(drill, #drill)
		else
			value = 1
		end

		for index, key in pairs(drill) do
			if index == #drill then
				scope[key] = (scope[key] or 0) + value
			else
				scope = scope[key]
			end
		end

		self.Client.Increment:Fire(player, table.unpack(args))
	end)
end

function DataStore:Delete(player)
	return self:OnLoad(player):andThen(function()
		warn("Deleting data for " .. player.Name)

		local old = self.Session[player.Name]
		local data = GetDefaultData(player, true)
		data._info = TableUtil.Assign(data._info or { }, old._info)

		self.Session[player.Name] = data
		self.Client.Delete:Fire(player, data)
	end)
end

function DataStore.isLoaded(player)
	return DataStore.Session[player.Name] ~= nil
end

function DataStore:OnLoad(player, timeout)
	return Promise.new(function(resolve, reject, onCancel)
		local start = os.clock()
		local yieldSent = false
		local run = true

		onCancel(function()
			run = false
		end)

		while run and not self.isLoaded(player) do
			if os.clock() - start > (timeout or 30) then
				if timeout then
					reject("Player data didn't load within timeout")
				end

				if not yieldSent then
					warn(
						"Possible infinite yield for "
							.. player.Name
							.. "'s data"
					)
					yieldSent = true
				end
			end

			task.wait()
		end

		resolve()
	end)
end

function DataStore:WipeKeys(name, amount)
	local userId = PlayersService:GetUserIdFromNameAsync(name)
	local saves = DataStoreService:GetOrderedDataStore(
		Globals.TITLE .. "_SaveKeys_" .. Globals.VERSION,
		"Player_" .. userId
	)

	local success, pages = pcall(function()
		return saves:GetSortedAsync(false, (amount or 100))
	end)
	if not success then
		warn("Could not get keys.")
	else
		for _, set in ipairs(pages:GetCurrentPage()) do
			success = pcall(function()
				saves:RemoveAsync(set.key)
			end)

			if success then
				warn("Key removed:,", set.key)
			else
				warn("ERROR: Failed to remove a key.")
			end
		end
	end
end

local Blacklist
--Store:SetAsync("Blacklist",{})
function DataStore:GetBlacklist()
	local success = pcall(function()
		Blacklist = Store:GetAsync("Blacklist")
	end)

	if not success then
		warn("Blacklist could not be updated.")
	end

	return Blacklist
end

function DataStore:Blacklist(name, remove)
	DataStore:GetBlacklist()

	if not Blacklist then
		return warn("No blacklist available")
	end

	local id = tostring(PlayersService:GetUserIdFromNameAsync(name))

	if self.Session[name] then
		self.Session[name]._info.Blacklisted = not remove
	end

	if remove then
		if not Blacklist[id] then
			return
		end
		Blacklist[id] = nil
	else
		if Blacklist[id] then
			return
		end
		Blacklist[id] = true
	end

	local success, err = pcall(function()
		return Store:SetAsync("Blacklist", Blacklist)
	end)

	if not success then
		warn("Could not save blacklist.")
		warn(err)
	end
end

function DataStore.Client:Init(player)
	local start = os.clock()
	repeat
		task.wait()
	until DataStore.Session[player.Name]
		or os.clock() - Globals.TIMEOUT >= start

	local data = DataStore.Session[player.Name]
	if data then
		return data
	elseif Globals.KICK_IN_STUDIO then
		KickPlayer(player, Globals.ERROR_MESSAGE)
		error("CRITICAL: Request for data was not completed.")
	end
end

--Shutdowns
game:BindToClose(function()
	for _, player in pairs(PlayersService:GetPlayers()) do
		Save(player)
	end
end)

function DataStore:KnitInit()
	DataStore.Client.Delete:Connect(function(player)
		DataStore:Delete(player)
	end)

	--Honeypot for morons
	local function MoronBlacklist(player)
		DataStore:Blacklist(player.Name)
		KickPlayer(player, Globals.BLACKLIST_MESSAGE)
	end

	DataStore.Client.Set:Connect(MoronBlacklist)
	DataStore.Client.Increment:Connect(MoronBlacklist)

	local Autosaving = { }
	PlayersService.PlayerAdded:Connect(function(player)
		Autosaving[player.Name] = os.clock() + Globals.AUTOSAVE_INTERVAL
		if Globals.AUTO_LOAD then
			Load(player)
		end
	end)

	PlayersService.PlayerRemoving:Connect(function(player)
		Autosaving[player.Name] = nil
	end)

	for _, player in pairs(PlayersService:GetPlayers()) do
		Autosaving[player.Name] = os.clock() + Globals.AUTOSAVE_INTERVAL
		if Globals.AUTO_LOAD then
			Load(player)
		end
	end

	coroutine.wrap(function()
		while task.wait(30) do
			for name, stamp in pairs(Autosaving) do
				local player = PlayersService:FindFirstChild(name)

				if not player then
					Autosaving[name] = nil
				elseif os.clock() >= stamp then
					Autosaving[name] = os.clock() + Globals.AUTOSAVE_INTERVAL
					Save(player, true)
				end

				task.wait(1)
			end
		end
	end)()
end

return DataStore
