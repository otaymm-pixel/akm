-- Client HUD: stage progress, coin counter, skip button, toasts, and
-- local-only coin spinning.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ObbyHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

-- Top bar: stage label + progress bar.
local top = Instance.new("Frame")
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 10)
top.Size = UDim2.fromOffset(320, 56)
top.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
top.BackgroundTransparency = 0.25
corner(top, 12)
top.Parent = gui

local stageLabel = label(top, "Stage 1", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 4))

local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(10, 36)
barBack.Size = UDim2.new(1, -20, 0, 10)
barBack.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
corner(barBack, 5)
barBack.Parent = top

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 120, 40)
corner(barFill, 5)
barFill.Parent = barBack

-- Bottom-left: coins + skip button.
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 12, 1, -12)
panel.Size = UDim2.fromOffset(200, 100)
panel.BackgroundTransparency = 1
panel.Parent = gui

local coinLabel = label(panel, "Coins: 0", UDim2.new(1, 0, 0, 36), UDim2.fromOffset(0, 0))
coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
coinLabel.TextXAlignment = Enum.TextXAlignment.Left

local skip = Instance.new("TextButton")
skip.Position = UDim2.fromOffset(0, 44)
skip.Size = UDim2.new(1, 0, 0, 48)
skip.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
skip.Font = Enum.Font.FredokaOne
skip.TextColor3 = Color3.new(1, 1, 1)
skip.TextScaled = true
skip.Text = ("Skip Stage (%d coins)"):format(Config.SKIP_STAGE_COST)
corner(skip, 10)
skip.Parent = panel
skip.Activated:Connect(function()
	remotes[Config.REMOTES.SkipStage]:FireServer()
end)

-- Toast in the middle of the screen.
local toast = label(gui, "", UDim2.fromOffset(500, 50), UDim2.new(0.5, -250, 0.22, 0))
toast.TextTransparency = 1
toast.TextStrokeTransparency = 1

local toastToken = 0
local function showToast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = color or Color3.new(1, 1, 1)
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.4
	task.delay(2.5, function()
		if token == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.5), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)
end

remotes[Config.REMOTES.Notify].OnClientEvent:Connect(function(text: string)
	showToast(text)
end)

remotes[Config.REMOTES.Won].OnClientEvent:Connect(function(name: string, wins: number)
	if name == player.Name then
		showToast(("YOU WIN! Total wins: %d  (+%d coins)"):format(wins, Config.WIN_COIN_BONUS), Color3.fromRGB(255, 215, 0))
	else
		showToast(("%s beat the obby!"):format(name), Color3.fromRGB(255, 180, 120))
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")

-- Bind HUD to leaderstats.
local stats = player:WaitForChild("leaderstats")
local stageValue = stats:WaitForChild("Stage") :: IntValue
local coinValue = stats:WaitForChild("Coins") :: IntValue

local function refreshStage()
	stageLabel.Text = ("Stage %d / %d"):format(stageValue.Value, Config.STAGE_COUNT)
	local fraction = (stageValue.Value - 1) / math.max(1, Config.STAGE_COUNT - 1)
	TweenService:Create(barFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(fraction, 1) }):Play()
end

local function refreshCoins()
	coinLabel.Text = ("Coins: %d"):format(coinValue.Value)
end

stageValue.Changed:Connect(refreshStage)
coinValue.Changed:Connect(refreshCoins)
refreshStage()
refreshCoins()

-- Spin coins locally (visual only, saves server bandwidth).
local coinBase: { [BasePart]: CFrame } = {}
local function trackCoin(coin: Instance)
	if coin:IsA("BasePart") then
		coinBase[coin] = coin.CFrame
	end
end
for _, coin in CollectionService:GetTagged("Coin") do
	trackCoin(coin)
end
CollectionService:GetInstanceAddedSignal("Coin"):Connect(trackCoin)
CollectionService:GetInstanceRemovedSignal("Coin"):Connect(function(coin)
	coinBase[coin] = nil
end)

local angle = 0
RunService.RenderStepped:Connect(function(dt)
	angle += dt * 3
	local bob = math.sin(angle) * 0.4
	for coin, base in coinBase do
		coin.CFrame = CFrame.new(base.Position + Vector3.new(0, bob, 0))
			* CFrame.Angles(0, angle, 0)
			* (base - base.Position)
	end
end)
