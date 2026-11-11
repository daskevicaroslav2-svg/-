-- Карта: лобби и шесть заводов. Вызывается из build.luau.
-- Координаты завода заданы в его локальной системе: вход смотрит на -Z,
-- пол занимает x и z от -40 до 40, верх пола на высоте 0.5.

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Material = roblox.Enum.Material
local PartType = roblox.Enum.PartType
local Smooth = roblox.Enum.SurfaceType.Smooth
local rgb = roblox.Color3.fromRGB

-- Точные повороты, без погрешности синусов
local YAW_90 = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local YAW_180 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1)
local ROLL_90 = CFrame.new(0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 0, 1)

local DARK = rgb(45, 47, 54)
local STEEL = rgb(125, 130, 140)
local METAL = { Material = Material.Metal }
local NEON = { Material = Material.Neon }

local PLOT_COLORS = {
	rgb(215, 64, 64),
	rgb(56, 120, 230),
	rgb(60, 180, 90),
	rgb(240, 190, 40),
	rgb(150, 80, 220),
	rgb(240, 130, 40),
}

-- Кнопка предмета появляется после покупки предмета `requires`
local DROPPERS = {
	{ label = "Дроппер 1", price = 0, requires = "", value = 1, body = rgb(120, 125, 135), ore = rgb(150, 150, 155), material = "Slate" },
	{ label = "Дроппер 2", price = 25, requires = "Dropper1", value = 2, body = rgb(176, 120, 70), ore = rgb(205, 125, 70), material = "Metal" },
	{ label = "Дроппер 3", price = 350, requires = "Upgrader1", value = 5, body = rgb(190, 195, 205), ore = rgb(215, 220, 230), material = "Metal" },
	{ label = "Дроппер 4", price = 1500, requires = "Dropper3", value = 12, body = rgb(235, 190, 60), ore = rgb(255, 210, 70), material = "Foil" },
	{ label = "Дроппер 5", price = 9000, requires = "Upgrader2", value = 30, body = rgb(70, 200, 235), ore = rgb(100, 230, 255), material = "Glass" },
	{ label = "Мега-дроппер", price = 60000, requires = "Upgrader3", value = 100, body = rgb(170, 90, 235), ore = rgb(200, 110, 255), material = "Neon", size = 1.8 },
}
local DROPPER_X = { 31, 24, 17, 10, 3, -4 }

local UPGRADERS = {
	{ label = "Улучшитель x2", price = 120, requires = "Dropper2", multiplier = 2, color = rgb(80, 255, 140) },
	{ label = "Улучшитель x2", price = 4000, requires = "Dropper4", multiplier = 2, color = rgb(80, 170, 255) },
	{ label = "Улучшитель x1.5", price = 30000, requires = "Dropper5", multiplier = 1.5, color = rgb(210, 120, 255) },
}
local UPGRADER_X = { -11, -17, -23 }

