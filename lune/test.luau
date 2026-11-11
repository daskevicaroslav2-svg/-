-- Дымовой тест логики игры. Запуск из корня репозитория: lune run test
-- Скрипты из собранного Tycoon.rbxl выполняются в Lune, а движок Roblox заменён
-- заглушками (сигналы, игроки, DataStore). Физики здесь нет, поэтому вместо неё
-- проверяется геометрия конвейера: руда падает на ленту и доезжает до сборщика.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local PLACE = "Tycoon.rbxl"
local SPEED = 25 -- во сколько раз ускорено игровое время

local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local game = roblox.deserializePlace(fs.readFile(PLACE))
game.GameId = 1 -- как у опубликованной игры, чтобы работала ветка с DataStore
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local checks, failures = 0, 0
local warnings = {}

local function check(condition, message)
	checks += 1
	if not condition then
		failures += 1
		print("  ПРОВАЛ: " .. message)
	end
end

-- Ошибка в игровом скрипте не должна потеряться в планировщике
local function guard(fn)
	return function(...)
		local result = table.pack(xpcall(fn, function(err)
			return debug.traceback(tostring(err), 2)
		end, ...))
		if not result[1] then
			check(false, "ошибка скрипта: " .. tostring(result[2]))
			return
		end
		return table.unpack(result, 2, result.n)
	end
end

---------------------------------------------------------------------------
-- Сигналы

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	local entry = { fn = fn, connection = connection }
	table.insert(self.handlers, entry)
	function connection.Disconnect()
		connection.Connected = false
		local index = table.find(self.handlers, entry)
		if index then
			table.remove(self.handlers, index)
		end
	end
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, entry in table.clone(self.handlers) do
		if entry.connection.Connected then
			task.spawn(guard(entry.fn), ...)
		end
	end
end

local signals = {}
local function signalOf(instance, name)
	local map = signals[instance]
	if not map then
		map = {}
		signals[instance] = map
	end
	if not map[name] then
		map[name] = Signal.new()
	end
	return map[name]
end

-- Lune не сообщает об изменении свойств: изменения ловит опрос в pump()
local watchers = {}
local watched = {}
local function watch(instance, key, read)
	local id = watched[instance]
	if not id then
		id = {}
		watched[instance] = id
	end
	if id[key] then
		return
	end
	id[key] = true
	local last = read()
	table.insert(watchers, function()
		local ok, value = pcall(read)
		if ok and value ~= last then
			last = value
			signalOf(instance, key):Fire(value)
		end
	end)
end

local function pump()
	for _, watcher in table.clone(watchers) do
		watcher()
	end
end

for className, names in {
	Instance = { "ChildAdded", "ChildRemoved", "DescendantAdded", "AncestryChanged", "Destroying" },
	BasePart = { "Touched", "TouchEnded" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	Humanoid = { "Died" },
	RemoteEvent = { "OnClientEvent", "OnServerEvent" },
} do
	for _, name in names do
		roblox.implementProperty(className, name, function(instance)
			return signalOf(instance, name)
		end)
	end
end

roblox.implementProperty("ValueBase", "Changed", function(instance)
	watch(instance, "Changed", function()
		return instance.Value
	end)
	return signalOf(instance, "Changed")
end)

roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(instance, name)
	local key = "Attribute:" .. name
	watch(instance, key, function()
		return instance:GetAttribute(name)
	end)
	return signalOf(instance, key)
end)

---------------------------------------------------------------------------
-- Заглушки методов и сервисов

local localPlayer = nil
local pivots = {}
local collisionGroups = { Default = true }
local closeCallbacks = {}
local clientMessages = {}
local savedData = {}
local dataStoreFails = false

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

local dataStore = {}
function dataStore:GetAsync(key)
	if dataStoreFails then
		error("502: API Services rejected request (заглушка)")
	end
	return deepCopy(savedData[key])
end
function dataStore:SetAsync(key, value)
	if dataStoreFails then
		error("502: API Services rejected request (заглушка)")
	end
	savedData[key] = deepCopy(value)
end

