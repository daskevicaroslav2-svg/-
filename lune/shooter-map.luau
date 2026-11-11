-- Проверка и предпросмотр карты шутера без Studio.
--   lune run shooter-map <имя>      (имя файла из shooter/maps без .luau)
-- Печатает отчёт о проходимости и рисует out/<имя>-radar.png и out/<имя>-views.png

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Scene = require("./lib/scene")
local kit = require("../shooter/maps/kit")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

local name = process.args[1]
if not name then
	print("Использование: lune run shooter-map <имя>")
	process.exit(1)
end

local map = require("../shooter/maps/" .. name)
local report = kit.analyze(map)
local bounds = report.bounds

print(`{map.name}: примитивов {#map.prims}, размер {bounds.maxX - bounds.minX} x {bounds.maxZ - bounds.minZ}, достижимых узлов {#report.reach}`)
print("Путь пешком от первой точки появления (studs, в скобках секунды при скорости 17):")
local labels = {}
for label in report.distances.T do
	if not label:match("^C?T%d+$") then
		table.insert(labels, label)
	end
end
table.sort(labels)
for _, label in labels do
	local t, ct = report.distances.T[label], report.distances.CT[label]
	print(string.format("  %-14s T %4d (%4.1f)   CT %4s (%4.1f)", label, t, t / 17, tostring(ct), (ct or 0) / 17))
end
if #report.problems == 0 then
	print("Проблем не найдено.")
else
	print(`ПРОБЛЕМЫ ({#report.problems}):`)
	for index, problem in report.problems do
		if index <= 25 then
			print("  - " .. problem)
		end
	end
end

-- Чем выше верх детали, тем она светлее: на радаре видны перепады высот
local function prims(camera, shadeByHeight)
	local list = {}
	local range = math.max(bounds.maxY - bounds.minY, 1)
	for _, prim in map.prims do
		local style = map.styles[prim.style]
		local shape, size, cf = kit.shape(prim)
		local factor = if shadeByHeight then 0.6 + 0.4 * (prim.y2 - bounds.minY) / range else 1
		local color = Color3.fromRGB(style[1] * factor, style[2] * factor, style[3] * factor)
		table.insert(list, Scene.prim(camera, shape, size, cf, color))
	end
	return list
end

local centerX, centerZ = (bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2
local width, height = 800, 640
-- Камера смотрит строго вниз: вправо +x, вверх экрана север (-z)
local top = CFrame.fromMatrix(Vector3.new(centerX, bounds.maxY + 50, centerZ), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 1, 0))
local half = math.max((bounds.maxZ - bounds.minZ) / 2, (bounds.maxX - bounds.minX) / 2 / (width / height)) * 1.04

local radarLabels = {}
for _, mark in map.marks do
	table.insert(radarLabels, { p = Scene.point(top, Vector3.new(mark.x, mark.y, mark.z)), text = mark.name, color = { 255, 255, 255 } })
end
for team, color in { T = { 255, 170, 60 }, CT = { 90, 170, 255 } } do
	for index, spawn in map.spawns[team] do
		table.insert(radarLabels, { p = Scene.point(top, Vector3.new(spawn.x, spawn.y, spawn.z)), text = if index == 1 then team else "", color = color })
	end
end
local dots = {}
for _, point in report.reach do
	table.insert(dots, { p = Scene.point(top, Vector3.new(point[1], point[2], point[3])), color = { 40, 220, 90 }, r = 1 })
end
for _, leak in report.leaks do
	table.insert(dots, { p = Scene.point(top, Vector3.new(leak[1], leak[2], leak[3])), color = { 255, 0, 0 }, r = 4 })
end
local radar = prims(top, true)
Scene.render({
	width = width,
	height = height,
	cols = 2,
	background = { 24, 26, 30 },
	frames = {
		{ label = map.name .. " radar (north is up)", ortho = half, prims = radar, labels = radarLabels },
		{ label = "walkable without jumping (green), leaks (red)", ortho = half, prims = radar, dots = dots },
	},
}, `out/{name}-radar.png`)

local frames = {}
local function addView(label, from, to)
	table.insert(frames, { label = label, prims = prims(CFrame.lookAt(from, to), false) })
end
local span = math.max(bounds.maxX - bounds.minX, bounds.maxZ - bounds.minZ)
local middle = Vector3.new(centerX, 0, centerZ)
addView("overview from south-west", middle + Vector3.new(-span * 0.55, span * 0.6, span * 0.55), middle)
addView("overview from north-east", middle + Vector3.new(span * 0.55, span * 0.6, -span * 0.55), middle)
for _, team in { "T", "CT" } do
	local spawn = map.spawns[team][1]
	if spawn then
		local eye = Vector3.new(spawn.x, spawn.y + 4.5, spawn.z)
		local angle = math.rad(spawn.facing)
		addView(team .. " spawn view", eye, eye + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * 10)
	end
end
for _, view in map.views do
	addView(view.label, view.from, view.to)
end
Scene.render({ width = 480, height = 270, cols = 3, background = { 150, 180, 210 }, frames = frames }, `out/{name}-views.png`)

if #report.problems > 0 then
	process.exit(1)
end
