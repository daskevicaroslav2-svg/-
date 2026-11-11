-- Общие помощники для сборки, проверки и предпросмотра шутера: дерево скриптов
-- из shooter/src и запуск модулей в Lune.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance

local lib = {}

-- Папка с исходниками -> где она лежит в игре
local ROOTS = {
	{ path = "shooter/src/shared", service = "ReplicatedStorage", name = "Shared" },
	{ path = "shooter/src/server", service = "ServerScriptService", name = "Server" },
	{ path = "shooter/src/client", service = "StarterPlayer", name = "Client", playerScripts = true },
}

local function mountDir(path, parent, sources)
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			local folder = Instance.new("Folder")
			folder.Name = entry
			folder.Parent = parent
			mountDir(full, folder, sources)
		elseif entry:match("%.luau$") then
			-- X.server.luau -> Script, X.client.luau -> LocalScript, остальное -> ModuleScript
			local name = entry:sub(1, -6)
			local className = "ModuleScript"
			if name:match("%.server$") then
				className, name = "Script", name:sub(1, -8)
			elseif name:match("%.client$") then
				className, name = "LocalScript", name:sub(1, -8)
			end
			local script = Instance.new(className)
			script.Name = name
			script.Source = fs.readFile(full)
			script.Parent = parent
			sources[script] = full
		end
	end
end

-- Создаёт в game дерево скриптов. Возвращает таблицу «скрипт -> путь к файлу».
function lib.mount(game)
	local sources = {}
	for _, root in ROOTS do
		if fs.isDir(root.path) then
			local parent = game:GetService(root.service)
			if root.playerScripts then
				local playerScripts = parent:FindFirstChild("StarterPlayerScripts")
				if not playerScripts then
					playerScripts = Instance.new("StarterPlayerScripts")
					playerScripts.Name = "StarterPlayerScripts"
					playerScripts.Parent = parent
				end
				parent = playerScripts
			end
			local folder = Instance.new("Folder")
			folder.Name = root.name
			folder.Parent = parent
			mountDir(root.path, folder, sources)
		end
	end
	return sources
end

-- Глобальные имена Luau и типы данных Roblox, доступные скриптам игры
function lib.globals()
	return {
		Instance = Instance,
		Enum = roblox.Enum,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		BrickColor = roblox.BrickColor,
		Font = roblox.Font,
		assert = assert, error = error, pcall = pcall, xpcall = xpcall, print = print, warn = print,
		select = select, type = type, typeof = typeof, tostring = tostring, tonumber = tonumber,
		ipairs = ipairs, pairs = pairs, next = next, unpack = unpack,
		setmetatable = setmetatable, getmetatable = getmetatable,
		rawget = rawget, rawset = rawset, rawequal = rawequal, rawlen = rawlen,
		math = math, string = string, table = table, coroutine = coroutine, os = os,
		bit32 = bit32, utf8 = utf8, buffer = buffer, debug = debug,
	}
end

-- Загрузчик модулей игры: require по Instance с общим кэшем.
-- overrides(scriptInstance) может вернуть таблицу имён, заменяющих стандартные.
function lib.loader(game, overrides)
	local loader = {}
	local modules = {}

	function loader.environment(scriptInstance)
		local env = lib.globals()
		env.game = game
		env.workspace = game:GetService("Workspace")
		env.script = scriptInstance
		env.require = loader.require
		if overrides then
			for key, value in overrides(scriptInstance) do
				env[key] = value
			end
		end
		return env
	end

	function loader.run(scriptInstance)
		local chunk = luau.load(scriptInstance.Source, {
			debugName = scriptInstance:GetFullName(),
			injectGlobals = false,
			environment = loader.environment(scriptInstance),
		})
		return chunk()
	end

	function loader.require(module)
		if not modules[module] then
			modules[module] = { value = loader.run(module) }
		end
		return modules[module].value
	end

	return loader
end

return lib
