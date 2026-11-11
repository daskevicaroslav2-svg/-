--!strict
-- Гранаты: бросок, полёт и срабатывание — осколочная, световая, дымовая, зажигательная.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Combat = require(script.Parent.Combat)
local Fighters = require(script.Parent.Fighters)
local Loadout = require(script.Parent.Loadout)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

type Fighter = Fighters.Fighter

local Grenades = {}

local COLORS: { [string]: Color3 } = {
	HE = Color3.fromRGB(70, 90, 60),
	Flash = Color3.fromRGB(190, 195, 200),
	Smoke = Color3.fromRGB(60, 80, 60),
	Molotov = Color3.fromRGB(200, 120, 40),
}
local PHYSICS = PhysicalProperties.new(1.5, 0.5, 0.45, 1, 1)
local LIFT = 0.6 -- доля притяжения, которую гасим: граната летит по пологой дуге
local SMOKE_PUFFS: { { offset: Vector3, size: number } } = {
	{ offset = Vector3.new(0, 4, 0), size = 16 },
	{ offset = Vector3.new(5, 3, 0), size = 12 },
	{ offset = Vector3.new(-5, 3, 0), size = 12 },
	{ offset = Vector3.new(0, 3, 5), size = 12 },
	{ offset = Vector3.new(0, 3, -5), size = 12 },
	{ offset = Vector3.new(3, 7, 3), size = 11 },
	{ offset = Vector3.new(-3, 7, -3), size = 11 },
}

local function effectPart(size: Vector3, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function explode(position: Vector3, thrower: Fighter)
	local spec = Weapons.Grenades.HE
	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Position = position
	explosion.Parent = World.effects
	Debris:AddItem(explosion, 3)
	Net.broadcast("Boom", position)
	Combat.blast(position + Vector3.new(0, 1.5, 0), spec.radius, thrower, "HE", function(distance)
		local falloff = 1 - distance / spec.radius
		return spec.damage * falloff * falloff
	end)
end

-- Ослепляет тех, кто видит вспышку: сильнее вблизи и если смотреть прямо на неё
local function flash(position: Vector3)
	local spec = Weapons.Grenades.Flash
	local center = position + Vector3.new(0, 1, 0)
	Net.broadcast("FlashBang", position)
	for _, fighter in Fighters.list do
		local head = Combat.headPosition(fighter)
		local root = fighter.root
		if fighter.alive and head and root then
			local offset = center - head
			local distance = offset.Magnitude
			if distance < spec.radius and not World.blocked(head, center) then
				local facing = if distance > 0.5 then root.CFrame.LookVector:Dot(offset.Unit) else 1
				local angle = if facing > 0.4 then 1 elseif facing > -0.2 then 0.55 else 0.2
				local duration = spec.duration * angle * (1 - 0.6 * distance / spec.radius)
				fighter.blindUntil = math.max(fighter.blindUntil, os.clock() + duration)
				if fighter.player then
					Net.sendTo(fighter.player, "Blind", duration)
				end
			end
		end
	end
end

-- Дым из больших шаров: клиент затемняет экран, когда камера внутри (атрибуты Center и Radius)
local function smoke(position: Vector3)
	local spec = Weapons.Grenades.Smoke
	local cloud = Instance.new("Model")
	cloud.Name = "Smoke"
	cloud:SetAttribute("Center", position + Vector3.new(0, 4, 0))
	cloud:SetAttribute("Radius", spec.radius)
	for _, puff in SMOKE_PUFFS do
		local size = puff.size
		local ball = effectPart(Vector3.new(size, size, size), CFrame.new(position + puff.offset), Color3.fromRGB(200, 200, 206))
		ball.Shape = Enum.PartType.Ball
		ball.Transparency = 0.06
		ball.Parent = cloud
	end
	cloud.Parent = World.smokes
	Debris:AddItem(cloud, spec.duration)
end

-- Огонь на земле: жжёт всех, кто стоит в круге
local function ignite(position: Vector3, thrower: Fighter)
	local spec = Weapons.Grenades.Molotov
	local ground = World.ground(position + Vector3.new(0, 2, 0), 40)
	if not ground then
		return
	end
	local zone = Instance.new("Model")
	zone.Name = "Fire"
	local disc = effectPart(
		Vector3.new(0.2, spec.radius * 2, spec.radius * 2),
		CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 120, 30)
	)
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.55
	disc.CanQuery = false
	disc.Parent = zone
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * spec.radius * (if index % 2 == 0 then 0.35 else 0.75)
		local ember = effectPart(Vector3.new(1, 1, 1), CFrame.new(ground + offset + Vector3.new(0, 0.5, 0)), Color3.new(0, 0, 0))
		ember.Transparency = 1
		ember.CanQuery = false
		local fire = Instance.new("Fire")
		fire.Heat = 9
		fire.Size = 9
		fire.Parent = ember
		ember.Parent = zone
	end
	zone.Parent = World.effects
	Debris:AddItem(zone, spec.duration)
	Net.broadcast("Burn", ground)

	local ends = os.clock() + spec.duration
	while os.clock() < ends and zone.Parent do
		for _, fighter in Fighters.list do
			local root = fighter.root
			if fighter.alive and root then
				local offset = root.CFrame.Position - ground
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= spec.radius and math.abs(offset.Y) < 8 then
					Combat.hurt(fighter, spec.damage, thrower, "Molotov", false)
				end
			end
		end
		task.wait(spec.tick)
	end
