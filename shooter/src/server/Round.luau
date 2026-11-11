--!strict
-- Ход матча: выбор команды, раунды, победы, деньги и смена карты.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Bots = require(script.Parent.Bots)
local Characters = require(script.Parent.Characters)
local Fighters = require(script.Parent.Fighters)
local Loadout = require(script.Parent.Loadout)
local State = require(script.Parent.State)
local Store = require(script.Parent.Store)
local World = require(script.Parent.World)

type Fighter = Fighters.Fighter

local Round = {}

local mapIndex = 0

local function makeTeam(name: string, color: string): Team
	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = BrickColor.new(color)
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

local teams: { [string]: Team } = {
	T = makeTeam(Config.Text.TeamT, "Bright orange"),
	CT = makeTeam(Config.Text.TeamCT, "Bright blue"),
}

local function publishAlive()
	State.setAlive(Fighters.aliveCount("T"), Fighters.aliveCount("CT"))
end

local function shuffled(list: { CFrame }): { CFrame }
	for index = #list, 2, -1 do
		local other = math.random(index)
		list[index], list[other] = list[other], list[index]
	end
	return list
end

local function spawnFighter(fighter: Fighter, cf: CFrame)
	if fighter.player then
		if Characters.spawnPlayer(fighter, cf) then
			Loadout.prepare(fighter)
		end
	else
		Characters.remove(fighter)
		if Characters.spawnBot(fighter, cf) then
			Bots.arm(fighter)
		end
	end
end

local function randomSpawn(team: string): CFrame?
	local spawns = World.spawns(team)
	return spawns[math.random(math.max(#spawns, 1))]
end

-- Игрок выбрал сторону: T, CT или Auto (где меньше людей)
function Round.chooseTeam(player: Player, choice: any)
	if choice ~= "T" and choice ~= "CT" and choice ~= "Auto" then
		return
	end
	local team: string = choice
	if choice == "Auto" then
		team = if Fighters.humans("T") <= Fighters.humans("CT") then "T" else "CT"
	end
	local current = Fighters.ofPlayer(player)
	if current and current.team == team then
		return
	end
	if Fighters.humans(team) >= Config.MaxTeamPlayers then
		Net.sendTo(player, "Notice", Config.Text.Full)
		return
	end

	local money = Config.StartMoney
	if current then
		-- Смена стороны посреди раунда: прежний персонаж выбывает
		money = current.money
		Characters.remove(current)
		Fighters.remove(current)
	end
	local fighter = Fighters.create(team, player.DisplayName, player, Store.prefs(player))
	fighter.money = money
	player.Team = teams[team]
	Fighters.sync(fighter)
	if State.phase == "Freeze" then
		local cf = randomSpawn(team)
		if cf then
			spawnFighter(fighter, cf)
		end
	end
end

function Round.playerLeft(player: Player)
	local fighter = Fighters.ofPlayer(player)
	if fighter then
		Characters.remove(fighter)
		Fighters.remove(fighter)
	end
end

local function reward(winner: string)
	for _, fighter in Fighters.list do
		if fighter.team == winner then
			fighter.lossStreak = 0
			Fighters.addMoney(fighter, Config.WinReward)
		else
			fighter.lossStreak += 1
			local bonus = Config.LossStreakBonus * (fighter.lossStreak - 1)
			Fighters.addMoney(fighter, math.min(Config.LossReward + bonus, Config.LossRewardMax))
		end
	end
end

-- Один раунд: закупка, бой до уничтожения команды или конца времени, итог
local function playRound()
	State.round += 1
	World.clear()
	Bots.balance()

	local spawns = { T = shuffled(World.spawns("T")), CT = shuffled(World.spawns("CT")) }
	local pending = 0
	for _, fighter in Fighters.list do
		local list = spawns[fighter.team]
		local cf = table.remove(list) or randomSpawn(fighter.team)
		if cf then
			pending += 1
			task.spawn(function()
				spawnFighter(fighter, cf)
				pending -= 1
			end)
		end
	end
	local deadline = os.clock() + 8
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end

	State.publish()
	State.setBuyTime(Config.FreezeTime + Config.BuyTime)
	State.setPhase("Freeze", Config.FreezeTime)
	publishAlive()
	task.wait(Config.FreezeTime)

	-- Раунд идёт на победу, только если в обеих командах кто-то есть
	local contested = #Fighters.team("T") > 0 and #Fighters.team("CT") > 0
	State.setPhase("Live", Config.RoundTime)
	Bots.start()
	local winner, reason = "", "Time"
	while Fighters.humans() > 0 do
		task.wait(0.2)
		publishAlive()
		local aliveT, aliveCT = Fighters.aliveCount("T"), Fighters.aliveCount("CT")
		if contested and aliveT == 0 then
			winner, reason = "CT", "Kill"
			break
		elseif contested and aliveCT == 0 then
			winner, reason = "T", "Kill"
			break
		elseif State.now() >= State.phaseEnds then
			-- Время вышло: атакующие не справились
			winner = if contested then "CT" else ""
			break
		end
	end

	if winner ~= "" then
		State.score[winner] += 1
		reward(winner)
	end
	State.publish()
	State.setPhase("RoundEnd", Config.RoundEndTime)
	Net.broadcast("RoundEnd", winner, reason)
	task.wait(Config.RoundEndTime)
end

local function playMatch()
	local maps = {}
	for _, name in Config.Maps do
		if World.has(name) then
			table.insert(maps, name)
		end
	end
	assert(#maps > 0, "в Workspace.Maps нет ни одной карты из Config.Maps")
	mapIndex = mapIndex % #maps + 1
	State.map = maps[mapIndex]
	World.setMap(State.map)
	State.round = 0
	State.score.T, State.score.CT = 0, 0
	for _, fighter in Fighters.list do
		fighter.money = Config.StartMoney
		fighter.kills, fighter.deaths, fighter.lossStreak = 0, 0, 0
		fighter.keepLoadout = false
		Fighters.sync(fighter)
	end
	State.publish()

	while Fighters.humans() > 0 do
		playRound()
		if State.score.T >= Config.RoundsToWin or State.score.CT >= Config.RoundsToWin then
			break
		end
	end

	if Fighters.humans() > 0 then
		local winner = if State.score.T > State.score.CT then "T" else "CT"
		State.setPhase("MatchEnd", Config.MatchEndTime)
		Net.broadcast("MatchEnd", winner, maps[mapIndex % #maps + 1])
		task.wait(Config.MatchEndTime)
	end
	-- Между матчами карта пустая
	for _, fighter in Fighters.list do
		Characters.remove(fighter)
		Fighters.sync(fighter)
	end
	Bots.removeAll()
	World.clear()
end

-- Главный цикл: матчи идут, пока в командах есть хотя бы один человек
function Round.run()
	while true do
		State.setPhase("Waiting", 0)
		publishAlive()
		while Fighters.humans() == 0 do
			task.wait(0.5)
		end
		playMatch()
	end
end

Players.PlayerRemoving:Connect(Round.playerLeft)

return Round
