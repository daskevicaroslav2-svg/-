-- Конструктор карт шутера. Карта описывается прямоугольниками на сетке 2 studs:
-- kit превращает их в детали Roblox, проверяет проходимость и готовит радар.
--
-- Координаты: x растёт на восток, z — на юг (на радаре север сверху), y — высота.
-- Все x и z должны быть чётными. Всё, по чему ходят, — сплошное до глубины kit.BASE.

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local kit = {}

kit.CELL = 2
kit.BASE = -12
kit.STEP = 1.6 -- на такую высоту игрок поднимается без прыжка
kit.HEADROOM = 5.5 -- столько свободного места нужно над головой

local CELL = kit.CELL

-- Стили: цвет и материал. Карта может переопределить их через m:style().
local DEFAULT_STYLES = {
	floor = { 200, 178, 136, "Sand" },
	floor2 = { 168, 160, 150, "Concrete" },
	wall = { 214, 192, 152, "Sandstone" },
	wall2 = { 186, 160, 120, "Sandstone" },
	trim = { 120, 100, 80, "Concrete" },
	crate = { 150, 110, 60, "WoodPlanks" },
	crate2 = { 80, 110, 90, "Metal" },
	wood = { 110, 76, 46, "WoodPlanks" },
	metal = { 90, 96, 104, "Metal" },
	dark = { 70, 64, 58, "Concrete" },
	roof = { 150, 130, 105, "Concrete" },
	site = { 190, 150, 110, "Concrete" },
	accent = { 60, 110, 150, "SmoothPlastic" },
}

local Map = {}
Map.__index = Map

function kit.map(name, displayName)
	return setmetatable({
		name = name,
		displayName = displayName or name,
		prims = {},
		spawns = { T = {}, CT = {} },
		marks = {},
		views = {},
		styles = table.clone(DEFAULT_STYLES),
	}, Map)
end

local function rect(x1, z1, x2, z2)
	for _, value in { x1, z1, x2, z2 } do
		assert(value % CELL == 0, `координата {value} не кратна {CELL}`)
	end
	assert(x1 ~= x2 and z1 ~= z2, "прямоугольник нулевой ширины")
	return math.min(x1, x2), math.min(z1, z2), math.max(x1, x2), math.max(z1, z2)
end

-- Свой цвет и материал стиля (материал — имя из Enum.Material)
function Map:style(name, r, g, b, material)
	self.styles[name] = { r, g, b, material or "SmoothPlastic" }
end

-- Сплошной блок от высоты y1 до y2: стены, здания, колонны
function Map:box(x1, z1, x2, z2, y1, y2, style)
	x1, z1, x2, z2 = rect(x1, z1, x2, z2)
	assert(y2 > y1, "y2 должен быть больше y1")
	style = style or "wall"
	assert(self.styles[style], `неизвестный стиль {style}`)
	table.insert(self.prims, { kind = "box", x1 = x1, z1 = z1, x2 = x2, z2 = z2, y1 = y1, y2 = y2, style = style })
end

-- Земля с верхом на высоте y, сплошная вниз до kit.BASE
function Map:ground(x1, z1, x2, z2, y, style)
	self:box(x1, z1, x2, z2, kit.BASE, y, style or "floor")
end

-- Стена высотой height (по умолчанию 16), стоящая на высоте y
function Map:wall(x1, z1, x2, z2, y, height, style)
	self:box(x1, z1, x2, z2, y, y + (height or 16), style or "wall")
end

-- Тонкая плита с верхом на высоте yTop: мостик, второй этаж, потолок туннеля
function Map:platform(x1, z1, x2, z2, yTop, thickness, style)
	self:box(x1, z1, x2, z2, yTop - (thickness or 1), yTop, style or "floor2")
end

-- Ящик-укрытие: угол (x, z), ширина w по x, глубина d по z, высота h, стоит на высоте y
function Map:crate(x, z, w, d, h, y, style)
	self:box(x, z, x + w, z + d, y, y + h, style or "crate")
end

