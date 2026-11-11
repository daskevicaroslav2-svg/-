--!strict
-- Меню: выбор стороны, магазин, выбор ножа и скинов с предпросмотром.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arsenal = require(Shared.Arsenal)
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Game = require(script.Parent.Game)
local Sounds = require(script.Parent.Sounds)
local Ui = require(script.Parent.Ui)

local Menus = {}

local Text = Config.Text
local player = Game.player

local CATEGORIES = { "pistol", "smg", "rifle", "sniper", "grenade", "gear" }
local RED = Color3.fromRGB(255, 110, 110)
local GREEN = Color3.fromRGB(120, 230, 130)
local IDENTITY = CFrame.new()

local modal: TextButton
local panels: { [string]: Frame } = {}
local refreshers: { [string]: () -> () } = {}
local current: string? = nil

-- Предпросмотр в меню скинов
local viewport: ViewportFrame
local previewCamera: Camera
local previewCenter = Vector3.new(0, 0, 0)
local previewDistance = 3
local previewAngle = 0

-- Выбор игрока до подтверждения сервером
local selectedKey = "Knife"
local chosenKnife: string? = nil
local chosenSkins: { [string]: string } = {}

function Menus.isOpen(): boolean
	return current ~= nil
end

local function hide()
	if current then
		panels[current].Visible = false
		current = nil
		modal.Visible = false
	end
end

function Menus.open(name: string)
	if current == name or not panels[name] then
		return
	end
	hide()
	current = name
	modal.Visible = true
	panels[name].Visible = true
	refreshers[name]()
	Sounds.play("Click", 0.3)
end

-- Меню выбора стороны нельзя закрыть, пока сторона не выбрана
function Menus.close()
	if current ~= "team" or Game.team() ~= "" then
		hide()
	end
end

function Menus.toggle(name: string)
	if current == name then
		Menus.close()
	else
		Menus.open(name)
	end
end

local function window(name: string, width: number, height: number, title: string, parent: Instance): Frame
	local frame = Ui.frame({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 21,
		Parent = parent,
	}, { Ui.corner(12), Ui.stroke(Color3.fromRGB(70, 76, 90), 1) })
	Ui.label({ Name = "Title", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 34), Text = title, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = frame })
	panels[name] = frame
	return frame
end

local function clearButtons(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

---------------------------------------------------------------------------
-- Выбор стороны

local function buildTeam(parent: Instance)
	local frame = window("team", 620, 330, Text.ChooseTeam, parent)
	local counts: { [string]: TextLabel } = {}
	for index, team in { "T", "CT" } do
		local button = Ui.button({
			Name = team,
			Position = UDim2.fromOffset(30 + (index - 1) * 290, 64),
			Size = UDim2.fromOffset(270, 170),
			BackgroundColor3 = Ui.teamColors[team],
			Text = if team == "T" then Text.TeamT else Text.TeamCT,
			TextSize = 28,
			ZIndex = 22,
			Parent = frame,
		}, { Ui.corner(10) })
		counts[team] = Ui.label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, ZIndex = 23, Parent = button })
		button.Activated:Connect(function()
			Net.send("Team", team)
			hide()
		end)
	end
	local auto = Ui.button({ Name = "Auto", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(200, 40), Text = Text.Auto, TextSize = 20, ZIndex = 22, Parent = frame }, { Ui.corner(8) })
	auto.Activated:Connect(function()
		Net.send("Team", "Auto")
		hide()
	end)
	refreshers.team = function()
		for team, label in counts do
			local count = 0
			for _, other in Players:GetPlayers() do
				if other:GetAttribute("Team") == team then
					count += 1
				end
			end
			label.Text = string.format(Text.Players, count)
		end
	end
end

---------------------------------------------------------------------------
-- Магазин

