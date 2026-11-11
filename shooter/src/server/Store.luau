--!strict
-- Выбранные игроком нож и скины: хранение в DataStore и изменение по запросу клиента.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arsenal = require(Shared.Arsenal)
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Characters = require(script.Parent.Characters)
local Fighters = require(script.Parent.Fighters)

type Prefs = Fighters.Prefs

local Store = {}

local cache: { [Player]: Prefs } = {}
local canSave: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

-- У файла, открытого с диска, GameId равен 0 и DataStore недоступен
local store: DataStore? = nil
if game.GameId ~= 0 then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Shooter] DataStore недоступен, выбор скинов не сохраняется:", result)
	end
end

local function defaults(): Prefs
	return { knife = "Classic", skins = {} }
end

function Store.prefs(player: Player): Prefs
	local prefs = cache[player]
	if not prefs then
		prefs = defaults()
		cache[player] = prefs
	end
	return prefs
end

-- Загружает сохранённый выбор. Чужие или устаревшие значения отбрасываются.
function Store.load(player: Player)
	local prefs = Store.prefs(player)
	Fighters.syncPrefs(player, prefs)
	local current = store
	if not current then
		return
	end
	local ok, data = pcall(function()
		return current:GetAsync("Player_" .. player.UserId)
	end)
	if not ok then
		warn(`[Shooter] Не удалось загрузить скины {player.Name}: {data}`)
		return
	end
	canSave[player] = true
	if typeof(data) == "table" then
		if typeof(data.knife) == "string" and Arsenal.isKnife(data.knife) then
			prefs.knife = data.knife
		end
		if typeof(data.skins) == "table" then
			for key, skinId in data.skins do
				local modelId = if key == "Knife" then prefs.knife else key
				if typeof(key) == "string" and typeof(skinId) == "string" and Arsenal.skin(modelId, skinId) then
					prefs.skins[key] = skinId
				end
			end
		end
	end
	if player.Parent == Players then
		Fighters.syncPrefs(player, prefs)
	end
end

function Store.save(player: Player)
	local current = store
	if not current or not canSave[player] or not dirty[player] then
		return
	end
	dirty[player] = nil
	local prefs = Store.prefs(player)
	local ok, err = pcall(function()
		current:SetAsync("Player_" .. player.UserId, { knife = prefs.knife, skins = prefs.skins }, { player.UserId })
	end)
	if not ok then
		warn(`[Shooter] Не удалось сохранить скины {player.Name}: {err}`)
	end
end

function Store.release(player: Player)
	Store.save(player)
	cache[player] = nil
	canSave[player] = nil
	dirty[player] = nil
end

local function changed(player: Player)
	dirty[player] = true
	Fighters.syncPrefs(player, Store.prefs(player))
	local fighter = Fighters.ofPlayer(player)
	if fighter and fighter.alive then
		Characters.holdWeapon(fighter)
	end
end

-- Скин оружия: key — id оружия или "Knife" (один скин на любой нож)
function Store.setSkin(player: Player, key: any, skinId: any)
	if typeof(key) ~= "string" or typeof(skinId) ~= "string" then
		return
	end
	local prefs = Store.prefs(player)
	local weapon = Weapons.get(key)
	if not weapon or weapon.kind == "grenade" then
		return
	end
	if Arsenal.skin(Weapons.modelId(key, prefs.knife), skinId) then
		prefs.skins[key] = skinId
		changed(player)
	end
end

function Store.setKnife(player: Player, knifeId: any)
	if typeof(knifeId) == "string" and Arsenal.isKnife(knifeId) then
		Store.prefs(player).knife = knifeId
		changed(player)
	end
end

return Store