-- Пандус: поднимается от yLow до yHigh в направлении dir ("+x", "-x", "+z", "-z"),
-- под ним сплошная земля. Длина должна быть не меньше полутора подъёмов.
function Map:ramp(x1, z1, x2, z2, yLow, yHigh, dir, style)
	x1, z1, x2, z2 = rect(x1, z1, x2, z2)
	assert(yHigh > yLow, "yHigh должен быть больше yLow")
	assert(dir == "+x" or dir == "-x" or dir == "+z" or dir == "-z", "dir: +x, -x, +z или -z")
	style = style or "floor"
	assert(self.styles[style], `неизвестный стиль {style}`)
	local run = if dir:sub(2) == "x" then x2 - x1 else z2 - z1
	assert(run >= (yHigh - yLow) * 1.5, `пандус слишком крутой: длина {run}, подъём {yHigh - yLow}`)
	table.insert(self.prims, { kind = "ramp", x1 = x1, z1 = z1, x2 = x2, z2 = z2, y1 = yLow, y2 = yHigh, dir = dir, style = style })
	if yLow > kit.BASE then
		self:box(x1, z1, x2, z2, kit.BASE, yLow, style)
	end
end

-- Точка появления команды "T" или "CT". y — высота земли, facing — куда смотреть:
-- 0 север (-z), 90 восток (+x), 180 юг, 270 запад.
function Map:spawn(team, x, z, y, facing)
	assert(team == "T" or team == "CT", "команда: T или CT")
	rect(x, z, x + CELL, z + CELL)
	table.insert(self.spawns[team], { x = x, y = y, z = z, facing = facing or 0 })
end

-- Именованная точка: название места для радара и цель для ботов. y — высота земли.
function Map:mark(name, x, z, y)
	rect(x, z, x + CELL, z + CELL)
	table.insert(self.marks, { name = name, x = x, y = y, z = z })
end

-- Ракурс для предпросмотра (lune run shooter-map): откуда и куда смотреть
function Map:view(label, x, y, z, lookX, lookY, lookZ)
	table.insert(self.views, { label = label, from = Vector3.new(x, y, z), to = Vector3.new(lookX, lookY, lookZ) })
end

-- Камера меню: вид на карту, пока игрок выбирает команду
function Map:overview(x, y, z, lookX, lookY, lookZ)
	self.camera = { from = Vector3.new(x, y, z), to = Vector3.new(lookX, lookY, lookZ) }
end

local DIRECTIONS = {
	["+x"] = Vector3.new(1, 0, 0),
	["-x"] = Vector3.new(-1, 0, 0),
	["+z"] = Vector3.new(0, 0, 1),
	["-z"] = Vector3.new(0, 0, -1),
}
local UP = Vector3.new(0, 1, 0)

-- Форма, размер и положение детали примитива (в координатах карты)
function kit.shape(prim)
	local center = Vector3.new((prim.x1 + prim.x2) / 2, (prim.y1 + prim.y2) / 2, (prim.z1 + prim.z2) / 2)
	local dx, dy, dz = prim.x2 - prim.x1, prim.y2 - prim.y1, prim.z2 - prim.z1
	if prim.kind == "ramp" then
		-- У WedgePart высокая стенка на локальной +Z: направляем +Z в сторону подъёма
		local rise = DIRECTIONS[prim.dir]
		local alongX = prim.dir:sub(2) == "x"
		local size = Vector3.new(if alongX then dz else dx, dy, if alongX then dx else dz)
		return "Wedge", size, CFrame.fromMatrix(center, UP:Cross(rise), UP, rise)
	end
	return "Block", Vector3.new(dx, dy, dz), CFrame.new(center)
end

local function rampTop(prim, x, z)
	local progress
	if prim.dir == "+x" then
		progress = (x - prim.x1) / (prim.x2 - prim.x1)
	elseif prim.dir == "-x" then
		progress = (prim.x2 - x) / (prim.x2 - prim.x1)
	elseif prim.dir == "+z" then
		progress = (z - prim.z1) / (prim.z2 - prim.z1)
	else
		progress = (prim.z2 - z) / (prim.z2 - prim.z1)
	end
	return prim.y1 + (prim.y2 - prim.y1) * progress
end