local function buildShop(parent: Instance)
	local frame = window("shop", 820, 470, Text.Shop, parent)
	local money = Ui.label({ Name = "Money", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 12), Size = UDim2.fromOffset(200, 34), TextSize = 24, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22, Parent = frame })
	local grid = Ui.new("Frame", { Name = "Grid", Position = UDim2.fromOffset(20, 60), Size = UDim2.new(1, -40, 1, -80), BackgroundTransparency = 1, ZIndex = 22, Parent = frame }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(252, 186), CellPadding = UDim2.fromOffset(12, 12), FillDirectionMaxCells = 3, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local columns: { [string]: Frame } = {}
	for order, category in CATEGORIES do
		columns[category] = Ui.frame({ Name = category, LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(30, 33, 42), ZIndex = 22, Parent = grid }, {
			Ui.corner(8),
			Ui.list(Enum.FillDirection.Vertical, 4),
			Ui.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
	end

	local function item(category: string, order: number, id: string, name: string, price: number, owned: boolean)
		local affordable = Game.money() >= price
		local button = Ui.button({
			Name = id,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 30),
			Text = "  " .. name,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if owned then GREEN elseif affordable then Ui.white else RED,
			ZIndex = 23,
			Parent = columns[category],
		}, { Ui.corner(6) })
		Ui.label({ Size = UDim2.new(1, -8, 1, 0), Text = "$" .. price, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = button.TextColor3, ZIndex = 24, Parent = button })
		button.Activated:Connect(function()
			Net.send("Buy", id)
		end)
	end

	refreshers.shop = function()
		money.Text = "$" .. Game.money()
		for _, category in CATEGORIES do
			clearButtons(columns[category])
			Ui.label({ Name = "Header", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), Text = (Text.Categories :: any)[category], TextSize = 14, TextTransparency = 0.25, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = columns[category] })
		end
		local team = Game.team()
		for order, weapon in Weapons.list do
			if weapon.kind ~= "knife" and (not weapon.team or weapon.team == team) then
				item(weapon.category, order, weapon.id, weapon.name, weapon.price, weapon.kind == "gun" and Game.owns(weapon.id))
			end
		end
		item("gear", 1, "Armor", Text.Armor, Config.ArmorPrice, Game.armor() >= 100)
	end
	for _, name in { "Money", "Primary", "Secondary", "Grenades", "Armor", "Team" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if current == "shop" then
				refreshers.shop()
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Ножи и скины

local function knife(): string
	return chosenKnife or Game.knife()
end

local function skinOf(key: string): string
	return chosenSkins[key] or Game.skin(key) or "Default"
end

local function showPreview(modelId: string, skinId: string)
	for _, child in viewport:GetChildren() do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end
	local rig = Arsenal.rig(modelId, skinId, Game.team())
	if not rig then
		return
	end
	local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, desc in rig.parts do
		if desc.group == "gun" then
			local part = Build.part(desc)
			part.Anchored = true
			part.CFrame = desc.rest * (desc.fix or IDENTITY)
			part.Parent = viewport
			local position, reach = desc.rest.Position, desc.size.Magnitude / 2
			low = Vector3.new(math.min(low.X, position.X - reach), math.min(low.Y, position.Y - reach), math.min(low.Z, position.Z - reach))
			high = Vector3.new(math.max(high.X, position.X + reach), math.max(high.Y, position.Y + reach), math.max(high.Z, position.Z + reach))
		end
	end
	previewCenter = (low + high) / 2
	previewDistance = math.max((high - low).Magnitude * 0.62, 1)
end

local function buildLoadout(parent: Instance)
	local frame = window("loadout", 900, 500, Text.Loadout, parent)
	local function column(name: string, x: number, width: number): ScrollingFrame
		return Ui.new("ScrollingFrame", {
			Name = name,
			Position = UDim2.fromOffset(x, 60),
			Size = UDim2.new(0, width, 1, -80),
			BackgroundColor3 = Color3.fromRGB(30, 33, 42),
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 22,
			Parent = frame,
		}, {
			Ui.list(Enum.FillDirection.Vertical, 4),
			Ui.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12) }),
		})
	end
	local items = column("Items", 20, 230)
	local skins = column("Skins", 262, 270)
	viewport = Ui.new("ViewportFrame", {
		Name = "Preview",
		Position = UDim2.fromOffset(548, 60),
		Size = UDim2.fromOffset(332, 330),
		BackgroundColor3 = Color3.fromRGB(26, 28, 36),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(190, 190, 190),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1.2, -0.8),
		ZIndex = 22,
		Parent = frame,
	}, { Ui.corner(8) })
	previewCamera = Ui.new("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = previewCamera
	local caption = Ui.label({ Name = "Caption", Position = UDim2.fromOffset(548, 398), Size = UDim2.fromOffset(332, 28), TextSize = 20, ZIndex = 22, Parent = frame })
	local rarity = Ui.label({ Name = "Rarity", Position = UDim2.fromOffset(548, 428), Size = UDim2.fromOffset(332, 22), TextSize = 15, ZIndex = 22, Parent = frame })

	local function entry(container: Instance, order: number, label: string, selected: boolean, color: Color3?, action: () -> ())
		local button = Ui.button({
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 30),
			Text = "  " .. label,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or Ui.white,
			BackgroundColor3 = if selected then Color3.fromRGB(64, 72, 92) else Color3.fromRGB(40, 44, 54),
			ZIndex = 23,
			Parent = container,
		}, { Ui.corner(6) })
		button.Activated:Connect(action)
	end
	local function header(container: Instance, order: number, label: string)
		Ui.label({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), Text = label, TextSize = 14, TextTransparency = 0.25, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = container })
	end

	local function refresh()
		clearButtons(items)
		clearButtons(skins)
		local names: { [string]: string } = Text.KnifeNames
		header(items, 0, Text.Knives)
		for order, knifeId in Arsenal.knives() do
			entry(items, order, names[knifeId] or knifeId, knifeId == knife(), nil, function()
				chosenKnife = knifeId
				selectedKey = "Knife"
				Net.send("KnifeType", knifeId)
				Sounds.play("Click", 0.3)
				refresh()
			end)
		end
		header(items, 100, Text.SkinsFor)
		entry(items, 101, Text.KnifeSkin, selectedKey == "Knife", nil, function()
			selectedKey = "Knife"
			refresh()
		end)
		for order, weapon in Weapons.list do
			if weapon.kind == "gun" then
				entry(items, 101 + order, weapon.name, selectedKey == weapon.id, nil, function()
					selectedKey = weapon.id
					refresh()
				end)
			end
		end

		local modelId = Weapons.modelId(selectedKey, knife())
		local equipped = skinOf(selectedKey)
		local shown: any = nil
		for order, skin in Arsenal.skins(modelId) do
			local chosen = skin.id == equipped
			if chosen or not shown then
				shown = skin
			end
			local label = if chosen then skin.name .. "  ✓" else skin.name
			entry(skins, order, label, chosen, Config.RarityColors[skin.rarity], function()
				chosenSkins[selectedKey] = skin.id
				Net.send("Skin", selectedKey, skin.id)
				Sounds.play("Click", 0.3)
				refresh()
			end)
		end
		local weapon = Weapons.get(selectedKey)
		caption.Text = if selectedKey == "Knife" then names[knife()] or knife() elseif weapon then weapon.name else selectedKey
		rarity.Text = if shown then `{shown.name} · {Text.Rarity[shown.rarity] or ""}` else ""
		rarity.TextColor3 = if shown then Config.RarityColors[shown.rarity] or Ui.white else Ui.white
		showPreview(modelId, if shown then shown.id else "Default")
	end
	refreshers.loadout = refresh
end

-- Вращает модель в предпросмотре
function Menus.update(dt: number)
	if current == "loadout" then
		previewAngle += dt * 0.9
		local offset = Vector3.new(math.cos(previewAngle), 0.28, math.sin(previewAngle)).Unit * previewDistance
		previewCamera.CFrame = CFrame.lookAt(previewCenter + offset, previewCenter)
	end
end

function Menus.init(gui: ScreenGui)
	-- Невидимая кнопка с Modal освобождает курсор в режиме от первого лица
	modal = Ui.new("TextButton", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Modal = true,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	modal.Activated:Connect(Menus.close)
	buildTeam(gui)
	buildShop(gui)
	buildLoadout(gui)
end

return Menus
