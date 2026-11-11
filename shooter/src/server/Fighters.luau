--!strict
-- Бойцы: игроки и боты, участвующие в матче. Состояние игрока копируется в его атрибуты.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

export type Ammo = { mag: number, reserve: number }

export type Prefs = { knife: string, skins: { [string]: string } }

export type Hit = { by: any, weapon: string, headshot: boolean, at: number }

export type Fighter = {
	id: number,
	name: string,
	team: string, -- T или CT
	player: Player?, -- nil у бота
	model: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	alive: boolean,
	money: number,
	armor: number,
	primary: string?,
	secondary: string?,
	grenades: { string },
	equipped: string,
	ammo: { [string]: Ammo },
	prefs: Prefs, -- выбранный нож и скины
	kills: number,
	deaths: number,
	lossStreak: number,
	keepLoadout: boolean, -- пережил прошлый раунд и сохраняет оружие
	lastFire: number,
	lastAttack: number,
	lastReload: number,
	lastHit: Hit?,
	blindUntil: number,
}

local Fighters = {}

Fighters.list = {} :: { Fighter }

local byModel: { [Model]: Fighter } = {}
local byPlayer: { [Player]: Fighter } = {}
local nextId = 0

function Fighters.create(team: string, name: string, player: Player?, prefs: Prefs): Fighter
	nextId += 1
	local fighter: Fighter = {
		id = nextId,
		name = name,
		team = team,
		player = player,
		model = nil,
		humanoid = nil,
		root = nil,
		alive = false,
		money = Config.StartMoney,
		armor = 0,
		primary = nil,
		secondary = nil,
		grenades = {},
		equipped = "Knife",
		ammo = {},
		prefs = prefs,
		kills = 0,
		deaths = 0,
		lossStreak = 0,
		keepLoadout = false,
		lastFire = 0,
		lastAttack = 0,
		lastReload = 0,
		lastHit = nil,
		blindUntil = 0,
	}
	table.insert(Fighters.list, fighter)
	if player then
		byPlayer[player] = fighter
	end
	return fighter
end

-- Привязывает модель персонажа к бойцу (и отвязывает прежнюю)
function Fighters.bind(fighter: Fighter, model: Model?)
	if fighter.model then
		byModel[fighter.model] = nil
	end
	fighter.model = model
	if model then
		byModel[model] = fighter
	end
end

function Fighters.remove(fighter: Fighter)
	Fighters.bind(fighter, nil)
	if fighter.player and byPlayer[fighter.player] == fighter then
		byPlayer[fighter.player] = nil
	end
	local index = table.find(Fighters.list, fighter)
	if index then
		table.remove(Fighters.list, index)
	end
end

function Fighters.ofPlayer(player: Player): Fighter?
	return byPlayer[player]
end

-- Боец, которому принадлежит деталь (часть тела персонажа)
function Fighters.ofPart(part: Instance): Fighter?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local fighter = byModel[model]
		if fighter then
			return fighter
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Fighters.team(team: string): { Fighter }
	local result = {}
	for _, fighter in Fighters.list do
		if fighter.team == team then
			table.insert(result, fighter)
		end
	end
	return result
end

function Fighters.aliveCount(team: string): number
	local count = 0
	for _, fighter in Fighters.list do
		if fighter.team == team and fighter.alive then
			count += 1
		end
	end
	return count
end

function Fighters.humans(team: string?): number
	local count = 0
	for _, fighter in Fighters.list do
		if fighter.player and (team == nil or fighter.team == team) then
			count += 1
		end
	end
	return count
end

-- Копирует состояние бойца в атрибуты игрока: по ним клиент рисует интерфейс
function Fighters.sync(fighter: Fighter)
	local player = fighter.player
	if not player then
		return
	end
	player:SetAttribute("Team", fighter.team)
	player:SetAttribute("Money", fighter.money)
	player:SetAttribute("Armor", math.floor(fighter.armor + 0.5))
	player:SetAttribute("Primary", fighter.primary or "")
	player:SetAttribute("Secondary", fighter.secondary or "")
	player:SetAttribute("Grenades", table.concat(fighter.grenades, ","))
	player:SetAttribute("Equipped", fighter.equipped)
	player:SetAttribute("Alive", fighter.alive)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local kills, deaths = stats:FindFirstChild("Убийства"), stats:FindFirstChild("Смерти")
		if kills and kills:IsA("IntValue") then
			kills.Value = fighter.kills
		end
		if deaths and deaths:IsA("IntValue") then
			deaths.Value = fighter.deaths
		end
	end
end

-- Выбранные нож и скины лежат в атрибутах игрока и до выбора команды
function Fighters.syncPrefs(player: Player, prefs: Prefs)
	player:SetAttribute("Knife", prefs.knife)
	player:SetAttribute("Skins", HttpService:JSONEncode(prefs.skins))
end

function Fighters.addMoney(fighter: Fighter, amount: number)
	fighter.money = math.clamp(fighter.money + amount, 0, Config.MaxMoney)
	Fighters.sync(fighter)
end

return Fighters
