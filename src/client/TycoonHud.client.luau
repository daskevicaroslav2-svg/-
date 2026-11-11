--!strict
-- Интерфейс игрока: деньги, множитель дохода, подсказка и всплывающие сообщения.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local notifyEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent
local player = Players.LocalPlayer

local CASH_COLOR = Color3.fromRGB(110, 255, 130)
local TOAST_COLORS: { [string]: Color3 } = {
	info = Color3.new(1, 1, 1),
	success = Color3.fromRGB(120, 255, 140),
	error = Color3.fromRGB(255, 110, 110),
}
local TOAST_BACKGROUND = 0.25
local TOAST_TIME = 2.5

local gui = Instance.new("ScreenGui")
gui.Name = "TycoonHud"
gui.ResetOnSpawn = false

local function panel(name: string, anchor: Vector2, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = anchor
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	label.BackgroundTransparency = TOAST_BACKGROUND
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = gui
	return label
end

local cashLabel = panel("Cash", Vector2.new(0, 0.5), UDim2.new(0, 12, 0.5, 0), UDim2.fromOffset(220, 48), 28)
cashLabel.TextColor3 = CASH_COLOR
local multiplierLabel = panel("Multiplier", Vector2.new(0, 0.5), UDim2.new(0, 12, 0.5, 44), UDim2.fromOffset(220, 30), 18)
local hintLabel = panel("Hint", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12), UDim2.new(0.7, 0, 0, 48), 20)
hintLabel.Text = Config.Text.Hint
local toast = panel("Toast", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -90), UDim2.new(0.6, 0, 0, 44), 22)
toast.Visible = false

gui.Parent = player:WaitForChild("PlayerGui")

local leaderstats = player:WaitForChild("leaderstats")
local cash = leaderstats:WaitForChild(Config.CashStat) :: IntValue
local rebirths = leaderstats:WaitForChild(Config.RebirthStat) :: IntValue

local function updateCash()
	cashLabel.Text = Format.money(cash.Value)
	-- Короткая вспышка при изменении суммы
	cashLabel.TextColor3 = Color3.new(1, 1, 1)
	TweenService:Create(cashLabel, TweenInfo.new(0.35), { TextColor3 = CASH_COLOR }):Play()
end

local function updateMultiplier()
	local multiplier = 1 + Config.RebirthBonus * rebirths.Value
	multiplierLabel.Visible = rebirths.Value > 0
	multiplierLabel.Text = string.format(Config.Text.Multiplier, Format.multiplier(multiplier))
end

local function updateHint()
	hintLabel.Visible = player:GetAttribute("Tycoon") == nil
end

local toastId = 0
local function showToast(text: string, kind: string)
	toastId += 1
	local id = toastId
	toast.Text = text
	toast.TextColor3 = TOAST_COLORS[kind] or TOAST_COLORS.info
	toast.TextTransparency = 0
	toast.BackgroundTransparency = TOAST_BACKGROUND
	toast.Visible = true
	task.delay(TOAST_TIME, function()
		if toastId == id then
			local fade = { TextTransparency = 1, BackgroundTransparency = 1 }
			TweenService:Create(toast, TweenInfo.new(0.4), fade):Play()
		end
	end)
end

cash.Changed:Connect(updateCash)
rebirths.Changed:Connect(updateMultiplier)
player:GetAttributeChangedSignal("Tycoon"):Connect(updateHint)
notifyEvent.OnClientEvent:Connect(function(text: unknown, kind: unknown)
	if typeof(text) == "string" then
		showToast(text, if typeof(kind) == "string" then kind else "info")
	end
end)

updateCash()
updateMultiplier()
updateHint()
