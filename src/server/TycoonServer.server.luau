--!strict
-- Точка входа сервера: запускает заводы, встречает игроков, сохраняет прогресс.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlayerData = require(script.PlayerData)
local Tycoon = require(script.Tycoon)

-- Руда проходит сквозь игроков и другую руду, поэтому лента не забивается
PhysicsService:RegisterCollisionGroup("Ore")
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:CollisionGroupSetCollidable("Ore", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Ore", "Ore", false)

for _, model in Workspace:WaitForChild("Tycoons"):GetChildren() do
	if model:IsA("Model") then
		local ok, err = pcall(Tycoon.new, model)
		if not ok then
			warn(`[Tycoon] {model.Name} не запущен: {err}`)
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local function setGroup(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(setGroup)
	for _, descendant in character:GetDescendants() do
		setGroup(descendant)
	end

	-- Владелец завода появляется у себя, а не в лобби
	local tycoon = Tycoon.ownedBy(player)
	if not tycoon then
		return
	end
	while not character:IsDescendantOf(Workspace) do
		character.AncestryChanged:Wait()
		if character.Parent == nil then
			return
		end
	end
	task.wait(0.1) -- движок сначала сам ставит персонажа на SpawnLocation
	if character:IsDescendantOf(Workspace) then
		character:PivotTo(tycoon.spawnCFrame)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	PlayerData.setup(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	Tycoon.release(player)
	PlayerData.release(player)
end)

task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			PlayerData.save(player)
		end
	end
end)

-- При остановке сервера PlayerRemoving может не успеть: сохраняем всех здесь
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			Tycoon.release(player)
			PlayerData.release(player)
		end)
	end
	PlayerData.waitForSaves()
end)
