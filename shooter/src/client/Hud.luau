--!strict
-- Интерфейс боя: счёт и таймер, здоровье, патроны, деньги, прицел, лента убийств, эффекты экрана.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Game = require(script.Parent.Game)
local Sounds = require(script.Parent.Sounds)
local Ui = require(script.Parent.Ui)

local Hud = {}

local Text = Config.Text
local player = Game.player

local RED = Color3.fromRGB(255, 90, 90)
local GREEN = Color3.fromRGB(120, 230, 130)
local SLOT_KEYS: { [number]: string } = { "1", "2", "3", "4" }

local timerLabel: TextLabel, phaseLabel: TextLabel
local scoreLabels: { [string]: TextLabel } = {}
local aliveLabels: { [string]: TextLabel } = {}
local healthLabel: TextLabel, armorLabel: TextLabel
local ammoLabel: TextLabel, weaponLabel: TextLabel, weaponList: Frame
local moneyLabel: TextLabel, shopHint: TextLabel, bhopLabel: TextLabel
local crosshair: Frame
local crossLines: { Frame } = {}
local hitmarker: Frame
local scopeOverlay: Frame, flashOverlay: Frame, hurtOverlay: Frame, smokeOverlay: Frame
local killfeed: Frame
local banner: Frame, bannerTitle: TextLabel, bannerSub: TextLabel
local noticeLabel: TextLabel, statusLabel: TextLabel, controlsLabel: TextLabel

local flashStart, flashDuration = 0, 0
local hurtUntil = 0
local hitUntil = 0
local bannerUntil = 0
local noticeUntil = 0
local equipped: string? = nil

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function colored(text: string, team: string): string
	return `<font color="{hex(Ui.teamColors[team] or Ui.white)}">{escape(text)}</font>`
end

local function panel(props: { [string]: any }, children: { Instance }?): Frame
	props.BackgroundTransparency = props.BackgroundTransparency or 0.35
	local frame = Ui.frame(props, children)
	Ui.corner(8).Parent = frame
	return frame
end

local function overlay(parent: Instance, color: Color3, order: number): Frame
	return Ui.frame({
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		ZIndex = order,
		Parent = parent,
	})
end

local function refreshWeapons()
	for _, child in weaponList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local grenades = Game.grenades()
	for order, weaponId in Game.weapons() do
		local weapon = Weapons.get(weaponId)
		if weapon then
			local name = weapon.name
			if weapon.kind == "grenade" then
				local count = 0
				for _, id in grenades do
					if id == weaponId then
						count += 1
					end
				end
				if count > 1 then
					name ..= " x" .. count
				end
			end
			Ui.label({
				Name = weaponId,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 20),
				Text = `{name}  [{SLOT_KEYS[weapon.slot] or ""}]`,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTransparency = if weaponId == equipped then 0 else 0.45,
				TextStrokeTransparency = 0.6,
				Parent = weaponList,
			})
		end
	end
end

-- Оружие в руках и патроны; mag = nil скрывает счётчик (нож, гранаты)
function Hud.setWeapon(weaponId: string?, mag: number?, reserve: number?)
	equipped = weaponId
	local weapon = if weaponId then Weapons.get(weaponId) else nil
	weaponLabel.Text = if weapon then weapon.name else ""
	ammoLabel.Text = if mag and reserve then `{mag} / {reserve}` else ""
	ammoLabel.TextColor3 = if mag and weapon and mag <= weapon.mag * 0.25 then RED else Ui.white
	refreshWeapons()
end

-- Прицел расходится вместе с разбросом (в градусах)
function Hud.setCrosshair(spread: number, visible: boolean)
	crosshair.Visible = visible
	if not visible then
		return
	end
	local gap = 4 + spread * 14
	crossLines[1].Position = UDim2.fromOffset(-1, -gap - 9)
	crossLines[2].Position = UDim2.fromOffset(-1, gap)
	crossLines[3].Position = UDim2.fromOffset(-gap - 9, -1)
	crossLines[4].Position = UDim2.fromOffset(gap, -1)
end

function Hud.setScope(on: boolean)
	scopeOverlay.Visible = on
end

function Hud.setBhop(hops: number)
	bhopLabel.Visible = hops > 0
	bhopLabel.Text = string.format("Банихоп x%.2f", 1 + hops * Config.Bhop.step)
end

function Hud.notice(text: string, bad: boolean?)
	noticeLabel.Text = text
	noticeLabel.TextColor3 = if bad then RED else Ui.white
	noticeLabel.Visible = true
	noticeUntil = os.clock() + 2.2
