return {
	TITLE = "global";
	VERSION = 0;

	AUTOSAVE_INTERVAL = 10 * 60; -- Minutes
	ROLLBACK_CHECKS = false;
	RETRIES_BEFORE_KICK = 3;
	SAVE_ATTEMPTS = 20;
	TIMEOUT = 60; -- Seconds before kicking for no data

	ERROR_MESSAGE = "Sorry! There was a problem loading your data. Please rejoin!";
	BLACKLIST_MESSAGE = "You are blacklisted from this game!";

	AUTO_LOAD = true;
	CAN_KICK = true;
	KICK_IN_STUDIO = true;
	SAVE_IN_STUDIO = true;
	DEBUG = true;
}
