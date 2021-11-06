--Override any of these values by using `MyDataStore:SetGlobals(globals)`

return {
	-- Datastore identity
	TITLE = "global";
	VERSION = 0;

	-- Intervals / tries
	AUTOSAVE_INTERVAL = 10 * 60; -- Minutes
	TIMEOUT = 60; -- Seconds before kicking for no data
	RETRIES_BEFORE_KICK = 3;
	SAVE_ATTEMPTS = 20;

	-- Messages
	ERROR_MESSAGE = "Sorry! There was a problem loading your data. Please rejoin!";
	BLACKLIST_MESSAGE = "You are blacklisted from this game!";

	-- Flags
	ROLLBACK_CHECKS = false;
	AUTO_LOAD = true;
	CAN_KICK = true;
	KICK_IN_STUDIO = true;
	SAVE_IN_STUDIO = true;
	DEBUG = false;
}
