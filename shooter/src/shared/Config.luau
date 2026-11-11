--!strict
-- Настройки шутера: правила раундов, экономика, движение, боты, звуки и тексты.

return {
	Maps = { "Dust2", "Mirage" }, -- порядок смены карт между матчами

	-- Раунды
	RoundsToWin = 8,
	FreezeTime = 6, -- секунд на закупку до начала боя
	RoundTime = 115,
	BuyTime = 20, -- сколько секунд после начала боя ещё работает магазин
	RoundEndTime = 6,
	MatchEndTime = 12,
	TeamSize = 4, -- команды дополняются ботами до этого размера (0 — без ботов)
	MaxTeamPlayers = 6,

	-- Экономика
	StartMoney = 800,
	MaxMoney = 16000,
	WinReward = 3250,
	LossReward = 1400,
	LossStreakBonus = 500,
	LossRewardMax = 3400,
	ArmorPrice = 1000,
	ArmorWear = 0.5, -- какая доля поглощённого урона снимается с брони
	MaxGrenades = 4,

	-- Движение
	WalkScale = 0.52, -- множитель скорости при зажатом Shift
	Bhop = {
		window = 0.2, -- прыжок не позже этого времени после приземления продолжает серию
		step = 0.07, -- прибавка к скорости за каждый прыжок серии
		maxHops = 6,
	},

	-- Осмотр оружия
	SecretChance = 0.12, -- шанс редкой анимации при обычном осмотре
	DoubleTap = 0.35, -- двойное нажатие F за это время всегда даёт редкую анимацию

	Bots = {
		reaction = { 0.4, 0.85 }, -- секунд от появления врага в поле зрения до первого выстрела
		aimError = 4.5, -- разброс прицеливания в градусах
		damageScale = 0.5,
		viewDistance = 260,
		names = { "Борис", "Гоша", "Витя", "Лёха", "Макс", "Саня", "Тимур", "Федя", "Юра", "Яша", "Дима", "Костя" },
	},

	DataStoreName = "ShooterLoadout_v1",

	-- Встроенные звуки клиента Roblox. Свои звуки: замени на rbxassetid://НОМЕР.
	Sounds = {
		Fire = "rbxasset://sounds/snap.mp3",
		FireHeavy = "rbxasset://sounds/collide.wav",
		Empty = "rbxasset://sounds/clickfast.wav",
		Reload = "rbxasset://sounds/switch.wav",
		Equip = "rbxasset://sounds/unsheath.wav",
		Slash = "rbxasset://sounds/swordslash.wav",
		Stab = "rbxasset://sounds/swordlunge.wav",
		Hit = "rbxasset://sounds/hit.wav",
		Explosion = "rbxasset://sounds/collide.wav",
		Flash = "rbxasset://sounds/flashbulb.wav",
		Buy = "rbxasset://sounds/electronicpingshort.wav",
		Deny = "rbxasset://sounds/button.wav",
		Click = "rbxasset://sounds/button.wav",
		RoundWin = "rbxasset://sounds/victory.wav",
		RoundLose = "rbxasset://sounds/uuhhh.mp3",
	},

	Text = {
		TeamT = "Террористы",
		TeamCT = "Спецназ",
		ChooseTeam = "ВЫБЕРИ СТОРОНУ",
		Auto = "Авто",
		Players = "Игроков: %d",
		Waiting = "Ожидание игроков",
		Freeze = "Закупка",
		Live = "Бой",
		RoundEnd = "Конец раунда",
		MatchEnd = "Матч окончен",
		WinT = "Победа террористов",
		WinCT = "Победа спецназа",
		Draw = "Ничья",
		ReasonKill = "Все противники уничтожены",
		ReasonTime = "Время вышло",
		MatchWin = "Матч выиграли: %s",
		NextMap = "Следующая карта: %s",
		Dead = "Ты погиб. Жди следующего раунда",
		Spectating = "Наблюдение: %s (ЛКМ — следующий)",
		NextRound = "Ты появишься в начале следующего раунда",
		Shop = "МАГАЗИН",
		ShopHint = "B — магазин",
		ShopClosed = "Время покупки вышло",
		NoMoney = "Недостаточно денег",
		WrongTeam = "Недоступно для твоей команды",
		Owned = "Уже есть",
		Full = "Больше не унести",
		Loadout = "НОЖИ И СКИНЫ",
		Knives = "Тип ножа",
		SkinsFor = "Скины для",
		KnifeSkin = "Нож",
		KnifeNames = { Classic = "Классический", Bayonet = "Штык-нож", Karambit = "Керамбит", Butterfly = "Бабочка", Kukri = "Кукри" },
		Armor = "Броня и шлем",
		Controls = "ЛКМ огонь · ПКМ прицел/удар · R перезарядка · F осмотр · 1-4 и колесо — оружие · B магазин · N скины · M команда · Shift шаг · Пробел прыжок",
		Categories = { pistol = "Пистолеты", smg = "Пистолеты-пулемёты", rifle = "Винтовки", sniper = "Снайперские", grenade = "Гранаты", gear = "Снаряжение" },
		Rarity = { "Ширпотреб", "Промышленное", "Армейское", "Запрещённое", "Засекреченное", "Тайное", "Редчайшее" },
	},

	-- Цвета редкости скинов (1..7)
	RarityColors = {
		Color3.fromRGB(176, 195, 217),
		Color3.fromRGB(94, 152, 217),
		Color3.fromRGB(75, 105, 255),
		Color3.fromRGB(136, 71, 255),
		Color3.fromRGB(211, 44, 230),
		Color3.fromRGB(235, 75, 75),
		Color3.fromRGB(255, 200, 40),
	},
}