-- Проверяет карту: все точки появления и метки должны быть связаны путём, который
-- проходится пешком (без прыжков) игроком шириной 4 studs, и с карты нельзя выпасть.
-- Возвращает отчёт: problems, reach (достижимые точки), distances, bounds.
function kit.analyze(map)
	local problems = {}
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	for _, prim in map.prims do
		minX, minZ = math.min(minX, prim.x1), math.min(minZ, prim.z1)
		maxX, maxZ = math.max(maxX, prim.x2), math.max(maxZ, prim.z2)
		minY, maxY = math.min(minY, prim.y2), math.max(maxY, prim.y2)
	end
	local nx, nz = (maxX - minX) / CELL, (maxZ - minZ) / CELL

	-- Столбики занятого пространства над каждой клеткой
	local columns = table.create(nx * nz)
	for _, prim in map.prims do
		for i = (prim.x1 - minX) / CELL, (prim.x2 - minX) / CELL - 1 do
			local x = minX + i * CELL + CELL / 2
			for j = (prim.z1 - minZ) / CELL, (prim.z2 - minZ) / CELL - 1 do
				local top = if prim.kind == "ramp" then rampTop(prim, x, minZ + j * CELL + CELL / 2) else prim.y2
				local index = i * nz + j + 1
				local column = columns[index]
				if not column then
					column = {}
					columns[index] = column
				end
				table.insert(column, { prim.y1, top })
			end
		end
	end

	-- Поверхности, на которых можно стоять: верх блока, над которым есть место для головы
	local levels = table.create(nx * nz)
	for index = 1, nx * nz do
		local column = columns[index]
		if column then
			table.sort(column, function(a, b)
				return a[1] < b[1]
			end)
			local surfaces = {}
			local top = column[1][2]
			for k = 2, #column do
				local interval = column[k]
				if interval[1] > top + 0.01 then
					if interval[1] - top >= kit.HEADROOM then
						table.insert(surfaces, top)
					end
					top = interval[2]
				elseif interval[2] > top then
					top = interval[2]
				end
			end
			table.insert(surfaces, top)
			levels[index] = surfaces
		end
	end

	local function cellLevel(i, j, h)
		if i < 0 or j < 0 or i >= nx or j >= nz then
			return nil
		end
		local surfaces = levels[i * nz + j + 1]
		if not surfaces then
			return nil
		end
		local best, bestDiff = nil, kit.STEP + 1e-6
		for _, surface in surfaces do
			local diff = math.abs(surface - h)
			if diff <= bestDiff then
				best, bestDiff = surface, diff
			end
		end
		return best
	end

	-- Узел — угол сетки: игрок стоит на четырёх клетках вокруг него
	local function resolve(ix, iz, h)
		local a = cellLevel(ix - 1, iz - 1, h)
		local b = cellLevel(ix, iz - 1, h)
		local c = cellLevel(ix - 1, iz, h)
		local d = cellLevel(ix, iz, h)
		if not (a and b and c and d) then
			return nil
		end
		local top = math.max(a, b, c, d)
		if top - math.min(a, b, c, d) > kit.STEP then
			return nil
		end
		return top
	end

	local function isVoid(i, j)
		return i < 0 or j < 0 or i >= nx or j >= nz or levels[i * nz + j + 1] == nil
	end

	local function key(ix, iz, h)
		return (ix * 4096 + iz) * 1024 + math.floor((h - kit.BASE) * 4 + 0.5)
	end

	-- Обход в ширину от узла: возвращает таблицу «ключ -> {ix, iz, h, шагов}»
	local function flood(ix, iz, h, leaks)
		local seen = { [key(ix, iz, h)] = { ix, iz, h, 0 } }
		local queue = { seen[key(ix, iz, h)] }
		local head = 1
		while head <= #queue do
			local state = queue[head]
			head += 1
			for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local jx, jz = state[1] + step[1], state[2] + step[2]
				local top = resolve(jx, jz, state[3])
				if top then
					local id = key(jx, jz, top)
					if not seen[id] then
						seen[id] = { jx, jz, top, state[4] + 1 }
						table.insert(queue, seen[id])
					end
				elseif leaks then
					-- Впереди нет никакой опоры: отсюда можно выпасть за карту
					local ci = if step[1] == 1 then jx elseif step[1] == -1 then jx - 1 else nil
					local cj = if step[2] == 1 then jz elseif step[2] == -1 then jz - 1 else nil
					local void
					if ci then
						void = isVoid(ci, jz - 1) or isVoid(ci, jz)
					else
						void = isVoid(jx - 1, cj) or isVoid(jx, cj)
					end
					if void then
						table.insert(leaks, { minX + state[1] * CELL, state[3], minZ + state[2] * CELL })
					end
				end
			end
		end
		return seen
	end

	local function nodeOf(point, label)
		local ix, iz = (point.x - minX) / CELL, (point.z - minZ) / CELL
		local top = resolve(ix, iz, point.y)
		if not top then
			table.insert(problems, `{label} ({point.x}, {point.z}): здесь нельзя стоять на высоте {point.y}`)
			return nil
		elseif math.abs(top - point.y) > 0.6 then
			table.insert(problems, `{label} ({point.x}, {point.z}): указана высота {point.y}, а земля на {top}`)
		end
		return ix, iz, top
	end

	local seeds = {}
	for _, team in { "T", "CT" } do
		if #map.spawns[team] < 5 then
			table.insert(problems, `у команды {team} меньше 5 точек появления`)
		end
		for index, spawn in map.spawns[team] do
			table.insert(seeds, { label = team .. index, point = spawn })
		end
	end
	local required = { TSpawn = true, CTSpawn = true, ASite = true, BSite = true, Mid = true }
	for _, mark in map.marks do
		required[mark.name] = nil
		table.insert(seeds, { label = mark.name, point = mark })
	end
	for name in required do
		table.insert(problems, `нет обязательной метки {name}`)
	end

	local report = { problems = problems, reach = {}, distances = { T = {}, CT = {} }, leaks = {} }
	report.bounds = { minX = minX, minZ = minZ, maxX = maxX, maxZ = maxZ, minY = minY, maxY = maxY }
	local reached
	for _, team in { "T", "CT" } do
		local spawn = map.spawns[team][1]
		local ix, iz, top
		if spawn then
			ix, iz, top = nodeOf(spawn, team .. "1")
		end
		if ix then
			local seen = flood(ix, iz, top, if team == "T" then report.leaks else nil)
			reached = reached or seen
			for _, seed in seeds do
				local sx, sz, sTop = nodeOf(seed.point, seed.label)
				local state = sx and seen[key(sx, sz, sTop)]
				if state then
					report.distances[team][seed.label] = state[4] * CELL
				elseif sx and team == "T" then
					table.insert(problems, `{seed.label} ({seed.point.x}, {seed.point.z}): пешком от появления T не дойти`)
				end
			end
		end
	end
	if reached then
		for _, state in reached do
			table.insert(report.reach, { minX + state[1] * CELL, state[3], minZ + state[2] * CELL })
		end
	end
	if #report.leaks > 0 then
		local leak = report.leaks[1]
		table.insert(problems, `с карты можно выпасть в {#report.leaks} местах, например у ({leak[1]}, {leak[3]}) на высоте {leak[2]}`)
	end

	-- Одна и та же проблема находится дважды (обход от T и от CT): убираем повторы
	local unique, known = {}, {}
	for _, problem in problems do
		if not known[problem] then
			known[problem] = true
			table.insert(unique, problem)
		end
	end
	report.problems = unique
	return report
