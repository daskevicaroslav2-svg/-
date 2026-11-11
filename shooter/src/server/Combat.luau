--!strict
-- Бой: проверка выстрелов игроков, урон, броня, убийства и награды.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Fighters = require(script.Parent.Fighters)
local Loadout = require(script.Parent.Loadout)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

type Fighter = Fighters.Fighter

local Combat = {}

-- Вызывается после каждой смерти: (погибший, убийца)
Combat.onKill = nil :: ((Fighter, Fighter?) -> ())?

local HEAD_MULTIPLIER = 4
local LEG_MULTIPLIER = 0.75
local RANGE_STEP = 35 -- studs, на которых урон умножается на rangeMod
local MAX_ORIGIN_OFFSET = 12 -- допуск на задержку сети для точки выстрела
local MAX_HIT_OFFSET = 10 -- и для положения цели

local function isVector(value: any): boolean
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
end

local function partMultiplier(part: Instance): (number, boolean)
	if part.Name == "Head" then
		return HEAD_MULTIPLIER, true
	elseif part.Name == "Left Leg" or part.Name == "Right Leg" then
		return LEG_MULTIPLIER, false
	end
	return 1, false
end

local function headPosition(fighter: Fighter): Vector3?
	local model = fighter.model
	local head = model and model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.CFrame.Position
	end
	return if fighter.root then fighter.root.CFrame.Position else nil
end

Combat.headPosition = headPosition

-- Наносит урон с учётом брони. Своих ранить нельзя, себя — можно (гранаты).
function Combat.hurt(victim: Fighter, amount: number, attacker: Fighter?, weaponId: string, headshot: boolean)
	local humanoid = victim.humanoid
	if not victim.alive or not humanoid or amount <= 0 then
		return
	end
	if attacker and attacker ~= victim and attacker.team == victim.team then
		return
	end
	if victim.armor > 0 then
		local weapon = Weapons.get(weaponId)
		local absorbed = amount * (1 - (if weapon then weapon.armorPen else 0.5))
		amount -= absorbed
		victim.armor = math.max(0, victim.armor - absorbed * Config.ArmorWear)
	end
	amount = math.max(1, math.floor(amount + 0.5))
	victim.lastHit = { by = attacker, weapon = weaponId, headshot = headshot, at = os.clock() }
	local killed = humanoid.Health <= amount
	if attacker and attacker.player and attacker ~= victim then
		Net.sendTo(attacker.player, "Hit", amount, headshot, killed)
	end
	if victim.player then
		local from = attacker and attacker.root
		Net.sendTo(victim.player, "Hurt", amount, if from then from.CFrame.Position else nil)
	end
	humanoid:TakeDamage(amount)
	Fighters.sync(victim)
end

-- Смерть персонажа: счёт, награда убийце, лента убийств
function Combat.handleDeath(victim: Fighter)
	if not victim.alive then
		return
	end
	victim.alive = false
	victim.deaths += 1
	victim.keepLoadout = false
	local hit = victim.lastHit
	local killer: Fighter? = nil
	if hit and hit.by and hit.by ~= victim and os.clock() - hit.at < 10 then
		killer = hit.by
	end
	if killer then
		killer.kills += 1
		local weapon = Weapons.get((hit :: Fighters.Hit).weapon)
		Fighters.addMoney(killer, if weapon then weapon.reward else 300)
	end
	Net.broadcast(
		"Kill",
		if killer then killer.name else "",
		if killer then killer.team else "",
		victim.name,
		victim.team,
		if hit then hit.weapon else "",
		if hit then hit.headshot else false
	)
	Fighters.sync(victim)
	if Combat.onKill then
		Combat.onKill(victim, killer)
	end
end

local function damageAt(weapon: Weapons.Weapon, distance: number, part: Instance): (number, boolean)
	local multiplier, headshot = partMultiplier(part)
	return weapon.damage * weapon.rangeMod ^ (distance / RANGE_STEP) * multiplier, headshot
end

