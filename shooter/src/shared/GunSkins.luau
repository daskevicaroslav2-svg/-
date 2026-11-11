--!strict
-- Скины огнестрельного оружия. Первый скин в списке — стандартный вид модели.

local Rig = require(script.Parent.Rig)

local paint = Rig.paint
local rgb = Color3.fromRGB

local Skins: { [string]: { Rig.Skin } } = {}

Skins.AK47 = {
	{ id = "Default", name = "Стандарт", rarity = 1 },
	{
		id = "Redline",
		name = "Красная линия",
		rarity = 4,
		slots = {
			body = paint(28, 28, 30, "Metal"),
			wood = paint(24, 24, 26),
			mag = paint(170, 30, 30, "Metal"),
			grip = paint(170, 30, 30),
		},
	},
	{
		id = "Fade",
		name = "Градиент",
		rarity = 6,
		gradient = { slots = { "body", "wood", "mag" }, colors = { rgb(255, 210, 60), rgb(255, 90, 160), rgb(120, 70, 220) }, material = "Metal", reflectance = 0.2 },
	},
}

return Skins
