-- Собирает Shooter.rbxl: скрипты из shooter/src, карты из shooter/maps, персонаж и настройки.
-- Запуск из корня репозитория: lune run shooter-build

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local kit = require("../shooter/maps/kit")
local rig = require("./lib/rig")
local shooter = require("./lib/shooter")

local OUTPUT = "Shooter.rbxl"
-- Карты стоят далеко друг от друга, чтобы с одной не было видно другую
local MAPS = {
	{ name = "Dust2", file = "dust2", origin = roblox.Vector3.new(0, 0, 0) },
	{ name = "Mirage", file = "mirage", origin = roblox.Vector3.new(3000, 0, 0) },
}

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local rgb = roblox.Color3.fromRGB

local game = Instance.new("DataModel")

local function new(className, name, parent)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local sources = shooter.mount(game)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = new("Folder", "Remotes", ReplicatedStorage)
new("RemoteEvent", "ToServer", remotes)
new("RemoteEvent", "ToClient", remotes)
new("Folder", "State", ReplicatedStorage)

-- Карты: сборка останавливается, если карта не проходит проверку проходимости.
-- Для отладки файлы можно подменить: SHOOTER_MAPS="Dust2=sample,Mirage=sample"
local substitutes = {}
for name, file in (process.env.SHOOTER_MAPS or ""):gmatch("(%w+)=(%w+)") do
	substitutes[name] = file
end
local Workspace = game:GetService("Workspace")
local maps = new("Folder", "Maps", Workspace)
local primitives = 0
for _, entry in MAPS do
	local file = substitutes[entry.name] or entry.file
	local map = require("../shooter/maps/" .. file)
	local report = kit.analyze(map)
	if #report.problems > 0 then
		error(`карта {file}: {report.problems[1]} (всего проблем: {#report.problems}; подробнее: lune run shooter-map {file})`)
	end
	map.name = entry.name
	kit.instantiate(map, maps, entry.origin)
	primitives += #map.prims
end

-- Персонаж игроков и заготовка для ботов
local StarterPlayer = game:GetService("StarterPlayer")
rig.build("StarterCharacter", Vector3.new(0, 0, 0)).Parent = StarterPlayer
rig.build("BotRig", Vector3.new(0, 0, 0)).Parent = game:GetService("ServerStorage")
-- Пустой скрипт Health заменяет стандартный: здоровье само не восстанавливается
local characterScripts = new("StarterCharacterScripts", "StarterCharacterScripts", StarterPlayer)
new("Script", "Health", characterScripts).Source = "-- Здоровье в шутере не восстанавливается само.\n"

-- Вид от первого лица, персонажей создаёт сервер в начале раунда
StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
StarterPlayer.EnableMouseLockOption = false
game:GetService("Players").CharacterAutoLoads = false

local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 15
Lighting.Brightness = 3
Lighting.Ambient = rgb(90, 86, 80)
Lighting.OutdoorAmbient = rgb(100, 96, 88)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
Lighting.ShadowSoftness = 0.2
local atmosphere = new("Atmosphere", "Atmosphere", Lighting)
atmosphere.Density = 0.32
atmosphere.Offset = 0.25
atmosphere.Color = rgb(214, 200, 176)
atmosphere.Decay = rgb(120, 110, 96)

-- Камера редактора: вид на первую карту при открытии файла
local camera = new("Camera", "Camera", Workspace)
camera.CFrame = CFrame.lookAt(Vector3.new(0, 260, 260), Vector3.new(0, 0, 0))
camera.Focus = CFrame.new(0, 0, 0)
Workspace.CurrentCamera = camera

fs.writeFile(OUTPUT, roblox.serializePlace(game))

-- Карта дерева объектов в формате Rojo: по ней luau-lsp проверяет типы скриптов.
-- Детали карт в неё не попадают: скриптам они не нужны, а файл раздувают.
local count = 0
local function describe(instance, deep)
	count += 1
	local node = { name = instance.Name, className = instance.ClassName }
	if sources[instance] then
		node.filePaths = { sources[instance] }
	end
	local children = instance:GetChildren()
	if #children > 0 and deep then
		node.children = {}
		for _, child in children do
			table.insert(node.children, describe(child, child.Name ~= "Geometry"))
		end
	end
	return node
end
local tree = describe(game, true)
tree.name = "Shooter"
fs.writeFile("shooter/sourcemap.json", serde.encode("json", tree))

print(`{OUTPUT}: скриптов {#game:GetDescendants() - #maps:GetDescendants()} объектов вне карт, примитивов карт {primitives}, байт {#fs.readFile(OUTPUT)}`)
