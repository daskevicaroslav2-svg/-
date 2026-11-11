--!strict
-- Оружие в руках игрока: стрельба, перезарядка, смена, осмотр, нож, гранаты и оптический прицел.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Effects = require(script.Parent.Effects)
local Game = require(script.Parent.Game)
local Hud = require(script.Parent.Hud)
local Menus = require(script.Parent.Menus)
local Movement = require(script.Parent.Movement)
local Sounds = require(script.Parent.Sounds)
local View = require(script.Parent.View)
local Viewmodel = require(script.Parent.Viewmodel)

type Weapon = Weapons.Weapon

local Arms = {}

local player = Game.player

local current: string? = nil
local previous: string? = nil
local ammo: { [string]: { mag: number, reserve: number } } = {}
local busyUntil = 0
local token = 0 -- меняется при каждом новом действии: отложенные шаги старого действия отменяются
local triggerHeld = false
local lastShot = 0
local lastEquip = 0
local lastInspect = 0
local spray = 0
local scoped = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function weapon(): Weapon?
	return if current then Weapons.get(current) else nil
end

local function busy(): boolean
	return os.clock() < busyUntil
end

local function occupy(duration: number): number
	token += 1
	busyUntil = os.clock() + duration
	return token
end

local function refreshHud()
	local counts = if current then ammo[current] else nil
	Hud.setWeapon(current, if counts then counts.mag else nil, if counts then counts.reserve else nil)
end

local function setScope(on: boolean)
	local held = weapon()
	local fov = if on and held then held.scopeFov else nil
	if scoped == (fov ~= nil) then
		return
	end
	scoped = fov ~= nil
	View.setZoom(fov)
	Viewmodel.setHidden(scoped)
	Hud.setScope(scoped)
end

-- Берёт оружие в руки. announce — сообщить серверу (не нужно, если он сам так решил).
local function show(weaponId: string, announce: boolean)
	setScope(false)
	if current and current ~= weaponId then
		previous = current
	end
	current = weaponId
	local modelId, skin = Game.look(weaponId)
	Viewmodel.show(modelId, skin, Game.team())
	occupy(math.max(Viewmodel.play("equip"), 0.25))
	spray = 0
	Sounds.play("Equip", 0.25)
	if announce then
		lastEquip = os.clock()
		Net.send("Equip", weaponId)
	end
	refreshHud()
end

local function drop()
	token += 1
	setScope(false)
	current = nil
	triggerHeld = false
	Viewmodel.show(nil, nil, Game.team())
	View.reset()
	Hud.setWeapon(nil, nil, nil)
end

function Arms.equip(weaponId: string)
	if Game.alive() and weaponId ~= current and Game.owns(weaponId) then
		show(weaponId, true)
	end
end