local function new(className, name, parent)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function part(parent, name, size, cframe, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Material.SmoothPlastic
	p.TopSurface = Smooth
	p.BottomSurface = Smooth
	if props then
		for key, value in props do
			p[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- Плоский круг: цилиндр, положенный осью вверх
local function disc(parent, name, diameter, height, cframe, color, props)
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cframe * ROLL_90, color, props)
	p.Shape = PartType.Cylinder
	return p
end

local function light(parent, color, range, brightness)
	local l = new("PointLight", "Light", parent)
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	return l
end

local function button(folder, cframe, diameter, attributes)
	local name = if attributes.Item == "" then "BuyRebirth" else "Buy" .. attributes.Item
	local b = disc(folder, name, diameter, 0.4, cframe, rgb(80, 255, 120), NEON)
	for key, value in attributes do
		b:SetAttribute(key, value)
	end
	return b
end

local function buildTycoon(parent, index, plot, color)
	local tycoon = new("Model", "Tycoon" .. index, parent)
	local essentials = new("Folder", "Essentials", tycoon)
	local buttons = new("Folder", "Buttons", tycoon)
	local items = new("Folder", "Items", tycoon)

	local function at(x, y, z)
		return plot * CFrame.new(x, y, z)
	end

	-- Пол и цветная кайма
	part(essentials, "Floor", Vector3.new(80, 1, 80), at(0, 0, 0), rgb(72, 74, 80), { Material = Material.Concrete })
	part(essentials, "Trim", Vector3.new(80, 0.3, 2), at(0, 0.65, 39), color)
	part(essentials, "Trim", Vector3.new(80, 0.3, 2), at(0, 0.65, -39), color)
	part(essentials, "Trim", Vector3.new(2, 0.3, 76), at(39, 0.65, 0), color)
	part(essentials, "Trim", Vector3.new(2, 0.3, 76), at(-39, 0.65, 0), color)

	-- Ворота с табличкой владельца и площадка захвата
	part(essentials, "GatePillar", Vector3.new(2, 12, 2), at(-8, 6.5, -38.9), DARK, METAL)
	part(essentials, "GatePillar", Vector3.new(2, 12, 2), at(8, 6.5, -38.9), DARK, METAL)
	part(essentials, "OwnerSign", Vector3.new(14, 3, 1), at(0, 11, -38.9), color)
	disc(essentials, "ClaimPad", 9, 0.4, at(0, 0.7, -30), rgb(80, 255, 120), NEON)

	-- Конвейер вдоль X: руда едет к сборщику в сторону -X
	local conveyor = new("Model", "Conveyor", essentials)
	part(conveyor, "Base", Vector3.new(68, 1.5, 7), at(1, 1.25, 20), DARK, METAL)
	part(conveyor, "Belt", Vector3.new(6, 0.5, 68), at(1, 2.25, 20) * YAW_90, rgb(25, 25, 28), { Material = Material.DiamondPlate })
	part(conveyor, "RailFront", Vector3.new(68, 2, 0.5), at(1, 3, 16.75), STEEL, METAL)
	part(conveyor, "RailBack", Vector3.new(68, 2, 0.5), at(1, 3, 23.25), STEEL, METAL)
	part(conveyor, "EndStop", Vector3.new(0.5, 1.5, 6), at(34.75, 3.25, 20), STEEL, METAL)

	-- Сборщик: печь в конце ленты, руда исчезает внутри при касании Hitbox
	local collector = new("Model", "Collector", essentials)
	local brick = { Material = Material.Brick }
	local furnace = rgb(120, 70, 55)
	part(collector, "Back", Vector3.new(1, 7, 9), at(-37.5, 4, 20), furnace, brick)
	part(collector, "SideFront", Vector3.new(10, 7, 1), at(-32, 4, 16), furnace, brick)
	part(collector, "SideBack", Vector3.new(10, 7, 1), at(-32, 4, 24), furnace, brick)
	part(collector, "Roof", Vector3.new(11, 1, 9), at(-32.5, 8, 20), DARK, METAL)
	part(collector, "Chimney", Vector3.new(2, 4, 2), at(-34.5, 10.5, 20), DARK, METAL)
	local hitbox = part(collector, "Hitbox", Vector3.new(5, 4.4, 5.8), at(-32.5, 4.8, 20), rgb(255, 120, 30), {
		Material = Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	})
	light(hitbox, rgb(255, 140, 50), 16, 2)
	disc(essentials, "CollectPad", 7, 0.4, at(-32, 0.7, 9), rgb(255, 205, 60), NEON)

	-- Дропперы стоят за лентой, носик висит над её серединой
	for i, spec in DROPPERS do
		local x = DROPPER_X[i]
		local name = "Dropper" .. i
		local height = 6.4 + i * 0.6
		local dropper = new("Model", name, items)
		dropper:SetAttribute("OreValue", spec.value)
		dropper:SetAttribute("DropInterval", 1)
		dropper:SetAttribute("OreSize", spec.size or 1.2)
		dropper:SetAttribute("OreColor", spec.ore)
		dropper:SetAttribute("OreMaterial", Material[spec.material].Name)
		part(dropper, "Base", Vector3.new(5, 1, 5), at(x, 1, 27.5), DARK, METAL)
		part(dropper, "Body", Vector3.new(3.4, height, 3.4), at(x, 1.5 + height / 2, 27.5), spec.body, METAL)
		part(dropper, "Cap", Vector3.new(4, 0.6, 4), at(x, 1.8 + height, 27.5), spec.ore, NEON)
		part(dropper, "Arm", Vector3.new(2.4, 1.6, 8), at(x, 7.6, 23), DARK, METAL)
		part(dropper, "Spout", Vector3.new(1.8, 0.8, 1.8), at(x, 6.4, 20), spec.ore, NEON)
		button(buttons, at(x, 0.7, 12), 4.5, { Item = name, Label = spec.label, Price = spec.price, Requires = spec.requires })
	end

	-- Улучшители: арки над лентой между дропперами и сборщиком
	for i, spec in UPGRADERS do
		local x = UPGRADER_X[i]
		local name = "Upgrader" .. i
		local upgrader = new("Model", name, items)
		upgrader:SetAttribute("Multiplier", spec.multiplier)
		part(upgrader, "PostFront", Vector3.new(1, 5, 1), at(x, 3, 15.5), DARK, METAL)
		part(upgrader, "PostBack", Vector3.new(1, 5, 1), at(x, 3, 24.5), DARK, METAL)
		part(upgrader, "Top", Vector3.new(1.4, 1, 10.4), at(x, 6, 20), spec.color, METAL)
		part(upgrader, "Beam", Vector3.new(0.6, 2.9, 5.8), at(x, 4.05, 20), spec.color, {
			Material = Material.Neon,
			Transparency = 0.5,
			CanCollide = false,
		})
		button(buttons, at(x, 0.7, 12), 4.5, { Item = name, Label = spec.label, Price = spec.price, Requires = spec.requires })
	end

	-- Украшения
	local walls = new("Model", "Walls", items)
	part(walls, "Back", Vector3.new(79.5, 12, 1), at(0, 6.5, 39.25), color, brick)
	part(walls, "Left", Vector3.new(1, 12, 77.5), at(-39.25, 6.5, 0), color, brick)
	part(walls, "Right", Vector3.new(1, 12, 77.5), at(39.25, 6.5, 0), color, brick)
	part(walls, "FrontLeft", Vector3.new(30.75, 12, 1), at(-24.375, 6.5, -39.25), color, brick)
	part(walls, "FrontRight", Vector3.new(30.75, 12, 1), at(24.375, 6.5, -39.25), color, brick)

	local lamps = new("Model", "Lamps", items)
	for _, spot in { { -34, -24 }, { 34, -24 }, { -34, -2 }, { 34, -2 } } do
		part(lamps, "Pole", Vector3.new(0.8, 9, 0.8), at(spot[1], 5, spot[2]), DARK, METAL)
		local bulb = part(lamps, "Bulb", Vector3.new(2, 2, 2), at(spot[1], 10.3, spot[2]), rgb(255, 235, 170), {
			Material = Material.Neon,
			Shape = PartType.Ball,
		})
		light(bulb, rgb(255, 225, 160), 30, 1.5)
	end

	local roof = new("Model", "Roof", items)
	part(roof, "Glass", Vector3.new(79.5, 0.6, 79.5), at(0, 12.8, 0), rgb(170, 215, 255), {
		Material = Material.Glass,
		Transparency = 0.6,
		CastShadow = false,
	})
	part(roof, "Ridge", Vector3.new(79.5, 0.8, 1.5), at(0, 13.5, 0), DARK, METAL)

	button(buttons, at(12, 0.7, -8), 4.5, { Item = "Walls", Label = "Стены", Price = 600, Requires = "Dropper3" })
	button(buttons, at(21, 0.7, -8), 4.5, { Item = "Lamps", Label = "Фонари", Price = 2500, Requires = "Walls" })
	button(buttons, at(30, 0.7, -8), 4.5, { Item = "Roof", Label = "Стеклянная крыша", Price = 15000, Requires = "Walls" })
	button(buttons, at(-26, 0.7, -22), 7, { Item = "", Label = "Перерождение", Price = 250000, Requires = "Dropper6", Rebirth = true })

	return tycoon
end

local function tree(parent, x, z)
	part(parent, "TreeTrunk", Vector3.new(2, 8, 2), CFrame.new(x, 4, z), rgb(110, 80, 55), { Material = Material.Wood })
	part(parent, "TreeCrown", Vector3.new(11, 11, 11), CFrame.new(x, 11.5, z), rgb(60, 140, 65), {
		Material = Material.LeafyGrass,
		Shape = PartType.Ball,
	})
end

local function build(workspace)
	part(workspace, "Baseplate", Vector3.new(420, 16, 420), CFrame.new(0, -8, 0), rgb(86, 150, 78), {
		Material = Material.Grass,
		Locked = true,
	})

	local lobby = new("Model", "Lobby", workspace)
	part(lobby, "Road", Vector3.new(300, 0.3, 26), CFrame.new(0, 0.15, 0), rgb(62, 64, 70), { Material = Material.Asphalt })
	disc(lobby, "Plaza", 44, 0.5, CFrame.new(0, 0.25, 0), rgb(190, 190, 196), { Material = Material.Concrete })

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 1, 0)
	spawn.Color = rgb(240, 240, 245)
	spawn.Material = Material.SmoothPlastic
	spawn.TopSurface = Smooth
	spawn.BottomSurface = Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = workspace

	for _, spot in {
		{ -47.5, 62 }, { 47.5, 62 }, { -47.5, -62 }, { 47.5, -62 },
		{ -155, 30 }, { 155, 30 }, { -155, -30 }, { 155, -30 },
		{ -155, 85 }, { 155, 85 }, { -155, -85 }, { 155, -85 },
		{ -100, 118 }, { 0, 118 }, { 100, 118 }, { -100, -118 }, { 0, -118 }, { 100, -118 },
	} do
		tree(lobby, spot[1], spot[2])
	end

	-- Два ряда по три завода, входами к дороге
	local tycoons = new("Folder", "Tycoons", workspace)
	local index = 0
	for _, row in { { z = 62, rotation = CFrame.new(0, 0, 0) }, { z = -62, rotation = YAW_180 } } do
		for _, x in { -95, 0, 95 } do
			index += 1
			buildTycoon(tycoons, index, CFrame.new(x, 0, row.z) * row.rotation, PLOT_COLORS[index])
			local pathZ = if row.z > 0 then 17.5 else -17.5
			part(lobby, "Path", Vector3.new(14, 0.3, 9), CFrame.new(x, 0.15, pathZ), rgb(150, 150, 156), { Material = Material.Concrete })
		end
	end

	-- Камера редактора: вид на всю карту при открытии файла
	local camera = new("Camera", "Camera", workspace)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 150, 215), Vector3.new(0, 0, 10))
	camera.Focus = CFrame.new(0, 0, 10)
	workspace.CurrentCamera = camera
end

return { build = build }
