--!strict
-- Анимации ножей: equip, slash (быстрый удар), stab (сильный удар), inspect и редкая secret.

local Anim = require(script.Parent.Anim)

local K = Anim.key

local Anims: { [string]: { [string]: Anim.Animation } } = {}

Anims.Classic = {
	equip = {
		duration = 0.45,
		tracks = { gun = { K(0, { 0.2, -0.8, 0.2 }, { -40, 30, 0 }), K(0.45) } },
	},
	slash = {
		duration = 0.4,
		tracks = {
			gun = { K(0), K(0.08, { 0.3, 0.15, 0.1 }, { 10, -30, -40 }), K(0.2, { -0.7, -0.1, -0.3 }, { -5, 50, 60 }, "out"), K(0.4) },
		},
	},
	stab = {
		duration = 0.9,
		tracks = {
			gun = { K(0), K(0.2, { 0.1, 0.1, 0.45 }, { 5, -10, 0 }), K(0.35, { -0.3, 0.05, -0.9 }, { 0, 15, 0 }, "out"), K(0.55, { -0.3, 0.05, -0.9 }, { 0, 15, 0 }), K(0.9) },
		},
	},
	inspect = {
		duration = 3.6,
		tracks = {
			gun = {
				K(0),
				K(0.5, { -0.3, 0.15, 0.1 }, { 0, 40, 70 }),
				K(1.6, { -0.3, 0.15, 0.1 }, { 0, 50, 80 }),
				K(2.1, { -0.3, 0.15, 0.1 }, { 0, 40, -100 }),
				K(3.1, { -0.3, 0.15, 0.1 }, { 0, 50, -90 }),
				K(3.6),
			},
		},
	},
	secret = {
		duration = 2.6,
		tracks = {
			gun = {
				K(0),
				K(0.3, { -0.2, 0.1, 0 }, { 30, 0, 0 }),
				K(0.6, { -0.2, 0.7, 0 }, { 150, 0, 0 }, "linear"),
				K(0.9, { -0.2, 0.95, 0 }, { 270, 0, 0 }, "linear"),
				K(1.2, { -0.2, 0.7, 0 }, { 390, 0, 0 }, "linear"),
				K(1.5, { -0.2, 0.2, 0 }, { 510, 0, 0 }, "linear"),
				K(1.8, { -0.2, 0.05, 0 }, { 720, 0, 0 }),
				K(2.6),
			},
		},
		detach = { armR = true },
	},
}

return Anims
