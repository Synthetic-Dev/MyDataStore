local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local MyDataStore = require(Packages.MyDataStore)

MyDataStore:Start()