-- Выстрел игрока. Попадание считает клиент, сервер проверяет правдоподобие:
-- темп стрельбы, патроны, откуда стреляли, далеко ли цель от заявленной точки и нет ли стены.
function Combat.fire(fighter: Fighter, weaponId: any, origin: any, direction: any, hitPart: any, hitPosition: any)
	if typeof(weaponId) ~= "string" or not isVector(origin) or not isVector(direction) then
		return
	end
	local weapon = Weapons.get(weaponId)
	local head = headPosition(fighter)
	if not weapon or weapon.kind ~= "gun" or not head then
		return
	end
	if not fighter.alive or not State.isLive() or fighter.equipped ~= weaponId then
		return
	end
	local now = os.clock()
	if now - fighter.lastFire < 60 / weapon.rpm * 0.8 or (origin - head).Magnitude > MAX_ORIGIN_OFFSET then
		return
	end
	if direction.Magnitude < 0.5 or not Loadout.consume(fighter, weaponId) then
		return
	end
	fighter.lastFire = now
	direction = direction.Unit

	local target: Fighter? = nil
	if typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and isVector(hitPosition) then
		target = Fighters.ofPart(hitPart)
	end
	local endPosition = if isVector(hitPosition) then hitPosition else origin + direction * 300
	Net.broadcast("Shot", fighter.model, weaponId, endPosition)

	if not target or target == fighter or not target.alive then
		return
	end
	local offset = hitPosition - origin
	if (hitPart.CFrame.Position - hitPosition).Magnitude > MAX_HIT_OFFSET then
		return
	end
	if offset.Magnitude > 1 and offset.Unit:Dot(direction) < 0.95 then
		return
	end
	if World.blocked(origin, hitPosition) then
		return
	end
	local damage, headshot = damageAt(weapon, offset.Magnitude, hitPart)
	Combat.hurt(target, damage, fighter, weaponId, headshot)
end

-- Выстрел бота: луч считает сервер
function Combat.botFire(bot: Fighter, aim: Vector3)
	local weapon = Weapons.get(bot.equipped)
	local origin = headPosition(bot)
	if not weapon or weapon.kind ~= "gun" or not origin or not bot.model then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.model, World.effects, World.smokes }
	local direction = (aim - origin).Unit
	local result = Workspace:Raycast(origin, direction * 600, params)
	Net.broadcast("Shot", bot.model, weapon.id, if result then result.Position else origin + direction * 300)
	if not result then
		return
	end
	local target = Fighters.ofPart(result.Instance)
	if target and target.alive then
		local damage, headshot = damageAt(weapon, result.Distance, result.Instance)
		Combat.hurt(target, damage * Config.Bots.damageScale, bot, weapon.id, headshot)
	end
end

-- Удар ножом: цель должна быть рядом; удар в спину сильнее
function Combat.knife(fighter: Fighter, heavy: any, hitPart: any)
	local root = fighter.root
	if not fighter.alive or not root or not State.isLive() or fighter.equipped ~= "Knife" then
		return
	end
	local attack = if heavy == true then Weapons.Knife.stab else Weapons.Knife.slash
	local now = os.clock()
	if now - fighter.lastAttack < attack.time * 0.8 then
		return
	end
	fighter.lastAttack = now
	Net.broadcast("Swing", fighter.model, heavy == true)
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then
		return
	end
	local target = Fighters.ofPart(hitPart)
	local targetRoot = target and target.root
	if not target or not targetRoot or target == fighter or not target.alive then
		return
	end
	local offset = targetRoot.CFrame.Position - root.CFrame.Position
	if offset.Magnitude > Weapons.Knife.range + 4 or World.blocked(root.CFrame.Position, targetRoot.CFrame.Position) then
		return
	end
	local fromBehind = offset.Magnitude > 0.1 and targetRoot.CFrame.LookVector:Dot(offset.Unit) > 0.45
	Combat.hurt(target, if fromBehind then attack.back else attack.damage, fighter, "Knife", false)
end

-- Урон по области (гранаты): amount(расстояние) возвращает урон, стены защищают
function Combat.blast(center: Vector3, radius: number, attacker: Fighter?, weaponId: string, amount: (number) -> number)
	for _, fighter in Fighters.list do
		local root = fighter.root
		if fighter.alive and root then
			local position = root.CFrame.Position
			local distance = (position - center).Magnitude
			if distance <= radius and not World.blocked(center, position) then
				Combat.hurt(fighter, amount(distance), attacker, weaponId, false)
			end
		end
	end
end

return Combat
