-- Procedurally builds the whole obby course into Workspace.
-- Obstacles are tagged with CollectionService so Main can attach behaviour.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local COLORS = {
	platform = Color3.fromRGB(70, 74, 92),
	accent = Color3.fromRGB(110, 190, 255),
	lava = Color3.fromRGB(255, 85, 20),
	checkpoint = Color3.fromRGB(80, 220, 120),
	mover = Color3.fromRGB(255, 200, 60),
	vanish = Color3.fromRGB(190, 120, 255),
	truss = Color3.fromRGB(200, 200, 210),
	coin = Color3.fromRGB(255, 215, 0),
	finish = Color3.fromRGB(255, 255, 255),
}

local rng = Random.new(1337) -- fixed seed: same course every server

local function makePart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function platform(parent, position: Vector3, size: Vector3, color: Color3?): BasePart
	return makePart(parent, {
		Name = "Platform",
		Size = size,
		Position = position,
		Color = color or COLORS.platform,
	})
end

local function killBrick(parent, position: Vector3, size: Vector3): BasePart
	local p = makePart(parent, {
		Name = "Lava",
		Size = size,
		Position = position,
		Color = COLORS.lava,
		Material = Enum.Material.Neon,
	})
	CollectionService:AddTag(p, "KillBrick")
	return p
end