end

local function new(className, name, parent)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function marker(name, parent, cf)
	local part = new("Part", name, parent)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = cf
	return part
end

-- Создаёт модель карты в parent со сдвигом origin: Geometry, Spawns/T, Spawns/CT, Marks, Overview
function kit.instantiate(map, parent, origin)
	local model = new("Model", map.name, parent)
	model:SetAttribute("DisplayName", map.displayName)

	local geometry = new("Folder", "Geometry", model)
	for _, prim in map.prims do
		local style = map.styles[prim.style]
		local shape, size, cf = kit.shape(prim)
		local part = Instance.new(if shape == "Wedge" then "WedgePart" else "Part")
		part.Name = prim.style
		part.Anchored = true
		part.Size = size
		part.CFrame = cf + origin
		part.Color = Color3.fromRGB(style[1], style[2], style[3])
		part.Material = Enum.Material[style[4]]
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = geometry
	end

	local spawns = new("Folder", "Spawns", model)
	for _, team in { "T", "CT" } do
		local folder = new("Folder", team, spawns)
		for index, spawn in map.spawns[team] do
			local position = Vector3.new(spawn.x, spawn.y + 3, spawn.z) + origin
			marker(tostring(index), folder, CFrame.new(position) * CFrame.Angles(0, -math.rad(spawn.facing), 0))
		end
	end

	local marks = new("Folder", "Marks", model)
	for _, mark in map.marks do
		marker(mark.name, marks, CFrame.new(Vector3.new(mark.x, mark.y + 3, mark.z) + origin))
	end

	local camera = map.camera
	if camera then
		marker("Overview", model, CFrame.lookAt(camera.from + origin, camera.to + origin))
	end
	return model
end

return kit
