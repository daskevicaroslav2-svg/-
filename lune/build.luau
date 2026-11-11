-- Собирает Tycoon.rbxl из скриптов в src/ и карты из lune/map.luau.
-- Запуск из корня репозитория: lune run build

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local map = require("./map")

local OUTPUT = "Tycoon.rbxl"

local Instance = roblox.Instance
local game = Instance.new("DataModel")
local sourcePaths = {}

local function new(className, name, parent)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function source(className, name, path, parent)
	local instance = new(className, name, parent)
	instance.Source = fs.readFile(path)
	sourcePaths[instance] = path
	return instance
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = new("Folder", "Shared", ReplicatedStorage)
source("ModuleScript", "Config", "src/shared/Config.luau", shared)
source("ModuleScript", "Format", "src/shared/Format.luau", shared)
new("RemoteEvent", "Notify", new("Folder", "Remotes", ReplicatedStorage))

local server = source("Script", "TycoonServer", "src/server/TycoonServer.server.luau", game:GetService("ServerScriptService"))
source("ModuleScript", "PlayerData", "src/server/PlayerData.luau", server)
source("ModuleScript", "Tycoon", "src/server/Tycoon.luau", server)

local playerScripts = new("StarterPlayerScripts", "StarterPlayerScripts", game:GetService("StarterPlayer"))
source("LocalScript", "TycoonHud", "src/client/TycoonHud.client.luau", playerScripts)

game:GetService("ServerStorage")

-- Освещение как в стандартном шаблоне Baseplate
local rgb = roblox.Color3.fromRGB
local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 14.5
Lighting.Brightness = 3
Lighting.Ambient = rgb(70, 70, 70)
Lighting.OutdoorAmbient = rgb(70, 70, 70)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
Lighting.ShadowSoftness = 0.2
local atmosphere = new("Atmosphere", "Atmosphere", Lighting)
atmosphere.Density = 0.3
atmosphere.Offset = 0.25
atmosphere.Color = rgb(199, 199, 199)
atmosphere.Decay = rgb(106, 112, 125)

map.build(game:GetService("Workspace"))

fs.writeFile(OUTPUT, roblox.serializePlace(game))

-- Карта дерева объектов в формате Rojo: по ней luau-lsp проверяет типы скриптов
local count = 0
local function describe(instance)
	count += 1
	local node = { name = instance.Name, className = instance.ClassName }
	if sourcePaths[instance] then
		node.filePaths = { sourcePaths[instance] }
	end
	local children = instance:GetChildren()
	if #children > 0 then
		node.children = {}
		for _, child in children do
			table.insert(node.children, describe(child))
		end
	end
	return node
end
local tree = describe(game)
tree.name = "Tycoon"
fs.writeFile("sourcemap.json", serde.encode("json", tree))

print(`{OUTPUT}: объектов {count}, байт {#fs.readFile(OUTPUT)}`)