end

function Hud.showBanner(title: string, sub: string, color: Color3, duration: number)
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerSub.Text = sub
	banner.Visible = true
	bannerUntil = os.clock() + duration
end

-- Строка под прицелом: наблюдение, ожидание раунда
function Hud.setStatus(text: string)
	statusLabel.Text = text
	statusLabel.Visible = text ~= ""
end

local function addKill(killer: string, killerTeam: string, victim: string, victimTeam: string, weaponId: string, headshot: boolean)
	local weapon = Weapons.get(weaponId)
	local how = if weapon then weapon.name else "погиб"
	if headshot then
		how ..= " в голову"
	end
	local text = `{colored(victim, victimTeam)} — {escape(how)}`
	if killer ~= "" then
		text = `{colored(killer, killerTeam)}  [{escape(how)}]  {colored(victim, victimTeam)}`
	end
	local entry = panel({ Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 0.45, Parent = killfeed }, {
		Ui.label({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), RichText = true, Text = text, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right }),
	})
	task.delay(6, function()
		entry:Destroy()
	end)
end

local function smokeDensity(position: Vector3): number
	local smokes = Workspace:FindFirstChild("Smokes")
	local density = 0
	if smokes then
		for _, cloud in smokes:GetChildren() do
			local center, radius = cloud:GetAttribute("Center"), cloud:GetAttribute("Radius")
			if typeof(center) == "Vector3" and typeof(radius) == "number" then
				-- Внутри облака почти ничего не видно, у края дым редеет
				density = math.max(density, math.clamp((radius - (position - center).Magnitude) / 3, 0, 1))
			end
		end
	end
	return density
end