end

local function detonate(grenadeId: string, position: Vector3, thrower: Fighter)
	if grenadeId == "HE" then
		explode(position, thrower)
	elseif grenadeId == "Flash" then
		flash(position)
	elseif grenadeId == "Smoke" then
		smoke(position)
	elseif grenadeId == "Molotov" then
		ignite(position, thrower)
	end
end

-- Бросок игрока: сервер создаёт снаряд и ведёт его до срабатывания
function Grenades.throw(fighter: Fighter, grenadeId: any, origin: any, direction: any)
	if typeof(grenadeId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local weapon = Weapons.get(grenadeId)
	local head = Combat.headPosition(fighter)
	if not weapon or weapon.kind ~= "grenade" or not head or not fighter.alive or not State.isLive() then
		return
	end
	if origin ~= origin or (origin - head).Magnitude > 12 or not (direction.Magnitude > 0.5) then
		return
	end
	if not Loadout.takeGrenade(fighter, grenadeId) then
		return
	end

	local ball = Instance.new("Part")
	ball.Name = grenadeId
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.9, 0.9, 0.9)
	ball.Color = COLORS[grenadeId] or COLORS.HE
	ball.Material = Enum.Material.Metal
	ball.TopSurface = Enum.SurfaceType.Smooth
	ball.BottomSurface = Enum.SurfaceType.Smooth
	ball.CustomPhysicalProperties = PHYSICS
	ball.CollisionGroup = "Grenades"
	ball.CFrame = CFrame.new(origin)
	ball.Parent = World.effects
	ball.AssemblyLinearVelocity = direction.Unit * Weapons.Grenades.throwSpeed + Vector3.new(0, 6, 0)
	local attachment = Instance.new("Attachment")
	attachment.Parent = ball
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = attachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, ball:GetMass() * Workspace.Gravity * LIFT, 0)
	lift.Parent = ball
	pcall(function()
		ball:SetNetworkOwner(nil)
	end)

	local round = State.round
	local started = os.clock()
	local landed = false
	if grenadeId == "Molotov" then
		-- Бутылка разбивается о первую же преграду
		ball.Touched:Connect(function(hit)
			if hit:IsDescendantOf(World.effects) or Fighters.ofPart(hit) then
				return
			end
			landed = true
		end)
	end
	while os.clock() - started < weapon.fuse do
		task.wait(0.05)
		local age = os.clock() - started
		if grenadeId == "Molotov" and landed and age > 0.1 then
			break
		elseif grenadeId == "Smoke" and age > 1 and ball.AssemblyLinearVelocity.Magnitude < 3 then
			break
		end
	end
	local position = ball.CFrame.Position
	ball:Destroy()
	-- Раунд мог закончиться, пока граната летела
	if State.round == round and State.isLive() then
		detonate(grenadeId, position, fighter)
	end
end

return Grenades
