--!strict
-- Состояние игры на клиенте: читает атрибуты матча и своего игрока, которые ведёт сервер.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Weapons)

local Game = {}

Game.player = Players.LocalPlayer
Game.state = ReplicatedStorage:WaitForChild("State")

local function text(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

function Game.phase(): string
	local phase = text(Game.state, "Phase")
	return if phase == "" then "Waiting" else phase
end

function Game.stateNumber(name: string): number
	return number(Game.state, name)
end

function Game.timeLeft(): number
	return math.max(0, number(Game.state, "PhaseEnds") - Workspace:GetServerTimeNow())
end

function Game.canBuy(): boolean
	local phase = Game.phase()
	return Game.alive() and (phase == "Freeze" or phase == "Live") and Workspace:GetServerTimeNow() < number(Game.state, "BuyEnds")
end

function Game.team(): string
	return text(Game.player, "Team")
end

function Game.alive(): boolean
	return Game.player:GetAttribute("Alive") == true
end

function Game.money(): number
	return number(Game.player, "Money")
end

function Game.armor(): number
	return number(Game.player, "Armor")
end

function Game.knife(): string
	local knife = text(Game.player, "Knife")
	return if knife == "" then "Classic" else knife
end

function Game.grenades(): { string }
	local list = text(Game.player, "Grenades")
	return if list == "" then {} else list:split(",")
end

-- Оружие в порядке слотов: основное, пистолет, нож, гранаты (без повторов)
function Game.weapons(): { string }
	local result = {}
	local primary, secondary = text(Game.player, "Primary"), text(Game.player, "Secondary")
	if primary ~= "" then
		table.insert(result, primary)
	end
	if secondary ~= "" then
		table.insert(result, secondary)
	end
	table.insert(result, "Knife")
	for _, grenade in Game.grenades() do
		if not table.find(result, grenade) then
			table.insert(result, grenade)
		end
	end
	return result
end

function Game.owns(weaponId: string): boolean
	return table.find(Game.weapons(), weaponId) ~= nil
end

local skins: { [string]: string } = {}
local function readSkins()
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(text(Game.player, "Skins"))
	end)
	skins = if ok and typeof(decoded) == "table" then decoded else {}
end
Game.player:GetAttributeChangedSignal("Skins"):Connect(readSkins)
readSkins()

-- Выбранный скин: key — id оружия или "Knife"
function Game.skin(key: string): string?
	local skin = skins[key]
	return if typeof(skin) == "string" then skin else nil
end

-- Модель и скин для вида от первого лица
function Game.look(weaponId: string): (string, string?)
	return Weapons.modelId(weaponId, Game.knife()), Game.skin(weaponId)
end

function Game.map(): Model?
	local maps = Workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild(text(Game.state, "Map"))
	return if map and map:IsA("Model") then map else nil
end

-- Подписка на атрибут с немедленным первым вызовом
function Game.watch(instance: Instance, name: string, callback: () -> ())
	instance:GetAttributeChangedSignal(name):Connect(callback)
	callback()
end

return Game