-- Клавиши 1-4: основное, пистолет, нож, гранаты по кругу
local function equipSlot(slot: number)
	local grenades = {}
	for _, id in Game.weapons() do
		local data = Weapons.get(id)
		if data and data.slot == slot then
			if slot ~= 4 then
				Arms.equip(id)
				return
			end
			table.insert(grenades, id)
		end
	end
	if #grenades > 0 then
		local index = if current then table.find(grenades, current) or 0 else 0
		Arms.equip(grenades[index % #grenades + 1])
	end
end

local function cycle(step: number)
	local list = Game.weapons()
	local index = if current then table.find(list, current) or 1 else 1
	Arms.equip(list[(index - 1 + step) % #list + 1])
end

local function body(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid, if root and root:IsA("BasePart") then root else nil
end

-- Разброс в градусах: растёт в движении, в прыжке и при стрельбе очередью
local function spreadAngle(held: Weapon): number
	local angle = held.spread + spray
	if held.scopeFov and not scoped then
		angle += 4.5
	end
	local humanoid, root = body()
	if humanoid and root then
		local velocity = root.AssemblyLinearVelocity
		local planar = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if humanoid.FloorMaterial == Enum.Material.Air then
			angle += held.moveSpread * 1.5 + 2
		elseif planar > held.speed * 0.34 then
			angle += held.moveSpread * math.min(planar / held.speed, 1)
		end
	end
	return angle
end

local function excluded(): { Instance }
	local list: { Instance } = { Effects.folder }
	if player.Character then
		table.insert(list, player.Character)
	end
	for _, name in { "Effects", "Smokes" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

local function reload()
	local held = weapon()
	local counts = if current then ammo[current] else nil
	if not held or held.kind ~= "gun" or not counts or busy() then
		return
	end
	if counts.mag >= held.mag or counts.reserve <= 0 then
		return
	end
	setScope(false)
	local weaponId = held.id
	local duration = Viewmodel.play("reload")
	if duration == 0 then
		duration = held.reloadTime
	end
	local action = occupy(duration)
	Sounds.play("Reload", 0.4)
	task.delay(duration, function()
		if token ~= action or current ~= weaponId then
			return
		end
		local moved = math.min(held.mag - counts.mag, counts.reserve)
		counts.mag += moved
		counts.reserve -= moved
		Net.send("Reload", weaponId)
		refreshHud()
	end)
end

local function shoot(held: Weapon, camera: Camera)
	local counts = ammo[held.id]
	if not counts then
		return
	end
	if counts.mag <= 0 then
		if counts.reserve > 0 then
			reload()
		elseif os.clock() - lastShot > 0.25 then
			lastShot = os.clock()
			Sounds.play("Empty", 0.4)
		end
		return
	end
	local now = os.clock()
	if now - lastShot < 60 / held.rpm then
		return
	end
	lastShot = now
	if Viewmodel.playing() then
		Viewmodel.stop()
	end

	-- Случайное отклонение внутри конуса разброса
	local cf = camera.CFrame
	local radius = math.tan(math.rad(spreadAngle(held))) * math.sqrt(math.random())
	local turn = math.random() * math.pi * 2
	local direction = (cf.LookVector + cf.RightVector * math.cos(turn) * radius + cf.UpVector * math.sin(turn) * radius).Unit
	local origin = cf.Position
	rayParams.FilterDescendantsInstances = excluded()
	local result = Workspace:Raycast(origin, direction * 1000, rayParams)
	local hitPosition = if result then result.Position else origin + direction * 1000
	Net.send("Fire", held.id, origin, direction, if result then result.Instance else nil, hitPosition)

	counts.mag -= 1
	local muzzle = Viewmodel.muzzle() or origin + cf.LookVector * 2
	Effects.tracer(muzzle, hitPosition)
	Effects.muzzleFlash(muzzle)
	if result then
		Effects.impact(result.Position, result.Normal)
	end
	Sounds.play(if held.heavy then "FireHeavy" else "Fire", 0.5)
	Viewmodel.kick(held.recoil)
	View.kick(held.recoil)
	spray = math.min(spray + held.sprayStep, held.sprayMax)
	if scoped then
		setScope(false)
	end
	refreshHud()
end

-- Удар ножом: сам удар приходится на середину анимации
local function swing(heavy: boolean, camera: Camera)
	if busy() then
		return
	end
	local attack = if heavy then Weapons.Knife.stab else Weapons.Knife.slash
	local duration = Viewmodel.play(if heavy then "stab" else "slash")
	local action = occupy(if duration > 0 then duration else attack.time)
	Sounds.play(if heavy then "Stab" else "Slash", 0.4)
	task.delay(attack.hit, function()
		if token ~= action then
			return
		end
		local cf = camera.CFrame
		rayParams.FilterDescendantsInstances = excluded()
		-- Три луча веером: ножом не нужно целиться точно
		local hitPart: Instance? = nil
		for _, side in { 0, -0.14, 0.14 } do
			local result = Workspace:Raycast(cf.Position, (cf.LookVector + cf.RightVector * side).Unit * Weapons.Knife.range, rayParams)
			if result and result.Instance:FindFirstAncestorOfClass("Model") then
				hitPart = result.Instance
				break
			end
		end
		Net.send("Knife", heavy, hitPart)
	end)
end

local function throw(held: Weapon, camera: Camera)
	if busy() then
		return
	end
	local weaponId = held.id
	local duration = Viewmodel.play("throw")
	local action = occupy(if duration > 0 then duration else 0.5)
	task.delay(Weapons.Grenades.throwTime, function()
		if token ~= action or current ~= weaponId then
			return
		end
		local cf = camera.CFrame
		Net.send("Throw", weaponId, cf.Position + cf.LookVector * 2, (cf.LookVector + Vector3.new(0, 0.12, 0)).Unit)
		Sounds.play("Slash", 0.3)
		Viewmodel.setHidden(true)
	end)
	task.delay(if duration > 0 then duration else 0.5, function()
		if token ~= action or current ~= weaponId then
			return
		end
		-- Если такая граната ещё осталась, берём её; иначе возвращаем прежнее оружие
		local left = 0
		for _, id in Game.grenades() do
			if id == weaponId then
				left += 1
			end
		end
		local nextId = if previous and previous ~= weaponId and Game.owns(previous) then previous else "Knife"
		for _, id in Game.weapons() do
			local data = Weapons.get(id)
			if data and data.slot <= 2 and nextId == "Knife" then
				nextId = id
			end
		end
		current = nil
		show(if left > 1 then weaponId else nextId, true)
	end)
end

local function pullTrigger(camera: Camera)
	local held = weapon()
	if not held or busy() then
		return
	end
	if held.kind == "gun" then
		shoot(held, camera)
	elseif held.kind == "knife" then
		swing(false, camera)
	elseif held.kind == "grenade" then
		throw(held, camera)
	end
end

-- Осмотр оружия. Двойное нажатие — секретная анимация; изредка она выпадает и сама.
local function inspect()
	if not current or busy() or scoped then
		return
	end
	local now = os.clock()
	local secret = now - lastInspect < Config.DoubleTap or math.random() < Config.SecretChance
	lastInspect = now
	if not secret or Viewmodel.play("secret") == 0 then
		Viewmodel.play("inspect")
	end
end

local function canAct(): boolean
	return current ~= nil and Game.alive() and not Menus.isOpen() and Game.phase() ~= "Freeze"
end

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local function onInputBegan(input: InputObject, processed: boolean)
	local camera = Workspace.CurrentCamera
	if processed or not camera or not Game.alive() or Menus.isOpen() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = true
		if canAct() then
			pullTrigger(camera)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		local held = weapon()
		if held and canAct() and not busy() then
			if held.kind == "knife" then
				swing(true, camera)
			elseif held.scopeFov then
				setScope(not scoped)
			end
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		reload()
	elseif input.KeyCode == Enum.KeyCode.F then
		inspect()
	elseif input.KeyCode == Enum.KeyCode.Q then
		if previous then
			Arms.equip(previous)
		end
	elseif SLOT_KEYS[input.KeyCode] then
		equipSlot(SLOT_KEYS[input.KeyCode])
	end
end

-- Каждый кадр после камеры
function Arms.update(dt: number, camera: Camera)
	local humanoid, root = body()
	if not Game.alive() or not humanoid or not root or humanoid.Health <= 0 then
		if current then
			drop()
		end
		Hud.setCrosshair(0, false)
		Hud.setBhop(0)
		Viewmodel.update(dt, camera, 0, true, 0)
		return
	end
	if not current then
		local equipped = player:GetAttribute("Equipped")
		show(if typeof(equipped) == "string" and Game.owns(equipped) then equipped else "Knife", false)
	end
	local held = weapon()
	if not held then
		return
	end
	if triggerHeld and held.auto and canAct() and not busy() then
		pullTrigger(camera)
	end
	if os.clock() - lastShot > 0.12 then
		spray = math.max(0, spray - dt * 9)
	end

	Movement.update(held.speed, if scoped then 0.5 else 1)
	Hud.setBhop(Movement.hops())
	local velocity = root.AssemblyLinearVelocity
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	Viewmodel.update(dt, camera, Vector3.new(velocity.X, 0, velocity.Z).Magnitude, grounded, velocity.Y)
	-- У снайперской винтовки без оптики прицела нет, как в CS
	Hud.setCrosshair(spreadAngle(held), not scoped and not held.scopeFov)
end

function Arms.init()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed and Game.alive() and not Menus.isOpen() then
			cycle(if input.Position.Z > 0 then -1 else 1)
		end
	end)

	Net.on("Ammo", function(data: any)
		if typeof(data) == "table" then
			ammo = data
			refreshHud()
		end
	end)
	-- Сервер сам меняет оружие после покупки; свои недавние переключения не перебиваем
	player:GetAttributeChangedSignal("Equipped"):Connect(function()
		local equipped = player:GetAttribute("Equipped")
		if Game.alive() and typeof(equipped) == "string" and equipped ~= current and os.clock() - lastEquip > 1 and Game.owns(equipped) then
			show(equipped, false)
		end
	end)
	-- Новый нож или скин сразу появляется в руках
	local function reskin()
		if current and Game.alive() then
			local modelId, skin = Game.look(current)
			Viewmodel.show(modelId, skin, Game.team())
		end
	end
	player:GetAttributeChangedSignal("Skins"):Connect(reskin)
	player:GetAttributeChangedSignal("Knife"):Connect(reskin)
end

return Arms
