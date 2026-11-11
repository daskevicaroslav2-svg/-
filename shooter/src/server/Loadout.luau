--!strict
-- Снаряжение бойца: стартовый набор, покупки, патроны, смена оружия в руках.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Characters = require(script.Parent.Characters)
local Fighters = require(script.Parent.Fighters)
local State = require(script.Parent.State)

type Fighter = Fighters.Fighter

local Loadout = {}

local function fill(fighter: Fighter, weaponId: string)
	local weapon = Weapons.get(weaponId)
	if weapon and weapon.kind == "gun" then
		fighter.ammo[weaponId] = { mag = weapon.mag, reserve = weapon.reserve }
	end
end

-- Клиент ведёт свой счёт патронов; сервер присылает точные значения после изменений
function Loadout.sendAmmo(fighter: Fighter)
	if fighter.player then
		Net.sendTo(fighter.player, "Ammo", fighter.ammo)
	end
end

function Loadout.owns(fighter: Fighter, weaponId: string): boolean
	return weaponId == "Knife"
		or fighter.primary == weaponId
		or fighter.secondary == weaponId
		or table.find(fighter.grenades, weaponId) ~= nil
end

-- Лучшее из имеющегося: основное, пистолет или нож
function Loadout.best(fighter: Fighter): string
	return fighter.primary or fighter.secondary or "Knife"
end

function Loadout.equip(fighter: Fighter, weaponId: string)
	if not Loadout.owns(fighter, weaponId) then
		return
	end
	fighter.equipped = weaponId
	Fighters.sync(fighter)
	Characters.holdWeapon(fighter)
end

-- Стартовый набор: нож и пистолет команды
function Loadout.reset(fighter: Fighter)
	fighter.primary = nil
	fighter.secondary = Weapons.defaultPistol(fighter.team)
	fighter.grenades = {}
	fighter.armor = 0
	fighter.ammo = {}
	fill(fighter, fighter.secondary :: string)
	fighter.equipped = fighter.secondary :: string
end

-- Начало раунда: выжившие сохраняют оружие, патроны пополняются у всех
function Loadout.prepare(fighter: Fighter)
	if not fighter.keepLoadout or not fighter.secondary and not fighter.primary then
		Loadout.reset(fighter)
	end
	for weaponId in fighter.ammo do
		fill(fighter, weaponId)
	end
	fighter.equipped = Loadout.best(fighter)
	fighter.keepLoadout = true
	Fighters.sync(fighter)
	Loadout.sendAmmo(fighter)
	Characters.holdWeapon(fighter)
end

local function deny(fighter: Fighter, reason: string): boolean
	if fighter.player then
		Net.sendTo(fighter.player, "BuyResult", false, reason)
	end
	return false
end

function Loadout.buy(fighter: Fighter, itemId: any): boolean
	if typeof(itemId) ~= "string" or not fighter.alive then
		return false
	end
	if not State.canBuy() then
		return deny(fighter, Config.Text.ShopClosed)
	end

	if itemId == "Armor" then
		if fighter.armor >= 100 then
			return deny(fighter, Config.Text.Owned)
		elseif fighter.money < Config.ArmorPrice then
			return deny(fighter, Config.Text.NoMoney)
		end
		fighter.armor = 100
		Fighters.addMoney(fighter, -Config.ArmorPrice)
		if fighter.player then
			Net.sendTo(fighter.player, "BuyResult", true, Config.Text.Armor)
		end
		return true
	end

	local weapon = Weapons.get(itemId)
	if not weapon or weapon.kind == "knife" then
		return false
	elseif weapon.team and weapon.team ~= fighter.team then
		return deny(fighter, Config.Text.WrongTeam)
	elseif fighter.money < weapon.price then
		return deny(fighter, Config.Text.NoMoney)
	end

	if weapon.kind == "grenade" then
		local same = 0
		for _, id in fighter.grenades do
			if id == itemId then
				same += 1
			end
		end
		if same >= weapon.carry or #fighter.grenades >= Config.MaxGrenades then
			return deny(fighter, Config.Text.Full)
		end
		table.insert(fighter.grenades, itemId)
		Fighters.addMoney(fighter, -weapon.price)
	else
		if fighter.primary == itemId or fighter.secondary == itemId then
			return deny(fighter, Config.Text.Owned)
		end
		local replaced = if weapon.slot == 1 then fighter.primary else fighter.secondary
		if replaced then
			fighter.ammo[replaced] = nil
		end
		if weapon.slot == 1 then
			fighter.primary = itemId
		else
			fighter.secondary = itemId
		end
		fill(fighter, itemId)
		fighter.money -= weapon.price
		Loadout.sendAmmo(fighter)
		Loadout.equip(fighter, itemId)
	end
	if fighter.player then
		Net.sendTo(fighter.player, "BuyResult", true, weapon.name)
	end
	return true
end

-- Списывает патрон. false — магазин пуст.
function Loadout.consume(fighter: Fighter, weaponId: string): boolean
	local ammo = fighter.ammo[weaponId]
	if not ammo or ammo.mag <= 0 then
		return false
	end
	ammo.mag -= 1
	return true
end

function Loadout.reload(fighter: Fighter, weaponId: any)
	if typeof(weaponId) ~= "string" or not fighter.alive then
		return
	end
	local weapon = Weapons.get(weaponId)
	local ammo = fighter.ammo[weaponId]
	local now = os.clock()
	-- Перезарядка не может идти быстрее анимации
	if not weapon or not ammo or now - fighter.lastReload < Weapons.reloadTime(weapon) * 0.8 then
		Loadout.sendAmmo(fighter)
		return
	end
	fighter.lastReload = now
	local moved = math.min(weapon.mag - ammo.mag, ammo.reserve)
	ammo.mag += moved
	ammo.reserve -= moved
	Loadout.sendAmmo(fighter)
end

-- Забирает гранату из инвентаря перед броском
function Loadout.takeGrenade(fighter: Fighter, grenadeId: string): boolean
	local index = table.find(fighter.grenades, grenadeId)
	if not index then
		return false
	end
	table.remove(fighter.grenades, index)
	if fighter.equipped == grenadeId and not table.find(fighter.grenades, grenadeId) then
		fighter.equipped = Loadout.best(fighter)
		Characters.holdWeapon(fighter)
	end
	Fighters.sync(fighter)
	return true
end

return Loadout
