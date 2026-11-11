--!strict
-- Характеристики оружия, ножа, гранат и снаряжения. Урон и цены близки к CS2.
-- Разброс и отдача заданы в градусах, скорость — в studs в секунду.

local Arsenal = require(script.Parent.Arsenal)

export type Weapon = {
	id: string,
	name: string,
	kind: string, -- gun, knife, grenade
	category: string, -- раздел магазина
	slot: number, -- 1 основное, 2 пистолет, 3 нож, 4 гранаты
	price: number,
	team: string?, -- доступно только этой команде
	reward: number, -- деньги за убийство
	speed: number,
	-- оружие
	damage: number,
	armorPen: number, -- доля урона, проходящая сквозь броню
	rangeMod: number, -- множитель урона на каждые 35 studs
	rpm: number,
	auto: boolean,
	mag: number,
	reserve: number,
	reloadTime: number, -- запасное значение: в игре берётся длительность анимации reload
	spread: number,
	moveSpread: number, -- прибавка к разбросу на полной скорости
	sprayStep: number, -- прибавка к разбросу за выстрел очереди
	sprayMax: number,
	recoil: number, -- подброс камеры за выстрел
	scopeFov: number?, -- поле зрения в прицеле; без прицела оружие неточное
	heavy: boolean?, -- громкий звук выстрела
	-- гранаты
	fuse: number,
	carry: number, -- сколько штук можно нести
}

local Weapons = {}

Weapons.list = {} :: { Weapon }
local byId: { [string]: Weapon } = {}

local function add(weapon: Weapon)
	table.insert(Weapons.list, weapon)
	byId[weapon.id] = weapon
end

local function gun(spec: { [string]: any })
	add({
		id = spec.id, name = spec.name, kind = "gun", category = spec.category, slot = spec.slot,
		price = spec.price, team = spec.team, reward = spec.reward or 300, speed = spec.speed,
		damage = spec.damage, armorPen = spec.armorPen, rangeMod = spec.rangeMod, rpm = spec.rpm,
		auto = spec.auto or false, mag = spec.mag, reserve = spec.reserve, reloadTime = spec.reloadTime,
		spread = spec.spread, moveSpread = spec.moveSpread, sprayStep = spec.sprayStep or 0,
		sprayMax = spec.sprayMax or 0, recoil = spec.recoil, scopeFov = spec.scopeFov, heavy = spec.heavy,
		fuse = 0, carry = 0,
	})
end

local function grenade(id: string, name: string, price: number, fuse: number, carry: number)
	add({
		id = id, name = name, kind = "grenade", category = "grenade", slot = 4, price = price, team = nil,
		reward = 300, speed = 19.5, damage = 0, armorPen = 0.5, rangeMod = 1, rpm = 60, auto = false,
		mag = 1, reserve = 0, reloadTime = 0, spread = 0, moveSpread = 0, sprayStep = 0, sprayMax = 0,
		recoil = 0, fuse = fuse, carry = carry,
	})
end

gun({ id = "Glock", name = "Glock-18", category = "pistol", slot = 2, price = 200, team = "T", speed = 19.2,
	damage = 30, armorPen = 0.47, rangeMod = 0.85, rpm = 400, mag = 20, reserve = 120, reloadTime = 2.2,
	spread = 0.55, moveSpread = 1.2, sprayStep = 0.25, sprayMax = 2.5, recoil = 1.1 })
gun({ id = "USP", name = "USP-S", category = "pistol", slot = 2, price = 200, team = "CT", speed = 19.2,
	damage = 35, armorPen = 0.505, rangeMod = 0.91, rpm = 352, mag = 12, reserve = 24, reloadTime = 2.2,
	spread = 0.4, moveSpread = 1.2, sprayStep = 0.25, sprayMax = 2.5, recoil = 1.0 })
gun({ id = "Deagle", name = "Desert Eagle", category = "pistol", slot = 2, price = 700, speed = 18.4,
	damage = 53, armorPen = 0.932, rangeMod = 0.85, rpm = 267, mag = 7, reserve = 35, reloadTime = 2.2,
	spread = 0.45, moveSpread = 3, sprayStep = 1.6, sprayMax = 6, recoil = 3.4, heavy = true })
