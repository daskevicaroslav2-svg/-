--!strict
-- Боты: дополняют команды до нужного размера, ходят по карте к меткам и стреляют
-- по врагам, которых видят.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arsenal = require(Shared.Arsenal)
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Characters = require(script.Parent.Characters)
local Combat = require(script.Parent.Combat)
local Fighters = require(script.Parent.Fighters)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

type Fighter = Fighters.Fighter

type Brain = {
	fighter: Fighter,
	goal: Vector3?,
	goalUntil: number,
	waypoints: { PathWaypoint }?,
	index: number,
	lastPosition: Vector3,
	lastProgress: number,
	seenSince: number?,
	reaction: number,
	nextShot: number,
	nextStrafe: number,
	burst: number,
}

local Bots = {}

local THINK_INTERVAL = 0.15
local PRIMARIES: { [string]: { string } } = {
	T = { "AK47", "AK47", "MP9", "AWP" },
	CT = { "M4A4", "M4A4", "MP9", "AWP" },
}

local brains: { [Fighter]: Brain } = {}
local plan: { [string]: string } = {} -- куда команда идёт в этом раунде
local usedNames: { [string]: boolean } = {}

local function range(bounds: { number }): number
	return bounds[1] + math.random() * (bounds[2] - bounds[1])
end

