--!strict
-- Точка входа сервера шутера: группы столкновений, игроки, сетевые сообщения, запуск матча.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Characters = require(script.Parent.Characters)
local Combat = require(script.Parent.Combat)
local Fighters = require(script.Parent.Fighters)
local Grenades = require(script.Parent.Grenades)
local Loadout = require(script.Parent.Loadout)
local Round = require(script.Parent.Round)
local Store = require(script.Parent.Store)

-- Бойцы не толкают друг друга, гранаты пролетают сквозь бойцов
PhysicsService:RegisterCollisionGroup("Fighters")
PhysicsService:RegisterCollisionGroup("Grenades")
PhysicsService:CollisionGroupSetCollidable("Fighters", "Fighters", false)
PhysicsService:CollisionGroupSetCollidable("Fighters", "Grenades", false)

Characters.onDied = Combat.handleDeath

local function onPlayerAdded(player: Player)
	player:SetAttribute("Team", "")
	player:SetAttribute("Alive", false)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Убийства", "Смерти" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
	Store.load(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(Store.release)
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(Store.save, player)
	end
	task.wait(1)
end)

-- Сообщение от игрока передаётся обработчику вместе с его бойцом
local function forFighter(handler: (Fighters.Fighter, ...any) -> ...any): (Player, ...any) -> ()
	return function(player: Player, ...: any)
		local fighter = Fighters.ofPlayer(player)
		if fighter then
			handler(fighter, ...)
		end
	end
end

Net.on("Team", Round.chooseTeam)
Net.on("Skin", Store.setSkin)
Net.on("KnifeType", Store.setKnife)
Net.on("Buy", forFighter(Loadout.buy))
Net.on("Reload", forFighter(Loadout.reload))
Net.on("Fire", forFighter(Combat.fire))
Net.on("Knife", forFighter(Combat.knife))
Net.on("Throw", forFighter(Grenades.throw))
Net.on("Equip", forFighter(function(fighter, weaponId)
	if typeof(weaponId) == "string" and fighter.alive then
		Loadout.equip(fighter, weaponId)
	end
end))

task.spawn(Round.run)