function Hud.update(_dt: number, camera: Camera)
	local now = os.clock()
	local phase = Game.phase()
	local left = math.ceil(Game.timeLeft())
	timerLabel.Text = if phase == "Waiting" then "--:--" else string.format("%d:%02d", left // 60, left % 60)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local health = if humanoid and Game.alive() then math.max(0, math.ceil(humanoid.Health)) else 0
	healthLabel.Text = tostring(health)
	healthLabel.TextColor3 = if health <= 25 then RED else Ui.white
	shopHint.Visible = Game.canBuy()
	controlsLabel.Visible = phase == "Freeze" and Game.alive()

	if flashDuration > 0 then
		-- Сначала полная белизна, затем плавное прояснение
		local progress = (now - flashStart) / flashDuration
		flashOverlay.BackgroundTransparency = math.clamp((progress - 0.35) / 0.65, 0, 1)
		if progress >= 1 then
			flashDuration = 0
		end
	end
	hurtOverlay.BackgroundTransparency = if now < hurtUntil then 0.7 + 0.3 * (1 - (hurtUntil - now) / 0.4) else 1
	smokeOverlay.BackgroundTransparency = 1 - 0.97 * smokeDensity(camera.CFrame.Position)
	hitmarker.Visible = now < hitUntil
	if banner.Visible and now >= bannerUntil then
		banner.Visible = false
	end
	if noticeLabel.Visible and now >= noticeUntil then
		noticeLabel.Visible = false
	end
end

function Hud.init(gui: ScreenGui)
	smokeOverlay = overlay(gui, Color3.fromRGB(196, 196, 202), 1)
	hurtOverlay = overlay(gui, Color3.fromRGB(200, 20, 20), 2)

	-- Счёт и таймер
	local top = panel({ Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(380, 56), ZIndex = 5, Parent = gui })
	timerLabel = Ui.label({ Name = "Timer", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(140, 32), TextSize = 28, ZIndex = 6, Parent = top })
	phaseLabel = Ui.label({ Name = "Phase", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(180, 18), TextSize = 13, TextTransparency = 0.2, ZIndex = 6, Parent = top })
	for team, side in { T = 0, CT = 1 } do
		local x = if side == 0 then 12 else -12
		scoreLabels[team] = Ui.label({
			Name = "Score" .. team,
			AnchorPoint = Vector2.new(side, 0),
			Position = UDim2.new(side, x, 0, 2),
			Size = UDim2.fromOffset(90, 34),
			TextSize = 30,
			TextColor3 = Ui.teamColors[team],
			TextXAlignment = if side == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			ZIndex = 6,
			Parent = top,
		})
		aliveLabels[team] = Ui.label({
			Name = "Alive" .. team,
			AnchorPoint = Vector2.new(side, 1),
			Position = UDim2.new(side, x, 1, -3),
			Size = UDim2.fromOffset(110, 18),
			TextSize = 13,
			TextColor3 = Ui.teamColors[team],
			TextXAlignment = if side == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			ZIndex = 6,
			Parent = top,
		})
	end

	-- Здоровье и броня
	local vitals = panel({ Name = "Vitals", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -20), Size = UDim2.fromOffset(250, 62), ZIndex = 5, Parent = gui })
	Ui.label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(110, 14), Text = "ЗДОРОВЬЕ", TextSize = 12, TextTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = vitals })
	healthLabel = Ui.label({ Name = "Health", Position = UDim2.fromOffset(12, 20), Size = UDim2.fromOffset(110, 36), Text = "0", TextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = vitals })
	Ui.label({ Position = UDim2.fromOffset(130, 6), Size = UDim2.fromOffset(110, 14), Text = "БРОНЯ", TextSize = 12, TextTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = vitals })
	armorLabel = Ui.label({ Name = "Armor", Position = UDim2.fromOffset(130, 20), Size = UDim2.fromOffset(110, 36), Text = "0", TextSize = 34, TextColor3 = Ui.teamColors.CT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = vitals })

	-- Патроны и список оружия
	local ammo = panel({ Name = "Ammo", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(250, 62), ZIndex = 5, Parent = gui })
	weaponLabel = Ui.label({ Name = "Weapon", Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, -12, 0, 14), TextSize = 12, TextTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6, Parent = ammo })
	ammoLabel = Ui.label({ Name = "Count", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, -12, 0, 36), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6, Parent = ammo })
	weaponList = Ui.new("Frame", {
		Name = "Weapons",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -92),
		Size = UDim2.fromOffset(240, 150),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	local listLayout = Ui.list(Enum.FillDirection.Vertical, 2)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = weaponList

	-- Деньги
	local wallet = panel({ Name = "Wallet", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(150, 40), ZIndex = 5, Parent = gui })
	moneyLabel = Ui.label({ Name = "Money", Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = GREEN, ZIndex = 6, Parent = wallet })
	shopHint = Ui.label({ Name = "ShopHint", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 34), Size = UDim2.fromOffset(150, 20), Text = Text.ShopHint, TextSize = 14, TextStrokeTransparency = 0.5, Visible = false, ZIndex = 5, Parent = gui })
	bhopLabel = Ui.label({ Name = "Bhop", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -130), Size = UDim2.fromOffset(200, 20), TextSize = 15, TextColor3 = GREEN, TextStrokeTransparency = 0.5, Visible = false, ZIndex = 5, Parent = gui })

	-- Прицел: четыре чёрточки вокруг центра экрана
	crosshair = Ui.new("Frame", { Name = "Crosshair", Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 4, Parent = gui })
	for index = 1, 4 do
		crossLines[index] = Ui.frame({
			Size = if index <= 2 then UDim2.fromOffset(2, 9) else UDim2.fromOffset(9, 2),
			BackgroundColor3 = Color3.fromRGB(90, 255, 110),
			ZIndex = 4,
			Parent = crosshair,
		})
	end
	hitmarker = Ui.new("Frame", { Name = "Hitmarker", Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 4, Parent = gui })
	for _, rotation in { 45, -45 } do
		Ui.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 2), Rotation = rotation, BackgroundColor3 = Ui.white, ZIndex = 4, Parent = hitmarker })
	end

	-- Оптический прицел: чёрные поля по бокам и перекрестие
	scopeOverlay = Ui.new("Frame", { Name = "Scope", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 3, Parent = gui })
	local black = Color3.new(0, 0, 0)
	Ui.frame({ Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = black, ZIndex = 3, Parent = scopeOverlay }, {
		Ui.new("UISizeConstraint", {}),
	})
	local window = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = black, BackgroundTransparency = 1, ZIndex = 3, Parent = scopeOverlay }, {
		Ui.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
	})
	Ui.frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(2, 1), BackgroundColor3 = black, ZIndex = 3, Parent = window })
	Ui.frame({ Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(2, 1), BackgroundColor3 = black, ZIndex = 3, Parent = window })
	Ui.frame({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = black, ZIndex = 3, Parent = window })
	Ui.frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = black, ZIndex = 3, Parent = window })
	scopeOverlay:FindFirstChildOfClass("Frame"):Destroy()

	-- Лента убийств
	killfeed = Ui.new("Frame", { Name = "Killfeed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 76), Size = UDim2.fromOffset(360, 200), BackgroundTransparency = 1, ZIndex = 5, Parent = gui }, {
		Ui.list(Enum.FillDirection.Vertical, 4),
	})

	-- Итог раунда, сообщения и подсказки
	banner = panel({ Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.16, 0), Size = UDim2.fromOffset(460, 84), Visible = false, ZIndex = 7, Parent = gui })
	bannerTitle = Ui.label({ Name = "Title", Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 38), TextSize = 32, ZIndex = 8, Parent = banner })
	bannerSub = Ui.label({ Name = "Sub", Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextTransparency = 0.15, ZIndex = 8, Parent = banner })
	noticeLabel = Ui.label({ Name = "Notice", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -160), Size = UDim2.fromOffset(500, 24), TextSize = 18, TextStrokeTransparency = 0.4, Visible = false, ZIndex = 7, Parent = gui })
	statusLabel = Ui.label({ Name = "Status", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(600, 24), TextSize = 18, TextStrokeTransparency = 0.4, Visible = false, ZIndex = 7, Parent = gui })
	controlsLabel = Ui.label({ Name = "Controls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -560, 0, 34), Text = Text.Controls, TextSize = 13, TextWrapped = true, TextTransparency = 0.15, TextStrokeTransparency = 0.5, Visible = false, ZIndex = 5, Parent = gui })

	flashOverlay = overlay(gui, Color3.new(1, 1, 1), 9)

	-- Данные с сервера
	Game.watch(player, "Money", function()
		moneyLabel.Text = "$" .. Game.money()
	end)
	Game.watch(player, "Armor", function()
		armorLabel.Text = tostring(Game.armor())
	end)
	for _, name in { "Primary", "Secondary", "Grenades" } do
		player:GetAttributeChangedSignal(name):Connect(refreshWeapons)
	end
	for team, label in scoreLabels do
		Game.watch(Game.state, "Score" .. team, function()
			label.Text = tostring(Game.stateNumber("Score" .. team))
		end)
		Game.watch(Game.state, "Alive" .. team, function()
			aliveLabels[team].Text = "в живых: " .. Game.stateNumber("Alive" .. team)
		end)
	end
	local function refreshPhase()
		local phase = Game.phase()
		local name = (Text :: any)[phase] or phase
		local round = Game.stateNumber("Round")
		phaseLabel.Text = if round > 0 and phase ~= "Waiting" then `Раунд {round} · {name}` else name
	end
	Game.watch(Game.state, "Phase", refreshPhase)
	Game.watch(Game.state, "Round", refreshPhase)

	Net.on("Kill", function(killer: any, killerTeam: any, victim: any, victimTeam: any, weaponId: any, headshot: any)
		if typeof(killer) == "string" and typeof(victim) == "string" then
			addKill(killer, tostring(killerTeam), victim, tostring(victimTeam), tostring(weaponId), headshot == true)
		end
	end)
	Net.on("Hit", function(_damage: any, headshot: any, killed: any)
		hitUntil = os.clock() + 0.14
		local color = if killed == true or headshot == true then RED else Ui.white
		for _, line in hitmarker:GetChildren() do
			if line:IsA("Frame") then
				line.BackgroundColor3 = color
			end
		end
		Sounds.play("Hit", 0.5)
	end)
	Net.on("Hurt", function()
		hurtUntil = os.clock() + 0.4
	end)
	Net.on("Blind", function(duration: any)
		if typeof(duration) == "number" then
			flashStart, flashDuration = os.clock(), duration
			flashOverlay.BackgroundTransparency = 0
		end
	end)
	Net.on("Notice", function(text: any)
		if typeof(text) == "string" then
			Hud.notice(text, true)
		end
	end)
	Net.on("BuyResult", function(ok: any, text: any)
		Hud.notice(tostring(text), ok ~= true)
		Sounds.play(if ok == true then "Buy" else "Deny", 0.5)
	end)
	Net.on("RoundEnd", function(winner: any, reason: any)
		local title = if winner == "T" then Text.WinT elseif winner == "CT" then Text.WinCT else Text.Draw
		local sub = if reason == "Kill" then Text.ReasonKill else Text.ReasonTime
		Hud.showBanner(title, sub, Ui.teamColors[tostring(winner)] or Ui.white, Config.RoundEndTime)
		if winner == "T" or winner == "CT" then
			Sounds.play(if winner == Game.team() then "RoundWin" else "RoundLose", 0.5)
		end
	end)
	Net.on("MatchEnd", function(winner: any, nextMap: any)
		local name = if winner == "T" then Text.TeamT else Text.TeamCT
		Hud.showBanner(string.format(Text.MatchWin, name), string.format(Text.NextMap, tostring(nextMap)), Ui.teamColors[tostring(winner)] or Ui.white, Config.MatchEndTime)
	end)
end

return Hud
