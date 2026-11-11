--!strict
-- Оружие из деталей: описание модели, раскраска скином и расчёт положения деталей
-- для вида от первого лица. Модуль только считает и не создаёт Instance, поэтому
-- им пользуются и клиент, и сервер, и предпросмотр без Studio.
--
-- Оси модели: начало координат в рукояти, -Z вперёд (ствол, остриё), +Y вверх, +X вправо.

export type Paint = { color: Color3, material: string?, transparency: number?, reflectance: number? }

export type PartSpec = {
	name: string,
	slot: string, -- ячейка палитры: её перекрашивают скины
	size: Vector3,
	cf: CFrame,
	shape: string?, -- Block (по умолчанию), Ball, Wedge, CylinderX, CylinderY, CylinderZ
	parent: string?, -- деталь, вместе с которой эта движется в анимации
}

export type ModelSpec = {
	parts: { PartSpec },
	palette: { [string]: Paint },
	view: CFrame, -- положение оружия относительно камеры в покое
	armR: CFrame?, -- положение кисти относительно оружия; nil — рука не показана
	armL: CFrame?,
	muzzle: Vector3?, -- дульный срез относительно оружия
}

export type Pattern = {
	slots: { string },
	colors: { Color3 },
	axis: string?, -- X, Y или Z (по умолчанию Z: от острия к рукояти)
	width: number?, -- ширина полосы в studs, только для stripes
	material: string?,
	reflectance: number?,
}

export type Skin = {
	id: string,
	name: string,
	rarity: number, -- 1 (обычный) .. 7 (золотой)
	slots: { [string]: Paint }?, -- перекраска ячеек палитры
	gradient: Pattern?, -- плавный переход цветов вдоль оси
	stripes: Pattern?, -- чередование цветов вдоль оси
}

export type RigPart = {
	name: string,
	group: string, -- gun, armR или armL
	shape: string, -- Block, Ball, Wedge или Cylinder (ось цилиндра — локальная X, как в Roblox)
	size: Vector3,
	rest: CFrame, -- положение внутри группы
	fix: CFrame?, -- доворот формы, не влияющий на анимацию
	color: Color3,
	material: string,
	transparency: number,
	reflectance: number,
	parent: number?,
}

export type Rig = { spec: ModelSpec, parts: { RigPart } }

local Rig = {}

local IDENTITY = CFrame.new()
local ZERO = { 0, 0, 0 }
local YAW_90 = CFrame.Angles(0, math.pi / 2, 0)
local ROLL_90 = CFrame.Angles(0, 0, math.pi / 2)
local EMPTY: { [string]: CFrame } = {}

