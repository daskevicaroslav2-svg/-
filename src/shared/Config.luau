--!strict
-- Общие настройки игры. Цены и параметры предметов задаются атрибутами
-- кнопок и моделей в Workspace.Tycoons (окно Properties в Studio).

return {
	StartingCash = 0,
	ConveyorSpeed = 12, -- studs в секунду
	OreLifetime = 30, -- через сколько секунд удалять застрявшую руду
	RebirthBonus = 0.5, -- прибавка к множителю дохода за одно перерождение
	PurchaseCooldown = 0.4, -- пауза между покупками, чтобы не купить лишнее на бегу
	DataStoreName = "TycoonSave_v1",
	AutosaveInterval = 120,

	-- Названия колонок в списке игроков
	CashStat = "Деньги",
	RebirthStat = "Перерождения",

	Text = {
		Unclaimed = "Свободный завод",
		ClaimPad = "Занять завод",
		Owner = "Завод игрока\n%s",
		Collect = "Собрать\n%s",
		Free = "БЕСПЛАТНО",
		RebirthButton = "%s\n+%.0f%% к доходу",
		Claimed = "Завод твой! Купи первый дроппер.",
		AlreadyOwner = "У тебя уже есть завод.",
		NotEnough = "Не хватает %s",
		Bought = "Куплено: %s",
		Rebirth = "Перерождение! Доход теперь x%s",
		Hint = "Найди свободный завод и встань на зелёную площадку",
		Multiplier = "Доход x%s",
	},
}
