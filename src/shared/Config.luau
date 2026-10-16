-- Shared tuning values for Lava Rush Obby.
local Config = {
	STAGE_COUNT = 30,

	-- Layout: every stage moves this far forward and this far up.
	STAGE_LENGTH = 60,
	STAGE_RISE = 6,

	COINS_PER_STAGE = 3,
	COIN_VALUE = 1,
	COIN_RESPAWN_SECONDS = 15,

	SKIP_STAGE_COST = 25,
	WIN_COIN_BONUS = 50,

	AUTOSAVE_SECONDS = 60,
	DATASTORE_NAME = "LavaRushObby_v1",

	REMOTES = {
		SkipStage = "SkipStage",
		Won = "Won",
		Notify = "Notify",
	},
}

return Config