-- Положение {x, y, z} и поворот {тангаж, рысканье, крен} в градусах
function Rig.place(position: { number }, rotation: { number }?): CFrame
	local r = rotation or ZERO
	return CFrame.new(position[1], position[2], position[3])
		* CFrame.fromOrientation(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
end

function Rig.part(
	name: string,
	slot: string,
	size: { number },
	position: { number },
	rotation: { number }?,
	shape: string?,
	parent: string?
): PartSpec
	return {
		name = name,
		slot = slot,
		size = Vector3.new(size[1], size[2], size[3]),
		cf = Rig.place(position, rotation),
		shape = shape,
		parent = parent,
	}
end

function Rig.paint(r: number, g: number, b: number, material: string?, transparency: number?, reflectance: number?): Paint
	return { color = Color3.fromRGB(r, g, b), material = material, transparency = transparency, reflectance = reflectance }
end

local FALLBACK = Rig.paint(255, 0, 255)

local ARM_PARTS = {
	Rig.part("Hand", "glove", { 0.32, 0.34, 0.4 }, { 0, 0, 0 }),
	Rig.part("Sleeve", "sleeve", { 0.44, 0.44, 2 }, { 0, -0.02, 1.2 }),
}

local ARM_PALETTES: { [string]: { [string]: Paint } } = {
	T = { sleeve = Rig.paint(150, 122, 84, "Fabric"), glove = Rig.paint(62, 46, 36) },
	CT = { sleeve = Rig.paint(44, 58, 88, "Fabric"), glove = Rig.paint(26, 26, 30) },
}

local function axisValue(v: Vector3, axis: string?): number
	if axis == "X" then
		return v.X
	elseif axis == "Y" then
		return v.Y
	end
	return v.Z
end

local function sampleGradient(colors: { Color3 }, t: number): Color3
	local count = #colors
	if count == 1 then
		return colors[1]
	end
	local scaled = math.clamp(t, 0, 1) * (count - 1)
	local index = math.min(math.floor(scaled), count - 2)
	return colors[index + 1]:Lerp(colors[index + 2], scaled - index)
end

-- Диапазон положений деталей с нужными ячейками вдоль оси узора
local function span(spec: ModelSpec, pattern: Pattern): ({ [string]: boolean }, number, number)
	local set = {}
	for _, slot in pattern.slots do
		set[slot] = true
	end
	local low, high = math.huge, -math.huge
	for _, part in spec.parts do
		if set[part.slot] then
			local value = axisValue(part.cf.Position, pattern.axis)
			low = math.min(low, value)
			high = math.max(high, value)
		end
	end
	return set, low, high
end

local function normalizeShape(part: PartSpec): (string, Vector3, CFrame?)
	local shape = part.shape or "Block"
	local size = part.size
	if shape == "CylinderZ" then
		return "Cylinder", Vector3.new(size.Z, size.Y, size.X), YAW_90
	elseif shape == "CylinderY" then
		return "Cylinder", Vector3.new(size.Y, size.X, size.Z), ROLL_90
	elseif shape == "CylinderX" then
		return "Cylinder", size, nil
	end
	return shape, size, nil
end

-- Готовый к показу набор деталей: модель + скин + руки в цветах команды
function Rig.describe(spec: ModelSpec, skin: Skin?, team: string?): Rig
	local parts: { RigPart } = {}
	local indexByName: { [string]: number } = {}

	local gradient = skin and skin.gradient
	local gradientSet, gradientLow, gradientHigh = {}, 0, 1
	if gradient then
		gradientSet, gradientLow, gradientHigh = span(spec, gradient)
	end
	local stripes = skin and skin.stripes
	local stripeSet, stripeLow = {}, 0
	if stripes then
		stripeSet, stripeLow = span(spec, stripes)
	end

	for _, part in spec.parts do
		local paint = (skin and skin.slots and skin.slots[part.slot]) or spec.palette[part.slot] or FALLBACK
		local color = paint.color
		local material = paint.material
		local reflectance = paint.reflectance
		if gradient and gradientSet[part.slot] then
			local range = math.max(gradientHigh - gradientLow, 1e-3)
			color = sampleGradient(gradient.colors, (axisValue(part.cf.Position, gradient.axis) - gradientLow) / range)
			material = gradient.material or material
			reflectance = gradient.reflectance or reflectance
		end
		if stripes and stripeSet[part.slot] then
			local offset = axisValue(part.cf.Position, stripes.axis) - stripeLow
			color = stripes.colors[math.floor(offset / (stripes.width or 0.25)) % #stripes.colors + 1]
			material = stripes.material or material
			reflectance = stripes.reflectance or reflectance
		end
		local shape, size, fix = normalizeShape(part)
		table.insert(parts, {
			name = part.name,
			group = "gun",
			shape = shape,
			size = size,
			rest = part.cf,
			fix = fix,
			color = color,
			material = material or "SmoothPlastic",
			transparency = paint.transparency or 0,
			reflectance = reflectance or 0,
		})
		indexByName[part.name] = #parts
	end
	for index, part in spec.parts do
		if part.parent then
			local parent = indexByName[part.parent]
			assert(parent and parent < index, `деталь {part.name}: родитель {part.parent} должен стоять в списке раньше`)
			parts[index].parent = parent
		end
	end

	local armPalette = ARM_PALETTES[team or "T"] or ARM_PALETTES.T
	for _, group in { "armR", "armL" } do
		if (spec :: any)[group] then
			for _, part in ARM_PARTS do
				local paint = armPalette[part.slot]
				table.insert(parts, {
					name = group .. "." .. part.name,
					group = group,
					shape = "Block",
					size = part.size,
					rest = part.cf,
					color = paint.color,
					material = paint.material or "SmoothPlastic",
					transparency = 0,
					reflectance = 0,
				})
			end
		end
	end
	return { spec = spec, parts = parts }
end

-- Положение оружия в мире: base — камера с покачиванием и отдачей, sample — поза анимации
function Rig.gunCFrame(rig: Rig, base: CFrame, sample: { [string]: CFrame }?): CFrame
	local gun = sample and sample.gun
	return base * rig.spec.view * (gun or IDENTITY)
end

-- Положение каждой детали в мире, в порядке rig.parts
function Rig.pose(rig: Rig, base: CFrame, sample: { [string]: CFrame }?, detach: { [string]: boolean }?): { CFrame }
	local spec = rig.spec
	local pose = sample or EMPTY
	local viewCF = base * spec.view
	local gunCF = viewCF * (pose.gun or IDENTITY)
	local groups: { [string]: CFrame } = { gun = gunCF }
	if spec.armR then
		local anchor = if detach and detach.armR then viewCF else gunCF
		groups.armR = anchor * spec.armR * (pose.armR or IDENTITY)
	end
	if spec.armL then
		local anchor = if detach and detach.armL then viewCF else gunCF
		groups.armL = anchor * spec.armL * (pose.armL or IDENTITY)
	end

	local frames: { CFrame } = table.create(#rig.parts)
	local result: { CFrame } = table.create(#rig.parts)
	for index, part in rig.parts do
		local cf
		if part.parent then
			cf = frames[part.parent] * rig.parts[part.parent].rest:Inverse() * part.rest
		else
			cf = groups[part.group] * part.rest
		end
		local offset = pose[part.name]
		if offset then
			cf *= offset
		end
		frames[index] = cf
		result[index] = if part.fix then cf * part.fix else cf
	end
	return result
end

return Rig
