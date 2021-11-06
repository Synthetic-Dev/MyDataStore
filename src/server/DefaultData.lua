local HttpService = game:GetService("HttpService")

return {
	Experience = 0;
	Money = 100;
	Rank = "Developer";

	-- This is a constructor function that allows you to create player specific/unique defaults
	Items = function(_player, isFirst)
		-- We only want to run this if it is the first time the player is joining the game,
		-- or if their data has been reset. This is because if "Items" was empty, this method
		-- would give the player another "Random Item"
		if not isFirst then
			return
		end

		-- In this case an item needs a unique guid, so we have to use a constructor function
		local items = {
			{
				Name = "Random item";
				Guid = HttpService:GenerateGUID(false);
			};
		}

		return items
	end;
}