gun({ id = "MP9", name = "MP9", category = "smg", slot = 1, price = 1250, reward = 600, speed = 19.2,
	damage = 26, armorPen = 0.6, rangeMod = 0.87, rpm = 857, auto = true, mag = 30, reserve = 120, reloadTime = 2.1,
	spread = 0.9, moveSpread = 1.3, sprayStep = 0.22, sprayMax = 3.2, recoil = 0.55 })
gun({ id = "AK47", name = "АК-47", category = "rifle", slot = 1, price = 2700, team = "T", speed = 17.2,
	damage = 36, armorPen = 0.775, rangeMod = 0.98, rpm = 600, auto = true, mag = 30, reserve = 90, reloadTime = 2.4,
	spread = 0.35, moveSpread = 4.5, sprayStep = 0.5, sprayMax = 4.2, recoil = 1.0, heavy = true })
gun({ id = "M4A4", name = "M4A4", category = "rifle", slot = 1, price = 2900, team = "CT", speed = 18,
	damage = 33, armorPen = 0.7, rangeMod = 0.97, rpm = 666, auto = true, mag = 30, reserve = 90, reloadTime = 3.1,
	spread = 0.3, moveSpread = 4.2, sprayStep = 0.42, sprayMax = 3.8, recoil = 0.85 })
gun({ id = "AWP", name = "AWP", category = "sniper", slot = 1, price = 4750, reward = 100, speed = 16,
	damage = 115, armorPen = 0.975, rangeMod = 0.99, rpm = 41, mag = 5, reserve = 30, reloadTime = 3.6,
	spread = 0.03, moveSpread = 7, recoil = 2.6, scopeFov = 22, heavy = true })

add({
	id = "Knife", name = "Нож", kind = "knife", category = "knife", slot = 3, price = 0, team = nil,
	reward = 1500, speed = 20, damage = 40, armorPen = 0.85, rangeMod = 1, rpm = 150, auto = true,
	mag = 0, reserve = 0, reloadTime = 0, spread = 0, moveSpread = 0, sprayStep = 0, sprayMax = 0,
	recoil = 0, fuse = 0, carry = 0,
})

grenade("HE", "Осколочная", 300, 1.8, 1)
grenade("Flash", "Световая", 200, 1.6, 2)
grenade("Smoke", "Дымовая", 300, 2.2, 1)
grenade("Molotov", "Коктейль Молотова", 400, 2, 1)

-- Параметры ножа: обычный и сильный удар, урон в спину
Weapons.Knife = {
	range = 6.5,
	slash = { damage = 40, back = 90, time = 0.4, hit = 0.14 },
	stab = { damage = 65, back = 180, time = 0.9, hit = 0.3 },
}

-- Параметры гранат
Weapons.Grenades = {
	throwSpeed = 72,
	throwTime = 0.3, -- момент броска внутри анимации throw
	HE = { damage = 98, radius = 26 },
	Flash = { duration = 4.5, radius = 90 },
	Smoke = { duration = 15, radius = 11 },
	Molotov = { duration = 7, radius = 9, damage = 12, tick = 0.3 },
}

function Weapons.get(id: string): Weapon?
	return byId[id]
end

function Weapons.defaultPistol(team: string): string
	return if team == "CT" then "USP" else "Glock"
end

-- Какую модель показывать для оружия: у ножа это выбранный игроком тип
function Weapons.modelId(weaponId: string, knife: string): string
	return if weaponId == "Knife" then knife else weaponId
end

local function duration(modelId: string, animation: string, fallback: number): number
	local track = Arsenal.animation(modelId, animation)
	return if track then track.duration else fallback
end

function Weapons.reloadTime(weapon: Weapon): number
	return duration(weapon.id, "reload", weapon.reloadTime)
end

function Weapons.equipTime(modelId: string): number
	return duration(modelId, "equip", 0.5)
end

return Weapons