roblox.implementMethod("Instance", "WaitForChild", function(instance, name)
	local child = instance:FindFirstChild(name)
	if not child then
		error(`WaitForChild: нет {instance:GetFullName()}.{name}`)
	end
	return child
end)
-- Players.LocalPlayer подменить нельзя, поэтому клиентский скрипт получает свой game
local clientGame = {
	GetService = function(_, name)
		if name == "Players" then
			return { LocalPlayer = localPlayer }
		end
		return game:GetService(name)
	end,
}
roblox.implementMethod("Players", "GetPlayers", function(players)
	local list = {}
	for _, child in players:GetChildren() do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end)
roblox.implementMethod("Players", "GetPlayerFromCharacter", function(players, character)
	for _, child in players:GetChildren() do
		if child.ClassName == "Player" and child.Character == character then
			return child
		end
	end
	return nil
end)
roblox.implementMethod("Model", "PivotTo", function(model, cframe)
	pivots[model] = cframe
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
roblox.implementMethod("PhysicsService", "RegisterCollisionGroup", function(_, name)
	collisionGroups[name] = true
end)
roblox.implementMethod("PhysicsService", "CollisionGroupSetCollidable", function(_, a, b)
	assert(collisionGroups[a] and collisionGroups[b], "группа столкновений не зарегистрирована")
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)
roblox.implementMethod("Debris", "AddItem", function(_, instance, lifetime)
	task.delay(lifetime / SPEED, function()
		pcall(function()
			instance:Destroy()
		end)
	end)
end)
roblox.implementMethod("DataStoreService", "GetDataStore", function()
	return dataStore
end)
roblox.implementMethod("DataModel", "BindToClose", function(_, callback)
	table.insert(closeCallbacks, callback)
end)
roblox.implementMethod("TweenService", "Create", function(_, instance, _, goals)
	return {
		Play = function()
			for key, value in goals do
				instance[key] = value
			end
		end,
	}
end)
roblox.implementMethod("RemoteEvent", "FireClient", function(remote, player, ...)
	table.insert(clientMessages, { player = player, text = (...) })
	if player == localPlayer then
		signalOf(remote, "OnClientEvent"):Fire(...)
	end
end)

---------------------------------------------------------------------------
-- Запуск скриптов из place-файла

local scaledTask = {
	wait = function(seconds)
		return task.wait((seconds or 0) / SPEED)
	end,
	delay = function(seconds, fn, ...)
		return task.delay(seconds / SPEED, guard(fn), ...)
	end,
	spawn = function(fn, ...)
		return task.spawn(if type(fn) == "function" then guard(fn) else fn, ...)
	end,
	defer = function(fn, ...)
		return task.defer(if type(fn) == "function" then guard(fn) else fn, ...)
	end,
	cancel = task.cancel,
}
local scaledOs = setmetatable({
	clock = function()
		return os.clock() * SPEED
	end,
}, { __index = os })

local modules = {}
local execute

local function requireModule(module)
	if not modules[module] then
		modules[module] = { value = execute(module) }
	end
	return modules[module].value
end

function execute(scriptInstance, clientSide)
	local chunk = luau.load(scriptInstance.Source, {
		debugName = scriptInstance:GetFullName(),
		injectGlobals = false,
		environment = {
			game = if clientSide then clientGame else game,
			workspace = Workspace,
			script = scriptInstance,
			require = requireModule,
			task = scaledTask,
			os = scaledOs,
			warn = function(...)
				local parts = table.pack(...)
				for i = 1, parts.n do
					parts[i] = tostring(parts[i])
				end
				table.insert(warnings, table.concat(parts, " "))
			end,
			Instance = Instance,
			Enum = roblox.Enum,
			Vector2 = roblox.Vector2,
			Vector3 = Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			PhysicalProperties = roblox.PhysicalProperties,
			TweenInfo = {
				new = function(...)
					return { ... }
				end,
			},
			assert = assert, error = error, pcall = pcall, xpcall = xpcall, print = print,
			select = select, type = type, typeof = typeof, tostring = tostring, tonumber = tonumber,
			ipairs = ipairs, pairs = pairs, next = next, unpack = unpack,
			setmetatable = setmetatable, getmetatable = getmetatable,
			rawget = rawget, rawset = rawset, rawequal = rawequal,
			math = math, string = string, table = table, coroutine = coroutine,
		},
	})
	return chunk()
end

---------------------------------------------------------------------------
-- Помощники сценария

local function wait(seconds)
	task.wait(seconds / SPEED)
	pump()
end

local function spawnCharacter(player)
	if player.Character then
		player.Character:Destroy()
	end
	local character = Instance.new("Model")
	character.Name = player.Name
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	for _, name in { "HumanoidRootPart", "LeftFoot" } do
		local limb = Instance.new("Part")
		limb.Name = name
		limb.Parent = character
	end
	character.Parent = Workspace
	player.Character = character
	signalOf(player, "CharacterAdded"):Fire(character)
	return character
end

local function addPlayer(name, userId)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	Instance.new("PlayerGui").Parent = player
	player.Parent = Players
	spawnCharacter(player)
	signalOf(Players, "PlayerAdded"):Fire(player)
	return player
end

local function removePlayer(player)
	signalOf(Players, "PlayerRemoving"):Fire(player)
	player.Character:Destroy()
	player:Destroy()
end

local function touch(part, player)
	signalOf(part, "Touched"):Fire(player.Character.LeftFoot)
end

local function hit(part, other)
	signalOf(part, "Touched"):Fire(other)
end

local function itemOf(button)
	return if button:GetAttribute("Rebirth") then "Rebirth" else button:GetAttribute("Item")
end

local function visible(tycoon)
	local names = {}
	for _, button in tycoon.Buttons:GetChildren() do
		table.insert(names, itemOf(button))
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function buttonFor(tycoon, item)
	for _, button in tycoon.Buttons:GetChildren() do
		if itemOf(button) == item then
			return button
		end
	end
	error(`кнопка {item} не видна на {tycoon.Name}, видны: {visible(tycoon)}`)
end

local function lastMessage(player)
	for i = #clientMessages, 1, -1 do
		if clientMessages[i].player == player then
			return clientMessages[i].text
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Геометрия завода

local EPS = 1e-3

local function bounds(p)
	local half = p.Size / 2
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = p.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				for axis, value in { corner.X, corner.Y, corner.Z } do
					lo[axis] = math.min(lo[axis], value)
					hi[axis] = math.max(hi[axis], value)
				end
			end
		end
	end
	return { min = Vector3.new(lo[1], lo[2], lo[3]), max = Vector3.new(hi[1], hi[2], hi[3]) }
end

local function overlapsXZ(a, b)
	return a.min.X < b.max.X - EPS and b.min.X < a.max.X - EPS and a.min.Z < b.max.Z - EPS and b.min.Z < a.max.Z - EPS
end

local function insideXZ(inner, outer)
	return inner.min.X >= outer.min.X - EPS and inner.max.X <= outer.max.X + EPS
		and inner.min.Z >= outer.min.Z - EPS and inner.max.Z <= outer.max.Z + EPS
end

local function checkLayout(tycoon, storage, speed)
	local name = tycoon.Name
	local floor = bounds(tycoon.Essentials.Floor)
	local belt = tycoon.Essentials.Conveyor.Belt
	local beltBox = bounds(belt)
	local hitboxBox = bounds(tycoon.Essentials.Collector.Hitbox)
	local velocity = belt.AssemblyLinearVelocity
	check(math.abs(velocity.Magnitude - speed) < EPS and math.abs(velocity.Y) < EPS, `{name}: скорость ленты {velocity}`)

	-- Координата вдоль хода ленты и размер поперёк неё
	local direction = velocity.Unit
	local function along(position)
		return position:Dot(direction)
	end
	local function alongRange(box)
		local a, b = along(box.min), along(box.max)
		return math.min(a, b), math.max(a, b)
	end
	local function across(box)
		local size = box.max - box.min
		return math.abs(direction.Z) * size.X + math.abs(direction.X) * size.Z
	end

	local beltStart, beltEnd = alongRange(beltBox)
	local hitStart, hitEnd = alongRange(hitboxBox)
	check(
		overlapsXZ(hitboxBox, beltBox) and hitStart < beltEnd and hitEnd >= beltEnd and hitboxBox.min.Y < beltBox.max.Y + 0.6,
		`{name}: сборщик перекрывает конец ленты`
	)

	local lastSpout = -math.huge
	local droppers, upgraders = 0, 0
	local function beamOf(item)
		return if item:GetAttribute("Multiplier") ~= nil then item:FindFirstChild("Beam") else nil
	end
	for _, item in storage:GetChildren() do
		local spout = item:FindFirstChild("Spout")
		local beam = beamOf(item)
		if spout then
			droppers += 1
			local size = item:GetAttribute("OreSize")
			local center = spout.CFrame.Position - Vector3.new(0, spout.Size.Y / 2 + size / 2 + 0.2, 0)
			local half = Vector3.new(size / 2, size / 2, size / 2)
			local oreBox = { min = center - half, max = center + half }
			check(
				insideXZ(oreBox, beltBox) and oreBox.min.Y > beltBox.max.Y and along(center) > beltStart and along(center) < hitStart,
				`{name}/{item.Name}: руда падает на ленту перед сборщиком`
			)
			lastSpout = math.max(lastSpout, along(center) + size / 2)
		elseif beam then
			upgraders += 1
		end
	end
	for _, item in storage:GetChildren() do
		local beam = beamOf(item)
		if beam then
			local box = bounds(beam)
			local beamStart, beamEnd = alongRange(box)
			check(
				beamStart > lastSpout and beamEnd < hitStart and overlapsXZ(box, beltBox)
					and across(box) >= across(beltBox) - 0.5 and box.min.Y < beltBox.max.Y + 0.6 and beam.CanCollide == false,
				`{name}/{item.Name}: луч стоит между дропперами и сборщиком и перекрывает ленту`
			)
		end
	end
	check(droppers == 6 and upgraders == 3, `{name}: 6 дропперов и 3 улучшителя, найдено {droppers} и {upgraders}`)

	-- Площадки лежат на полу и не перекрываются: случайной двойной покупки не будет
	local pads = { tycoon.Essentials.ClaimPad, tycoon.Essentials.CollectPad }
	for _, child in storage:GetChildren() do
		if child:GetAttribute("Price") ~= nil then
			table.insert(pads, child)
			local item, requires = child:GetAttribute("Item"), child:GetAttribute("Requires")
			check(child:GetAttribute("Rebirth") == true or storage:FindFirstChild(item) ~= nil, `{name}/{child.Name}: предмет {item} существует`)
			check(requires == "" or storage:FindFirstChild(requires) ~= nil, `{name}/{child.Name}: зависимость {requires} существует`)
		end
	end
	check(#pads == 15, `{name}: 13 кнопок и 2 площадки, найдено {#pads}`)
	for i, pad in pads do
		local box = bounds(pad)
		check(insideXZ(box, floor) and box.max.Y > floor.max.Y + 0.2 and math.abs(box.min.Y - floor.max.Y) < EPS, `{name}/{pad.Name}: площадка лежит на полу`)
		for j = i + 1, #pads do
			check(not overlapsXZ(box, bounds(pads[j])), `{name}: {pad.Name} и {pads[j].Name} перекрываются`)
		end
	end
end

---------------------------------------------------------------------------
-- Сценарий

task.spawn(function()
	while true do
		pump()
		task.wait()
	end
end)

print("1. Запуск сервера")
local Config = requireModule(ReplicatedStorage.Shared.Config)
local Format = requireModule(ReplicatedStorage.Shared.Format)
check(Format.money(0) == "$0" and Format.money(999) == "$999" and Format.money(1234) == "$1,234", "Format.money: разряды")
check(Format.money(999999.9) == "$999,999" and Format.money(100000) == "$100,000", "Format.money: тысячи")
check(Format.money(1500000) == "$1.5M" and Format.money(2e9) == "$2B" and Format.money(1250000) == "$1.25M", "Format.money: сокращения")
check(Format.multiplier(1.5) == "1.5" and Format.multiplier(2) == "2" and Format.multiplier(10) == "10", "Format.multiplier")

guard(execute)(game:GetService("ServerScriptService").TycoonServer)
local tycoons = Workspace.Tycoons
local storageRoot = ServerStorage:FindFirstChild("TycoonStorage")
check(#warnings == 0, "предупреждения при запуске: " .. table.concat(warnings, "; "))
check(storageRoot ~= nil and #storageRoot:GetChildren() == 6, "запущены все 6 заводов")
for _, tycoon in tycoons:GetChildren() do
	checkLayout(tycoon, storageRoot[tycoon.Name], Config.ConveyorSpeed)
	check(#tycoon.Items:GetChildren() == 0 and #tycoon.Buttons:GetChildren() == 0, `{tycoon.Name}: предметы и кнопки скрыты до захвата`)
end

print("2. Игрок занимает завод")
local t1 = tycoons.Tycoon1
local claimPad = t1.Essentials.ClaimPad
local collectPad = t1.Essentials.CollectPad
local hitbox = t1.Essentials.Collector.Hitbox
local sign = t1.Essentials.OwnerSign.SignFront.TextLabel
local bankLabel = collectPad.Label.TextLabel
check(sign.Text == Config.Text.Unclaimed and claimPad.Label.TextLabel.Text == Config.Text.ClaimPad, "надписи свободного завода")

local alice = addPlayer("Alice", 101)
local cash = alice.leaderstats[Config.CashStat]
local rebirths = alice.leaderstats[Config.RebirthStat]
check(cash.Value == Config.StartingCash and rebirths.Value == 0, "стартовые значения leaderstats")
check(alice.Character.LeftFoot.CollisionGroup == "Players", "персонаж в группе столкновений Players")

touch(claimPad, alice)
check(alice:GetAttribute("Tycoon") == "Tycoon1", "завод занят")
check(t1.Essentials:FindFirstChild("ClaimPad") == nil, "площадка захвата скрыта")
check(visible(t1) == "Dropper1", "после захвата видна только первая кнопка, видны: " .. visible(t1))
check(sign.Text == string.format(Config.Text.Owner, "Alice"), "табличка владельца: " .. sign.Text)
check(lastMessage(alice) == Config.Text.Claimed, "сообщение о захвате")
check(buttonFor(t1, "Dropper1").Label.TextLabel.Text == "Дроппер 1\n" .. Config.Text.Free, "надпись бесплатной кнопки")

print("3. Покупки, руда и сбор денег")
touch(buttonFor(t1, "Dropper1"), alice)
check(t1.Purchased:FindFirstChild("Dropper1") ~= nil, "бесплатный дроппер куплен")
check(visible(t1) == "Dropper2", "открылась следующая кнопка, видны: " .. visible(t1))
check(buttonFor(t1, "Dropper2").Label.TextLabel.Text == "Дроппер 2\n$25", "надпись платной кнопки")
wait(2.5)
local ores = t1.Ores:GetChildren()
check(#ores >= 2 and #ores <= 4, `дроппер роняет руду раз в секунду, за 2.5 с штук: {#ores}`)
local ore = ores[1]
check(ore:GetAttribute("Value") == 1 and ore.CollisionGroup == "Ore" and ore.Anchored == false, "параметры руды")

hit(hitbox, ore)
check(ore.Parent == nil, "сборщик уничтожает руду")
check(bankLabel.Text == string.format(Config.Text.Collect, "$1"), "банк завода: " .. bankLabel.Text)
hit(hitbox, alice.Character.LeftFoot)
check(bankLabel.Text == string.format(Config.Text.Collect, "$1"), "сборщик не реагирует на игрока")
touch(collectPad, alice)
check(cash.Value == 1 and bankLabel.Text == string.format(Config.Text.Collect, "$0"), "деньги собраны")

wait(1)
touch(buttonFor(t1, "Dropper2"), alice)
check(cash.Value == 1 and t1.Purchased:FindFirstChild("Dropper2") == nil, "без денег покупка не проходит")
check(lastMessage(alice) == string.format(Config.Text.NotEnough, "$24"), "сообщение о нехватке: " .. tostring(lastMessage(alice)))
check(buttonFor(t1, "Dropper2").Color == roblox.Color3.fromRGB(255, 95, 95), "недоступная кнопка красная")

cash.Value = 1000000
wait(0.5)
check(buttonFor(t1, "Dropper2").Color == roblox.Color3.fromRGB(80, 255, 120), "доступная кнопка зелёная")
local spent, order = 0, {}
for _ = 1, 20 do
	local nextButton = nil
	for _, button in t1.Buttons:GetChildren() do
		if not button:GetAttribute("Rebirth") and (not nextButton or button:GetAttribute("Price") < nextButton:GetAttribute("Price")) then
			nextButton = button
		end
	end
	if not nextButton then
		break
	end
	spent += nextButton:GetAttribute("Price")
	table.insert(order, nextButton:GetAttribute("Item"))
	touch(nextButton, alice)
	wait(0.5)
end
check(
	table.concat(order, ",") == "Dropper2,Upgrader1,Dropper3,Walls,Dropper4,Lamps,Upgrader2,Dropper5,Roof,Upgrader3,Dropper6",
	"порядок покупок: " .. table.concat(order, ",")
)
check(spent == 123095 and cash.Value == 1000000 - spent, `потрачено {spent}, осталось {cash.Value}`)
check(#t1.Purchased:GetChildren() == 12 and visible(t1) == "Rebirth", "куплено всё, осталось перерождение; видны: " .. visible(t1))
check(lastMessage(alice) == string.format(Config.Text.Bought, "Мега-дроппер"), "сообщение о покупке")
check(buttonFor(t1, "Rebirth").Label.TextLabel.Text == "Перерождение\n+50% к доходу\n$250,000", "надпись кнопки перерождения")

wait(1.2)
local fresh = nil
for _, candidate in t1.Ores:GetChildren() do
	if candidate:GetAttribute("Value") == 100 then
		fresh = candidate
	end
end
check(fresh ~= nil, "мега-дроппер роняет руду ценой 100")
check(fresh ~= nil and (fresh.Size - Vector3.new(1.8, 1.8, 1.8)).Magnitude < EPS, `руда мега-дроппера крупная: {fresh and fresh.Size}`)
local purchased = t1.Purchased
hit(purchased.Upgrader1.Beam, fresh)
hit(purchased.Upgrader1.Beam, fresh)
check(fresh:GetAttribute("Value") == 200, "улучшитель умножает цену один раз")
hit(purchased.Upgrader2.Beam, fresh)
hit(purchased.Upgrader3.Beam, fresh)
check(fresh:GetAttribute("Value") == 600, "три улучшителя дают x6")
hit(purchased.Upgrader1.Beam, alice.Character.LeftFoot)
local before = cash.Value
hit(hitbox, fresh)
touch(collectPad, alice)
check(cash.Value == before + 600, "улучшенная руда продана за 600")

print("4. Перерождение")
touch(buttonFor(t1, "Rebirth"), alice)
check(rebirths.Value == 1 and cash.Value == 0, "перерождение обнуляет деньги и даёт уровень")
check(#t1.Purchased:GetChildren() == 0 and #t1.Ores:GetChildren() == 0 and visible(t1) == "Dropper1", "завод сброшен")
check(lastMessage(alice) == string.format(Config.Text.Rebirth, "1.5"), "сообщение о перерождении")
wait(1.5)
check(#t1.Ores:GetChildren() == 0, "старые дропперы остановлены")
touch(buttonFor(t1, "Dropper1"), alice)
hit(hitbox, t1.Ores:GetChildren()[1])
touch(collectPad, alice)
check(cash.Value == 1, "множитель x1.5: собран $1, $0.5 остались в банке")
wait(1.2)
hit(hitbox, t1.Ores:GetChildren()[1])
touch(collectPad, alice)
check(cash.Value == 3, "остаток банка не теряется")

print("5. Второй игрок")
local bob = addPlayer("Bob", 202)
touch(buttonFor(t1, "Dropper2"), bob)
touch(collectPad, bob)
check(t1.Purchased:FindFirstChild("Dropper2") == nil and bob.leaderstats[Config.CashStat].Value == 0, "чужой завод не слушается")
touch(tycoons.Tycoon2.Essentials.ClaimPad, bob)
check(bob:GetAttribute("Tycoon") == "Tycoon2", "второй игрок занял свой завод")
touch(tycoons.Tycoon3.Essentials.ClaimPad, alice)
check(tycoons.Tycoon3.Essentials:FindFirstChild("ClaimPad") ~= nil, "второй завод одному игроку не выдаётся")
check(lastMessage(alice) == Config.Text.AlreadyOwner, "сообщение о втором заводе")

local character = spawnCharacter(alice)
wait(0.5)
local pivot = pivots[character]
check(pivot ~= nil and (pivot.Position - claimPad.CFrame.Position).Magnitude < 5, "владелец возрождается у своего завода")
check(pivot ~= nil and pivot.LookVector:Dot(hitbox.CFrame.Position - pivot.Position) > 0, "и смотрит внутрь завода")

print("6. Выход, сохранение и возвращение")
wait(1.2)
hit(hitbox, t1.Ores:GetChildren()[1])
removePlayer(alice)
local saved = savedData.Player_101
check(saved ~= nil and saved.cash == 4 and saved.rebirths == 1, "сохранены деньги вместе с несобранным банком")
check(saved ~= nil and #saved.items == 1 and saved.items[1] == "Dropper1", "сохранены покупки")
check(
	t1.Essentials:FindFirstChild("ClaimPad") ~= nil and #t1.Buttons:GetChildren() == 0 and #t1.Purchased:GetChildren() == 0
		and #t1.Ores:GetChildren() == 0 and sign.Text == Config.Text.Unclaimed,
	"завод освобождён после выхода владельца"
)

alice = addPlayer("Alice", 101)
cash = alice.leaderstats[Config.CashStat]
check(cash.Value == 4 and alice.leaderstats[Config.RebirthStat].Value == 1, "прогресс загружен")

print("7. Интерфейс клиента")
localPlayer = alice
guard(execute)(game:GetService("StarterPlayer").StarterPlayerScripts.TycoonHud, true)
local hud = alice.PlayerGui:FindFirstChild("TycoonHud")
check(hud ~= nil, "интерфейс создан")
if hud then
	check(hud.Cash.Text == "$4", "деньги на экране: " .. hud.Cash.Text)
	check(hud.Multiplier.Visible and hud.Multiplier.Text == string.format(Config.Text.Multiplier, "1.5"), "множитель на экране")
	check(hud.Hint.Visible and hud.Hint.Text == Config.Text.Hint, "подсказка видна без завода")
	check(hud.Toast.Visible == false, "сообщение скрыто")

	local t4 = tycoons.Tycoon4
	touch(t4.Essentials.ClaimPad, alice)
	wait(0.2)
	check(t4.Purchased:FindFirstChild("Dropper1") ~= nil and visible(t4) == "Dropper2", "покупки восстановлены на новом заводе")
	check(hud.Hint.Visible == false, "подсказка скрыта после захвата")
	check(hud.Toast.Visible and hud.Toast.Text == Config.Text.Claimed and hud.Toast.TextTransparency == 0, "сообщение показано")
	cash.Value = 2500000
	wait(0.2)
	check(hud.Cash.Text == "$2.5M", "деньги на экране обновились: " .. hud.Cash.Text)
	wait(4)
	check(hud.Toast.TextTransparency == 1, "сообщение погасло")
end

print("8. Остановка сервера")
for _, callback in closeCallbacks do
	guard(callback)()
end
check(#closeCallbacks == 1 and savedData.Player_202 ~= nil, "при остановке сохранены все игроки")
check(savedData.Player_101.cash == 2500000, "сохранено последнее значение денег")
check(#warnings == 0, "предупреждения за игру: " .. table.concat(warnings, "; "))

print("9. DataStore недоступен")
dataStoreFails = true
local carol = addPlayer("Carol", 303)
check(#warnings == 2, `два предупреждения о сохранении, получено {#warnings}`)
touch(tycoons.Tycoon5.Essentials.ClaimPad, carol)
check(carol:GetAttribute("Tycoon") == "Tycoon5", "играть можно и без сохранения")
dataStoreFails = false
removePlayer(carol)
check(savedData.Player_303 == nil, "после сбоя загрузки сохранение не перезаписывается")

print(`\nПроверок: {checks}, провалов: {failures}`)
process.exit(if failures == 0 then 0 else 1)
