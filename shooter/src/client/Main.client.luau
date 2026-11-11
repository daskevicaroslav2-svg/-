--!strict
-- Точка входа клиента шутера: интерфейс, камера, оружие и клавиши меню.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Arms = require(script.Parent.Arms)
local Game = require(script.Parent.Game)
local Hud = require(script.Parent.Hud)
local Menus = require(script.Parent.Menus)
local Movement = require(script.Parent.Movement)
local Ui = require(script.Parent.Ui)
local View = require(script.Parent.View)

local player = Players.LocalPlayer

local gui: ScreenGui = Ui.new("ScreenGui", {
	Name = "Shooter",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})
Hud.init(gui)
Menus.init(gui)
Arms.init()

-- Стандартные рюкзак, полоску здоровья и список игроков заменяет свой интерфейс.
-- CoreGui может быть ещё не готов, поэтому несколько попыток.
local function setCore(kind: Enum.CoreGuiType, enabled: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, enabled)
	end)
end
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		Movement.bind(humanoid)
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

local MENU_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.B] = "shop",
	[Enum.KeyCode.N] = "loadout",
	[Enum.KeyCode.M] = "team",
}

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local menu = MENU_KEYS[input.KeyCode]
	if input.KeyCode == Enum.KeyCode.Tab then
		setCore(Enum.CoreGuiType.PlayerList, true)
	elseif menu == "shop" and not Menus.isOpen() and not Game.canBuy() then
		Hud.notice(Config.Text.ShopClosed, true)
	elseif menu then
		Menus.toggle(menu)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not Game.alive() and not Menus.isOpen() then
		View.nextSpectate()
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Tab then
		setCore(Enum.CoreGuiType.PlayerList, false)
	end
end)

-- Без команды сразу открывается выбор стороны
Game.watch(player, "Team", function()
	if Game.team() == "" then
		Menus.open("team")
	end
end)

local shopWasOpen = false
RunService:BindToRenderStep("Shooter", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	View.update(dt, camera)
	Arms.update(dt, camera)
	Hud.update(dt, camera)
	Menus.update(dt)

	-- Строка состояния для выбывшего игрока
	local status = ""
	if Game.team() ~= "" and not Game.alive() then
		local name = View.spectatedName()
		local phase = Game.phase()
		if name then
			status = string.format(Config.Text.Spectating, name)
		elseif phase == "Live" or phase == "RoundEnd" then
			status = Config.Text.NextRound
		end
	end
	Hud.setStatus(status)

	-- Магазин закрывается сам, когда время покупки вышло
	local shopOpen = Menus.isOpen() and gui:FindFirstChild("shop") ~= nil and (gui:FindFirstChild("shop") :: Frame).Visible
	if shopOpen and shopWasOpen and not Game.canBuy() then
		Menus.close()
	end
	shopWasOpen = shopOpen
end)