local function coin(parent, position: Vector3)
	local c = makePart(parent, {
		ClassName = "Part",
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2.2, 2.2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
		Color = COLORS.coin,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	c:SetAttribute("Active", true)
	CollectionService:AddTag(c, "Coin")
end

-- Each stage builder gets the start position (top surface centre of the
-- previous checkpoint) and must reach `start + (0, RISE, LENGTH)`.
-- It returns a list of positions where coins may be placed.
local StageBuilders = {}

-- Floating jump pads that get smaller with difficulty.
function StageBuilders.jumps(folder, start: Vector3, difficulty: number)
	local spots = {}
	local count = 5
	local size = math.max(3, 7 - difficulty * 4)
	for i = 1, count do
		local alpha = i / (count + 1)
		local pos = start
			+ Vector3.new(rng:NextNumber(-4, 4), Config.STAGE_RISE * alpha, Config.STAGE_LENGTH * alpha)
		platform(folder, pos, Vector3.new(size, 1, size), COLORS.accent)
		table.insert(spots, pos + Vector3.new(0, 3, 0))
	end
	return spots
end

-- A walkway crossed by lava strips you have to hop over.
function StageBuilders.lavaWalk(folder, start: Vector3, difficulty: number)
	local spots = {}
	local len = Config.STAGE_LENGTH - 8
	local mid = start + Vector3.new(0, Config.STAGE_RISE / 2, Config.STAGE_LENGTH / 2)
	makePart(folder, {
		Name = "Ramp",
		Size = Vector3.new(8, 1, 10),
		CFrame = CFrame.new(start + Vector3.new(0, Config.STAGE_RISE / 4, 6))
			* CFrame.Angles(-math.atan2(Config.STAGE_RISE / 2, 10), 0, 0),
		Color = COLORS.platform,
	})
	platform(folder, mid, Vector3.new(8, 1, len - 12))
	local strips = 4 + math.floor(difficulty * 3)
	for i = 1, strips do
		local z = (i / (strips + 1) - 0.5) * (len - 16)
		local width = 2 + difficulty * 2
		killBrick(folder, mid + Vector3.new(0, 0.6, z), Vector3.new(8, 0.3, width))
		table.insert(spots, mid + Vector3.new(0, 4, z))
	end
	return spots
end

-- Yellow platforms that slide side to side over the void.
function StageBuilders.movers(folder, start: Vector3, difficulty: number)
	local spots = {}
	local count = 3
	for i = 1, count do
		local alpha = i / (count + 1)
		local pos = start + Vector3.new(0, Config.STAGE_RISE * alpha, Config.STAGE_LENGTH * alpha)
		local p = platform(folder, pos, Vector3.new(7, 1, 7), COLORS.mover)
		p.Name = "Mover"
		p:SetAttribute("Origin", pos)
		p:SetAttribute("Axis", Vector3.new(1, 0, 0))
		p:SetAttribute("Distance", 8 + difficulty * 6)
		p:SetAttribute("Speed", 0.8 + difficulty * 1.2)
		p:SetAttribute("Phase", i * 1.7)
		CollectionService:AddTag(p, "Mover")
		table.insert(spots, pos + Vector3.new(0, 3, 0))
	end
	return spots
end

-- A big round platform with a spinning lava bar to jump over.
function StageBuilders.spinner(folder, start: Vector3, difficulty: number)
	local center = start + Vector3.new(0, Config.STAGE_RISE / 2, Config.STAGE_LENGTH / 2)
	-- Bridges in and out.
	platform(folder, start + Vector3.new(0, Config.STAGE_RISE / 4, 10), Vector3.new(5, 1, 14))
	platform(folder, start + Vector3.new(0, Config.STAGE_RISE * 3 / 4, Config.STAGE_LENGTH - 10), Vector3.new(5, 1, 14))
	makePart(folder, {
		Name = "Arena",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 30, 30),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.platform,
	})
	local bar = killBrick(folder, center + Vector3.new(0, 1.6, 0), Vector3.new(29, 1.2, 1.2))
	bar.Name = "SpinBar"
	bar:SetAttribute("Origin", center + Vector3.new(0, 1.6, 0))
	bar:SetAttribute("Speed", 1.2 + difficulty * 2)
	CollectionService:AddTag(bar, "Spinner")
	return {
		center + Vector3.new(8, 3, 0),
		center + Vector3.new(-8, 3, 0),
		center + Vector3.new(0, 3, 8),
	}
end

-- Purple tiles that vanish shortly after being touched.
function StageBuilders.vanish(folder, start: Vector3, _difficulty: number)
	local spots = {}
	local count = 6
	for i = 1, count do
		local alpha = i / (count + 1)
		local pos = start
			+ Vector3.new(i % 2 == 0 and 3 or -3, Config.STAGE_RISE * alpha, Config.STAGE_LENGTH * alpha)
		local p = platform(folder, pos, Vector3.new(5, 1, 5), COLORS.vanish)
		p.Name = "VanishTile"
		CollectionService:AddTag(p, "Vanish")
		table.insert(spots, pos + Vector3.new(0, 3, 0))
	end
	return spots
end

-- Climb a truss up a tall wall, then cross a narrow beam.
function StageBuilders.climb(folder, start: Vector3, difficulty: number)
	local height = Config.STAGE_RISE + 10
	local wallZ = start.Z + 14
	platform(folder, start + Vector3.new(0, 0, 7), Vector3.new(8, 1, 10))
	makePart(folder, {
		ClassName = "TrussPart",
		Name = "Truss",
		Size = Vector3.new(2, height, 2),
		Position = Vector3.new(start.X, start.Y + height / 2, wallZ - 1),
		Color = COLORS.truss,
	})
	platform(folder, Vector3.new(start.X, start.Y + height / 2, wallZ + 1), Vector3.new(10, height, 2))
	local beamTop = start.Y + height
	local beamLen = Config.STAGE_LENGTH - 20
	local beamWidth = math.max(1.5, 3 - difficulty * 1.5)
	platform(folder, Vector3.new(start.X, beamTop, wallZ + 2 + beamLen / 2), Vector3.new(beamWidth, 1, beamLen))
	-- Drop down onto the next checkpoint.
	return {
		Vector3.new(start.X, beamTop + 3, wallZ + 2 + beamLen * 0.25),
		Vector3.new(start.X, beamTop + 3, wallZ + 2 + beamLen * 0.5),
		Vector3.new(start.X, beamTop + 3, wallZ + 2 + beamLen * 0.75),
	}
end

local STAGE_ORDER = { "jumps", "lavaWalk", "movers", "spinner", "vanish", "climb" }

local function checkpoint(folder, position: Vector3, stage: number): BasePart
	local pad = makePart(folder, {
		Name = "Checkpoint" .. stage,
		Size = Vector3.new(12, 1, 8),
		Position = position - Vector3.new(0, 0.5, 0),
		Color = COLORS.checkpoint,
		Material = Enum.Material.Neon,
	})
	pad:SetAttribute("Stage", stage)
	CollectionService:AddTag(pad, "Checkpoint")

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(stage)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Rotation = 180
	label.Parent = gui
	gui.Parent = pad
	return pad
end

-- Builds the map and returns { checkpoints = {[stage] = part}, finish = part }.
function MapBuilder.build()
	local existing = workspace:FindFirstChild("Course")
	if existing then
		existing:Destroy()
	end

	local course = Instance.new("Folder")
	course.Name = "Course"
	course.Parent = workspace

	local checkpoints = {}
	local pos = Vector3.new(0, 10, 0)

	-- Spawn platform doubles as checkpoint 1.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 8)
	spawn.Position = pos - Vector3.new(0, 0.5, 0)
	spawn.Color = COLORS.checkpoint
	spawn.Material = Enum.Material.Neon
	spawn.Parent = course
	spawn:SetAttribute("Stage", 1)
	CollectionService:AddTag(spawn, "Checkpoint")
	checkpoints[1] = spawn
	platform(course, pos + Vector3.new(0, -0.5, -10), Vector3.new(24, 1, 14))

	for stage = 1, Config.STAGE_COUNT do
		local folder = Instance.new("Folder")
		folder.Name = "Stage" .. stage
		folder.Parent = course

		local difficulty = (stage - 1) / math.max(1, Config.STAGE_COUNT - 1)
		local kind = STAGE_ORDER[(stage - 1) % #STAGE_ORDER + 1]
		local spots = StageBuilders[kind](folder, pos, difficulty)

		for i = 1, math.min(Config.COINS_PER_STAGE, #spots) do
			coin(folder, spots[math.ceil(i * #spots / Config.COINS_PER_STAGE)])
		end

		pos += Vector3.new(0, Config.STAGE_RISE, Config.STAGE_LENGTH)
		if stage < Config.STAGE_COUNT then
			checkpoints[stage + 1] = checkpoint(folder, pos, stage + 1)
		end
	end

	-- Finish platform with a trophy.
	local finish = makePart(course, {
		Name = "Finish",
		Size = Vector3.new(20, 1, 20),
		Position = pos - Vector3.new(0, 0.5, -6),
		Color = COLORS.finish,
		Material = Enum.Material.Neon,
	})
	CollectionService:AddTag(finish, "Finish")
	makePart(course, {
		Name = "Trophy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		Position = pos + Vector3.new(0, 6, 10),
		Color = COLORS.coin,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	-- A lava sea under the whole course so falling is an instant respawn.
	local totalLength = (Config.STAGE_COUNT + 2) * Config.STAGE_LENGTH
	local sea = killBrick(course, Vector3.new(0, -4, totalLength / 2 - 30), Vector3.new(220, 2, totalLength + 60))
	sea.Name = "LavaSea"

	return { checkpoints = checkpoints, finish = finish }
end

return MapBuilder
