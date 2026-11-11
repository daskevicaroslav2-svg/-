--!strict
-- Один завод: владелец, кнопки покупки, дропперы, лента и сборщик денег.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(script.Parent.PlayerData)

local notifyEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent

local COLOR_AFFORDABLE = Color3.fromRGB(80, 255, 120)
local COLOR_EXPENSIVE = Color3.fromRGB(255, 95, 95)
local ORE_PHYSICS = PhysicalProperties.new(1, 0.5, 0, 1, 100)
-- Трение ленты меньше 1, иначе кубик руды опрокидывается при разгоне
local BELT_PHYSICS = PhysicalProperties.new(1, 0.6, 0, 100, 100)
local NOTICE_COOLDOWN = 1.5

type Button = {
	part: BasePart,
	item: string, -- имя модели в Items ("" у кнопки перерождения)
	price: number,
	requires: string, -- предмет, после покупки которого кнопка появляется
	title: string,
	rebirth: boolean,
}

local Tycoon = {}
Tycoon.__index = Tycoon

type Self = {
	model: Model,
	essentials: Instance,
	buttonFolder: Instance,
	purchasedFolder: Folder,
	oreFolder: Folder,
	storage: Folder, -- некупленные предметы и скрытые кнопки лежат в ServerStorage
	claimPad: BasePart,
	collectLabel: TextLabel,
	signLabels: { TextLabel },
	spawnCFrame: CFrame,
	items: { [string]: Instance },
	buttons: { Button },
	owner: Player?,
	purchased: { [string]: boolean },
	bank: number, -- заработано, но ещё не собрано
	session: number, -- растёт при сбросе, чтобы остановить старые циклы дропперов
	lastPurchase: number,
	cashConnection: RBXScriptConnection?,
}

export type Tycoon = typeof(setmetatable({} :: Self, Tycoon))

local byOwner: { [Player]: Tycoon } = {}
local lastNotice: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function notify(player: Player, text: string, kind: string)
	notifyEvent:FireClient(player, text, kind)
end

-- Касание срабатывает много раз подряд: одинаковые сообщения не должны спамить
local function notifyThrottled(player: Player, text: string, kind: string)
	local now = os.clock()
	if now - (lastNotice[player] or -math.huge) >= NOTICE_COOLDOWN then
		lastNotice[player] = now
		notify(player, text, kind)
	end
end

