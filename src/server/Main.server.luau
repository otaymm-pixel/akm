-- Server entry point: builds the course, wires up obstacles, tracks
-- player progress and saves it with DataStores.
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapBuilder = require(script.Parent.MapBuilder)

-- Atmosphere ----------------------------------------------------------------

Lighting.ClockTime = 18.2
Lighting.Brightness = 2
Lighting.OutdoorAmbient = Color3.fromRGB(150, 110, 100)
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Color = Color3.fromRGB(255, 160, 120)
atmosphere.Decay = Color3.fromRGB(120, 60, 50)
atmosphere.Parent = Lighting

local map = MapBuilder.build()

-- Remotes -------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local skipRemote = remote(Config.REMOTES.SkipStage)
local wonRemote = remote(Config.REMOTES.Won)
local notifyRemote = remote(Config.REMOTES.Notify)
remotes.Parent = ReplicatedStorage

-- Player data ---------------------------------------------------------------

local store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
local loaded: { [Player]: boolean } = {}

local function stat(player: Player, name: string): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(name) :: IntValue?
end

local function loadData(player: Player)
	local ok, data = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if not ok then
		warn("Failed to load data for", player.Name, data)
		data = nil
	end
	data = data or {}

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Stage", "Coins", "Wins" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = stats
	end
	stats.Stage.Value = math.clamp(data.Stage or 1, 1, Config.STAGE_COUNT)
	stats.Coins.Value = data.Coins or 0
	stats.Wins.Value = data.Wins or 0
	stats.Parent = player

	-- Only allow saving if the load succeeded, so a DataStore outage
	-- can't overwrite real progress with zeros.
	loaded[player] = ok
end

local function saveData(player: Player)
	if not loaded[player] then
		return
	end
	local stage, coins, wins = stat(player, "Stage"), stat(player, "Coins"), stat(player, "Wins")
	if not (stage and coins and wins) then
		return
	end
	local payload = { Stage = stage.Value, Coins = coins.Value, Wins = wins.Value }
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Failed to save data for", player.Name, err)
	end
end

-- Respawning at checkpoints --------------------------------------------------

local function sendToStage(player: Player)
	local character = player.Character
	local stage = stat(player, "Stage")
	if not (character and stage) then
		return
	end
	local pad = map.checkpoints[stage.Value] or map.checkpoints[1]
	character:PivotTo(CFrame.new(pad.Position + Vector3.new(0, 4, 0)))
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart")
	task.wait() -- let the default spawn finish before moving
	sendToStage(player)
end

local function onPlayerAdded(player: Player)
	loadData(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	loaded[player] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(saveData, player)
	end
	task.wait(2)
end)

task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_SECONDS)
		for _, player in Players:GetPlayers() do
			task.spawn(saveData, player)
		end
	end
end)

-- Helpers for touch handlers --------------------------------------------------

local function playerFromHit(hit: BasePart): (Player?, Humanoid?)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)
	if not (humanoid and player) or humanoid.Health <= 0 then
		return nil, nil
	end
	return player, humanoid
end

local function onTagged(tag: string, callback: (BasePart) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(callback, inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
end

-- Obstacles -------------------------------------------------------------------

onTagged("KillBrick", function(part)
	part.Touched:Connect(function(hit)
		local _, humanoid = playerFromHit(hit)
		if humanoid then
			humanoid.Health = 0
		end
	end)
end)

onTagged("Checkpoint", function(part)
	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local stage = player and stat(player, "Stage")
		local padStage = part:GetAttribute("Stage")
		if stage and padStage and padStage > stage.Value then
			stage.Value = padStage
			notifyRemote:FireClient(player, ("Checkpoint! Stage %d"):format(padStage))
		end
	end)
end)

onTagged("Coin", function(part)
	part.Touched:Connect(function(hit)
		if not part:GetAttribute("Active") then
			return
		end
		local player = playerFromHit(hit)
		local coins = player and stat(player, "Coins")
		if not coins then
			return
		end
		part:SetAttribute("Active", false)
		part.Transparency = 1
		coins.Value += Config.COIN_VALUE
		task.delay(Config.COIN_RESPAWN_SECONDS, function()
			part.Transparency = 0
			part:SetAttribute("Active", true)
		end)
	end)
end)

onTagged("Vanish", function(part)
	local busy = false
	part.Touched:Connect(function(hit)
		if busy or not playerFromHit(hit) then
			return
		end
		busy = true
		for i = 1, 5 do
			part.Transparency = i * 0.15
			task.wait(0.1)
		end
		part.CanCollide = false
		part.Transparency = 1
		task.wait(2)
		part.CanCollide = true
		part.Transparency = 0
		busy = false
	end)
end)

local winDebounce: { [Player]: boolean } = {}
map.finish.Touched:Connect(function(hit)
	local player = playerFromHit(hit)
	if not player or winDebounce[player] then
		return
	end
	local stage, coins, wins = stat(player, "Stage"), stat(player, "Coins"), stat(player, "Wins")
	if not (stage and coins and wins) or stage.Value < Config.STAGE_COUNT then
		return -- must actually reach the last checkpoint first
	end
	winDebounce[player] = true
	wins.Value += 1
	coins.Value += Config.WIN_COIN_BONUS
	stage.Value = 1
	wonRemote:FireAllClients(player.Name, wins.Value)
	task.delay(4, function()
		sendToStage(player)
		winDebounce[player] = nil
	end)
end)

-- Moving parts. Anchored parts are moved by CFrame each frame; we also set
-- their velocity so characters standing on them get carried along.
local movers = CollectionService:GetTagged("Mover")
local spinners = CollectionService:GetTagged("Spinner")
local clock = 0

RunService.Heartbeat:Connect(function(dt)
	clock += dt
	for _, p in movers do
		local origin: Vector3 = p:GetAttribute("Origin")
		local axis: Vector3 = p:GetAttribute("Axis")
		local dist: number = p:GetAttribute("Distance")
		local speed: number = p:GetAttribute("Speed")
		local phase: number = p:GetAttribute("Phase") or 0
		local t = clock * speed + phase
		p.CFrame = CFrame.new(origin + axis * math.sin(t) * dist)
		p.AssemblyLinearVelocity = axis * math.cos(t) * dist * speed
	end
	for _, p in spinners do
		local origin: Vector3 = p:GetAttribute("Origin")
		local speed: number = p:GetAttribute("Speed")
		p.CFrame = CFrame.new(origin) * CFrame.Angles(0, clock * speed, 0)
	end
end)

-- Shop: skip a stage for coins ---------------------------------------------------

skipRemote.OnServerEvent:Connect(function(player)
	local stage, coins = stat(player, "Stage"), stat(player, "Coins")
	if not (stage and coins) then
		return
	end
	if stage.Value >= Config.STAGE_COUNT then
		notifyRemote:FireClient(player, "You're on the last stage - go finish it!")
		return
	end
	if coins.Value < Config.SKIP_STAGE_COST then
		notifyRemote:FireClient(player, ("Need %d coins to skip"):format(Config.SKIP_STAGE_COST))
		return
	end
	coins.Value -= Config.SKIP_STAGE_COST
	stage.Value += 1
	sendToStage(player)
	notifyRemote:FireClient(player, ("Skipped to stage %d"):format(stage.Value))
end)
