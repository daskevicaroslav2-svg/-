--!strict
-- Скины ножей: подходят ко всем моделям из KnifeModels. Первый — стандартный.

local Rig = require(script.Parent.Rig)

local rgb = Color3.fromRGB

local Skins: { Rig.Skin } = {
	{ id = "Default", name = "Стандарт", rarity = 1 },
	{
		id = "Fade",
		name = "Градиент",
		rarity = 7,
		gradient = { slots = { "blade", "edge" }, colors = { rgb(255, 220, 70), rgb(255, 80, 170), rgb(110, 70, 230) }, material = "Metal", reflectance = 0.3 },
	},
}

return Skins