local function freeName(): string
	local names = Config.Bots.names
	for _ = 1, 20 do
		local name = names[math.random(#names)]
		if not usedNames[name] then
			usedNames[name] = true
			return "Бот " .. name
		end
	end
	return "Бот " .. names[math.random(#names)]
end

-- Случайный нож и скины: боты тоже красуются
local function randomPrefs(): Fighters.Prefs
	local knives = Arsenal.knives()
	local prefs: Fighters.Prefs = { knife = knives[math.random(#knives)], skins = {} }
	for _, weapon in Weapons.list do
		local skins = Arsenal.skins(Weapons.modelId(weapon.id, prefs.knife))
		if #skins > 0 and math.random() < 0.6 then
			prefs.skins[weapon.id] = skins[math.random(#skins)].id
		end
	end
	return prefs
end

local function bots(team: string): { Fighter }
	local result = {}
	for _, fighter in Fighters.team(team) do
		if not fighter.player then
			table.insert(result, fighter)
		end
	end
	return result
end

-- Подгоняет число ботов: в каждой команде бойцов должно быть Config.TeamSize
function Bots.balance()
	for _, team in { "T", "CT" } do
		local list = bots(team)
		local want = math.max(0, Config.TeamSize - Fighters.humans(team))
		while #list > want do
			local fighter = table.remove(list) :: Fighter
			brains[fighter] = nil
			Characters.remove(fighter)
			Fighters.remove(fighter)
		end
		while #list < want do
			table.insert(list, Fighters.create(team, freeName(), nil, randomPrefs()))
		end
	end
end

function Bots.removeAll()
	for _, team in { "T", "CT" } do
		for _, fighter in bots(team) do
			brains[fighter] = nil
			Characters.remove(fighter)
			Fighters.remove(fighter)
		end
	end
	table.clear(usedNames)
end

-- Оружие бота на раунд: в первом раунде пистолеты, дальше случайное основное
function Bots.arm(fighter: Fighter)
	fighter.primary = nil
	fighter.secondary = Weapons.defaultPistol(fighter.team)
	fighter.armor = if State.round > 1 then 100 else 0
	if State.round > 1 and math.random() < 0.8 then
		local options = PRIMARIES[fighter.team]
		fighter.primary = options[math.random(#options)]
	end
	fighter.equipped = fighter.primary or fighter.secondary :: string
	local weapon = Weapons.get(fighter.equipped)
	if weapon and fighter.humanoid then
		fighter.humanoid.WalkSpeed = weapon.speed
	end
	Characters.holdWeapon(fighter)
end

local function findTarget(fighter: Fighter, eye: Vector3, look: Vector3): (Fighter?, Vector3?)
	local best: Fighter? = nil
	local bestPoint: Vector3? = nil
	local bestDistance = Config.Bots.viewDistance
	for _, other in Fighters.list do
		local root = other.root
		if other.alive and other.team ~= fighter.team and root then
			local point = root.CFrame.Position + Vector3.new(0, 0.5, 0)
			local offset = point - eye
			local distance = offset.Magnitude
			-- За спиной бот не видит, вплотную — чувствует
			local inView = distance < 12 or look:Dot(offset.Unit) > -0.3
			if distance < bestDistance and inView and not World.hidden(eye, point) then
				best, bestPoint, bestDistance = other, point, distance
			end
		end
	end
	return best, bestPoint
end

local function computePath(from: Vector3, to: Vector3): { PathWaypoint }?
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 8 })
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end
	return nil
end

-- Первая цель — план команды, дальше случайные места карты
local function pickGoal(brain: Brain): Vector3?
	local marks = World.marks()
	local names = {}
	for name in marks do
		table.insert(names, name)
	end
	if #names == 0 then
		return nil
	end
	local planned = plan[brain.fighter.team]
	if not brain.goal and planned and marks[planned] and math.random() < 0.75 then
		return marks[planned]
	end
	return marks[names[math.random(#names)]]
end

local function navigate(brain: Brain, humanoid: Humanoid, position: Vector3, now: number)
	humanoid.AutoRotate = true
	if not brain.waypoints or now > brain.goalUntil then
		local goal = pickGoal(brain)
		if not goal then
			return
		end
		brain.goal = goal
		brain.goalUntil = now + 35
		brain.index = 2
		brain.lastPosition = position
		brain.lastProgress = now
		brain.waypoints = computePath(position, goal) or {}
		return
	end
	local waypoint = brain.waypoints[brain.index]
	if not waypoint then
		-- Путь пройден или не найден: идём напрямик и вскоре выбираем новую цель
		if brain.goal and #brain.waypoints == 0 then
			humanoid:MoveTo(brain.goal)
			brain.goalUntil = math.min(brain.goalUntil, now + 3)
		else
			brain.waypoints = nil
		end
		return
	end
	local target = waypoint.Position
	if Vector3.new(target.X - position.X, 0, target.Z - position.Z).Magnitude < 3 then
		brain.index += 1
		return
	end
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end
	humanoid:MoveTo(target)
	if (position - brain.lastPosition).Magnitude > 1.5 then
		brain.lastPosition = position
		brain.lastProgress = now
	elseif now - brain.lastProgress > 2 then
		-- Застрял: подпрыгнуть и построить путь заново
		humanoid.Jump = true
		brain.waypoints = nil
	end
end

local function fight(brain: Brain, humanoid: Humanoid, root: BasePart, eye: Vector3, point: Vector3, now: number)
	local fighter = brain.fighter
	local position = root.CFrame.Position
	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
	if not brain.seenSince then
		brain.seenSince = now
		brain.reaction = range(Config.Bots.reaction)
	end

	local weapon = Weapons.get(fighter.equipped)
	if weapon and now - (brain.seenSince :: number) >= brain.reaction and now >= brain.nextShot then
		local distance = (point - eye).Magnitude
		local spread = math.rad(Config.Bots.aimError) * (1 + distance / 150)
		local aim = CFrame.lookAt(eye, point) * CFrame.Angles((math.random() - 0.5) * 2 * spread, (math.random() - 0.5) * 2 * spread, 0)
		Combat.botFire(fighter, eye + aim.LookVector * distance)
		brain.burst += 1
		local pause = 60 / weapon.rpm * (if weapon.auto then 1.7 else 1.3)
		if brain.burst >= 5 then
			brain.burst = 0
			pause += 0.5 + math.random() * 0.5
		end
		brain.nextShot = now + pause
	end

	if now >= brain.nextStrafe then
		brain.nextStrafe = now + 0.7 + math.random() * 0.6
		local side = root.CFrame.RightVector * (math.random() - 0.5) * 12
		humanoid:MoveTo(position + side)
	end
	brain.waypoints = nil
end

local function think(brain: Brain)
	local fighter = brain.fighter
	local humanoid, root = fighter.humanoid, fighter.root
	if not humanoid or not root then
		return
	end
	local now = os.clock()
	local eye = Combat.headPosition(fighter) or root.CFrame.Position
	local target, point
	if now >= fighter.blindUntil then
		target, point = findTarget(fighter, eye, root.CFrame.LookVector)
	end
	if target and point then
		fight(brain, humanoid, root, eye, point, now)
	else
		brain.seenSince = nil
		navigate(brain, humanoid, root.CFrame.Position, now)
	end
end

-- Запускает ботов в начале боя; каждый думает в своём потоке до конца раунда
function Bots.start()
	plan.T = if math.random() < 0.5 then "ASite" else "BSite"
	plan.CT = if math.random() < 0.5 then "ASite" else "BSite"
	local round = State.round
	for _, fighter in Fighters.list do
		local root = fighter.root
		if not fighter.player and fighter.alive and root then
			local brain: Brain = {
				fighter = fighter,
				goal = nil,
				goalUntil = 0,
				waypoints = nil,
				index = 1,
				lastPosition = root.CFrame.Position,
				lastProgress = os.clock(),
				seenSince = nil,
				reaction = 0.5,
				nextShot = 0,
				nextStrafe = 0,
				burst = 0,
			}
			brains[fighter] = brain
			task.spawn(function()
				task.wait(math.random() * 0.5)
				while fighter.alive and brains[fighter] == brain and State.isLive() and State.round == round do
					think(brain)
					task.wait(THINK_INTERVAL)
				end
			end)
		end
	end
end

return Bots
