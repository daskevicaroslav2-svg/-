--!strict
-- Данные игрока: leaderstats и сохранение прогресса в DataStore.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type Profile = {
	cash: IntValue,
	rebirths: IntValue,
	items: { [string]: boolean }, -- купленные предметы
	canSave: boolean, -- false, если загрузка не удалась: старое сохранение не затираем
	released: boolean,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local activeSaves = 0

-- У файла, открытого с диска, GameId равен 0 и DataStore недоступен: играем без сохранения
local store: DataStore? = nil
if game.GameId == 0 then
	print("[Tycoon] Игра не опубликована, прогресс не сохраняется.")
else
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Tycoon] DataStore недоступен, прогресс не сохраняется:", result)
	end
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function load(player: Player): (boolean, any)
	-- В Studio без доступа к API запрос падает сразу, повторы только задержат вход
	local attempts = if RunService:IsStudio() then 1 else 3
	for attempt = 1, attempts do
		local current = store
		if not current then
			return false, nil
		end
		local ok, result = pcall(function()
			return current:GetAsync(keyFor(player))
		end)
		if ok then
			return true, result
		end
		warn(`[Tycoon] Не удалось загрузить данные {player.Name}: {result}`)
		if attempt < attempts then
			task.wait(2)
		end
	end
	if RunService:IsStudio() then
		store = nil
		warn("[Tycoon] Сохранение отключено. Опубликуй игру и включи Enable Studio Access to API Services (Game Settings → Security).")
	end
	return false, nil
end

-- Создаёт leaderstats и загружает сохранение. Возвращает nil, если игрок вышел во время загрузки.
function PlayerData.setup(player: Player): Profile?
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = Config.CashStat
	cash.Value = Config.StartingCash
	cash.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = Config.RebirthStat
	rebirths.Value = 0
	rebirths.Parent = leaderstats
	leaderstats.Parent = player

	local loaded, data = load(player)
	if player.Parent ~= Players then
		return nil
	end

	local profile: Profile = {
		cash = cash,
		rebirths = rebirths,
		items = {},
		canSave = loaded,
		released = false,
	}
	if typeof(data) == "table" then
		if typeof(data.cash) == "number" then
			cash.Value = data.cash
		end
		if typeof(data.rebirths) == "number" then
			rebirths.Value = data.rebirths
		end
		if typeof(data.items) == "table" then
			for _, name in data.items do
				if typeof(name) == "string" then
					profile.items[name] = true
				end
			end
		end
	end
	profiles[player] = profile
	return profile
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.save(player: Player)
	local profile = profiles[player]
	local current = store
	if not profile or not profile.canSave or not current then
		return
	end
	local items = {}
	for name in profile.items do
		table.insert(items, name)
	end
	local data = {
		cash = profile.cash.Value,
		rebirths = profile.rebirths.Value,
		items = items,
	}
	activeSaves += 1
	local ok, err = pcall(function()
		current:SetAsync(keyFor(player), data, { player.UserId })
	end)
	activeSaves -= 1
	if not ok then
		warn(`[Tycoon] Не удалось сохранить данные {player.Name}: {err}`)
	end
end

-- Сохраняет и забывает игрока при выходе
function PlayerData.release(player: Player)
	local profile = profiles[player]
	if not profile or profile.released then
		return
	end
	profile.released = true
	PlayerData.save(player)
	profiles[player] = nil
end

function PlayerData.waitForSaves()
	while activeSaves > 0 do
		task.wait(0.1)
	end
end

return PlayerData
