local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local MyDataStore = require(Packages.MyDataStore)

MyDataStore:Start({
	TITLE = "Datastore";
	DEBUG = true;
}, script.Parent.DefaultData)

Knit.Start():catch(warn)