local function playerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function need(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	if not child then
		error(`не найден {parent:GetFullName()}.{name}`)
	end
	return child
end

local function needPart(parent: Instance, name: string): BasePart
	local child = need(parent, name)
	if not child:IsA("BasePart") then
		error(`{child:GetFullName()} должен быть деталью (Part)`)
	end
	return child
end

local function attrNumber(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function attrString(instance: Instance, name: string, default: string): string
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" then value else default
end

-- Неизвестное название материала не должно ломать дроппер
local function oreMaterial(name: string): Enum.Material
	local ok, material = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(material) == "EnumItem" then
		return material :: any
	end
	return Enum.Material.SmoothPlastic
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function newLabel(parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = ""
	label.Parent = parent
	return label
end

-- Парящая надпись над деталью, высота подстраивается под число строк
local function billboard(adornee: BasePart, text: string): TextLabel
	local lines = #text:split("\n")
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(8, 1.3 * lines)
	gui.StudsOffset = Vector3.new(0, 2.5 + 0.65 * lines, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	local label = newLabel(gui)
	label.Text = text
	gui.Parent = adornee
	return label
end

local function surfaceLabel(part: BasePart, face: Enum.NormalId): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Adornee = part
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = newLabel(gui)
	gui.Parent = part
	return label
end

function Tycoon.setSign(self: Tycoon, text: string)
	for _, label in self.signLabels do
		label.Text = text
	end
end

function Tycoon.updateCollectLabel(self: Tycoon)
	self.collectLabel.Text = string.format(Config.Text.Collect, Format.money(self.bank))
end

-- Показывает кнопки, которые владелец может купить сейчас, и красит их по доступности
function Tycoon.refreshButtons(self: Tycoon)
	local owner = self.owner
	local profile = if owner then PlayerData.get(owner) else nil
	local cash = if profile then profile.cash.Value else 0
	for _, button in self.buttons do
		local unlocked = button.requires == "" or self.purchased[button.requires] == true
		local visible = owner ~= nil and unlocked and not self.purchased[button.item]
		button.part.Parent = if visible then self.buttonFolder else self.storage
		button.part.Color = if cash >= button.price then COLOR_AFFORDABLE else COLOR_EXPENSIVE
	end
end

function Tycoon.spawnOre(self: Tycoon, dropper: Instance, spout: BasePart)
	local size = attrNumber(dropper, "OreSize", 1.2)
	local color = dropper:GetAttribute("OreColor")

	local ore = Instance.new("Part")
	ore.Name = "Ore"
	ore.Size = Vector3.new(size, size, size)
	ore.Color = if typeof(color) == "Color3" then color else Color3.fromRGB(160, 160, 160)
	ore.Material = oreMaterial(attrString(dropper, "OreMaterial", "SmoothPlastic"))
	ore.TopSurface = Enum.SurfaceType.Smooth
	ore.BottomSurface = Enum.SurfaceType.Smooth
	ore.CustomPhysicalProperties = ORE_PHYSICS
	ore.CollisionGroup = "Ore"
	ore.CFrame = CFrame.new(spout.CFrame.Position - Vector3.new(0, spout.Size.Y / 2 + size / 2 + 0.2, 0))
	ore:SetAttribute("Value", attrNumber(dropper, "OreValue", 1))
	ore.Parent = self.oreFolder
	-- Физику руды считает сервер: клиент не сможет её утащить или подёргать
	pcall(function()
		ore:SetNetworkOwner(nil)
	end)
	Debris:AddItem(ore, Config.OreLifetime)
end

function Tycoon.startDropper(self: Tycoon, dropper: Instance)
	local spout = dropper:FindFirstChild("Spout")
	if not spout or not spout:IsA("BasePart") then
		warn(`[Tycoon] У дроппера {dropper:GetFullName()} нет детали Spout`)
		return
	end
	local session = self.session
	local interval = math.max(0.1, attrNumber(dropper, "DropInterval", 1))
	task.spawn(function()
		while self.session == session and dropper.Parent == self.purchasedFolder do
			self:spawnOre(dropper, spout)
			task.wait(interval)
		end
	end)
end

-- Ставит купленный предмет на завод
function Tycoon.activate(self: Tycoon, name: string)
	local item = self.items[name]
	if not item or self.purchased[name] then
		return
	end
	self.purchased[name] = true
	item.Parent = self.purchasedFolder
	if item:GetAttribute("OreValue") ~= nil then
		self:startDropper(item)
	end
end

function Tycoon.resetProgress(self: Tycoon)
	self.session += 1
	self.bank = 0
	table.clear(self.purchased)
	for _, item in self.items do
		item.Parent = self.storage
	end
	self.oreFolder:ClearAllChildren()
	self:updateCollectLabel()
end

-- Луч улучшителя умножает цену руды, каждую руду только один раз
function Tycoon.connectUpgrader(self: Tycoon, upgrader: Instance, beam: BasePart)
	local mark = "Upgraded_" .. upgrader.Name
	beam.Touched:Connect(function(hit)
		if hit.Parent ~= self.oreFolder or hit:GetAttribute(mark) then
			return
		end
		hit:SetAttribute(mark, true)
		hit:SetAttribute("Value", attrNumber(hit, "Value", 0) * attrNumber(upgrader, "Multiplier", 1))
		hit.Color = hit.Color:Lerp(beam.Color, 0.6)
		hit.Material = Enum.Material.Neon
	end)
end

function Tycoon.collectOre(self: Tycoon, ore: BasePart)
	if ore.Parent ~= self.oreFolder then
		return
	end
	local value = attrNumber(ore, "Value", 0)
	ore:Destroy()
	local profile = if self.owner then PlayerData.get(self.owner) else nil
	if profile then
		self.bank += value * (1 + Config.RebirthBonus * profile.rebirths.Value)
		self:updateCollectLabel()
	end
end

function Tycoon.collect(self: Tycoon, player: Player)
	if player ~= self.owner then
		return
	end
	local profile = PlayerData.get(player)
	local amount = math.floor(self.bank)
	if not profile or amount <= 0 then
		return
	end
	self.bank -= amount
	profile.cash.Value += amount
	self:updateCollectLabel()
end

function Tycoon.claim(self: Tycoon, player: Player)
	if self.owner then
		return
	end
	if byOwner[player] then
		notifyThrottled(player, Config.Text.AlreadyOwner, "error")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return -- сохранение ещё загружается
	end

	self.owner = player
	byOwner[player] = self
	self.claimPad.Parent = self.storage
	self:setSign(string.format(Config.Text.Owner, player.DisplayName))
	player:SetAttribute("Tycoon", self.model.Name)
	for name in profile.items do
		self:activate(name)
	end
	self.cashConnection = profile.cash.Changed:Connect(function()
		self:refreshButtons()
	end)
	self:refreshButtons()
	notify(player, Config.Text.Claimed, "success")
end

function Tycoon.rebirth(self: Tycoon, player: Player, profile: PlayerData.Profile)
	profile.rebirths.Value += 1
	profile.cash.Value = 0
	table.clear(profile.items)
	self:resetProgress()
	self:refreshButtons()
	local multiplier = Format.multiplier(1 + Config.RebirthBonus * profile.rebirths.Value)
	notify(player, string.format(Config.Text.Rebirth, multiplier), "success")
end

function Tycoon.onButtonTouched(self: Tycoon, button: Button, hit: BasePart)
	local player = playerFromHit(hit)
	if not player or player ~= self.owner or button.part.Parent ~= self.buttonFolder then
		return
	end
	local profile = PlayerData.get(player)
	local now = os.clock()
	if not profile or now - self.lastPurchase < Config.PurchaseCooldown then
		return
	end
	local missing = button.price - profile.cash.Value
	if missing > 0 then
		notifyThrottled(player, string.format(Config.Text.NotEnough, Format.money(missing)), "error")
		return
	end

	self.lastPurchase = now
	if button.rebirth then
		self:rebirth(player, profile)
		return
	end
	profile.cash.Value -= button.price
	profile.items[button.item] = true
	self:activate(button.item)
	self:refreshButtons()
	notify(player, string.format(Config.Text.Bought, button.title), "success")
end

function Tycoon.addButton(self: Tycoon, part: BasePart)
	local button: Button = {
		part = part,
		item = attrString(part, "Item", ""),
		price = attrNumber(part, "Price", 0),
		requires = attrString(part, "Requires", ""),
		title = attrString(part, "Label", part.Name),
		rebirth = part:GetAttribute("Rebirth") == true,
	}
	part.Parent = self.storage
	if not button.rebirth and not self.items[button.item] then
		warn(`[Tycoon] Кнопка {part:GetFullName()} продаёт неизвестный предмет "{button.item}"`)
		return
	end

	local title = button.title
	if button.rebirth then
		title = string.format(Config.Text.RebirthButton, title, Config.RebirthBonus * 100)
	end
	local price = if button.price > 0 then Format.money(button.price) else Config.Text.Free
	billboard(part, `{title}\n{price}`)
	part.Touched:Connect(function(hit)
		self:onButtonTouched(button, hit)
	end)
	table.insert(self.buttons, button)
end

function Tycoon.new(model: Model): Tycoon
	local essentials = need(model, "Essentials")
	local buttonFolder = need(model, "Buttons")
	local itemFolder = need(model, "Items")
	local claimPad = needPart(essentials, "ClaimPad")
	local collectPad = needPart(essentials, "CollectPad")
	local sign = needPart(essentials, "OwnerSign")
	local belt = needPart(need(essentials, "Conveyor"), "Belt")
	local hitbox = needPart(need(essentials, "Collector"), "Hitbox")

	local storageRoot = ServerStorage:FindFirstChild("TycoonStorage") or newFolder("TycoonStorage", ServerStorage)

	-- Владелец появляется над площадкой входа лицом к конвейеру
	local spawnPosition = claimPad.CFrame.Position + Vector3.new(0, 4, 0)
	local beltPosition = belt.CFrame.Position

	local self: Tycoon = setmetatable({
		model = model,
		essentials = essentials,
		buttonFolder = buttonFolder,
		purchasedFolder = newFolder("Purchased", model),
		oreFolder = newFolder("Ores", model),
		storage = newFolder(model.Name, storageRoot),
		claimPad = claimPad,
		collectLabel = billboard(collectPad, string.format(Config.Text.Collect, Format.money(0))),
		signLabels = { surfaceLabel(sign, Enum.NormalId.Front), surfaceLabel(sign, Enum.NormalId.Back) },
		spawnCFrame = CFrame.lookAt(spawnPosition, Vector3.new(beltPosition.X, spawnPosition.Y, beltPosition.Z)),
		items = {},
		buttons = {},
		owner = nil,
		purchased = {},
		bank = 0,
		session = 0,
		lastPurchase = -math.huge,
		cashConnection = nil,
	} :: Self, Tycoon)

	-- Лента: неподвижная деталь со скоростью везёт всё, что на ней лежит.
	-- Направление выбирается в сторону сборщика, как бы ни была повёрнута деталь.
	local direction = belt.CFrame.LookVector
	if direction:Dot(hitbox.CFrame.Position - beltPosition) < 0 then
		direction = -direction
	end
	belt.CustomPhysicalProperties = BELT_PHYSICS
	belt.AssemblyLinearVelocity = direction * Config.ConveyorSpeed

	for _, item in itemFolder:GetChildren() do
		self.items[item.Name] = item
		item.Parent = self.storage
		-- Улучшитель: модель с атрибутом Multiplier и деталью-лучом Beam
		local beam = item:FindFirstChild("Beam")
		if item:GetAttribute("Multiplier") ~= nil and beam and beam:IsA("BasePart") then
			self:connectUpgrader(item, beam)
		end
	end
	for _, child in buttonFolder:GetChildren() do
		if child:IsA("BasePart") then
			self:addButton(child)
		end
	end

	billboard(claimPad, Config.Text.ClaimPad)
	claimPad.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			self:claim(player)
		end
	end)
	collectPad.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			self:collect(player)
		end
	end)
	hitbox.Touched:Connect(function(hit)
		self:collectOre(hit)
	end)

	self:setSign(Config.Text.Unclaimed)
	return self
end

function Tycoon.ownedBy(player: Player): Tycoon?
	return byOwner[player]
end

-- Освобождает завод игрока (выход из игры): несобранные деньги уходят владельцу
function Tycoon.release(player: Player)
	local self = byOwner[player]
	if not self then
		return
	end
	byOwner[player] = nil
	self.owner = nil
	if self.cashConnection then
		self.cashConnection:Disconnect()
		self.cashConnection = nil
	end
	local profile = PlayerData.get(player)
	if profile then
		profile.cash.Value += math.floor(self.bank)
	end
	self:resetProgress()
	self.claimPad.Parent = self.essentials
	self:refreshButtons()
	self:setSign(Config.Text.Unclaimed)
	player:SetAttribute("Tycoon", nil)
end

return Tycoon
