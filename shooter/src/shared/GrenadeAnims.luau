--!strict
-- Анимации гранат, общие для всех видов: equip, throw, inspect и редкая secret.

local Anim = require(script.Parent.Anim)

local K = Anim.key

local Anims: { [string]: Anim.Animation } = {
	equip = {
		duration = 0.4,
		tracks = { gun = { K(0, { 0.1, -0.8, 0.2 }, { -30, 0, 0 }), K(0.4) } },
	},
	throw = {
		duration = 0.5,
		tracks = {
			gun = { K(0), K(0.18, { 0.2, 0.35, 0.6 }, { 35, 0, 0 }), K(0.32, { -0.2, 0.3, -0.9 }, { -30, 0, 0 }, "out"), K(0.5, { -0.2, -0.9, -0.6 }, { -60, 0, 0 }) },
		},
	},
	inspect = {
		duration = 2.4,
		tracks = {
			gun = { K(0), K(0.5, { -0.3, 0.15, 0.1 }, { 0, 60, 0 }), K(1.2, { -0.3, 0.15, 0.1 }, { 0, 180, 20 }), K(1.9, { -0.3, 0.15, 0.1 }, { 0, 300, 0 }), K(2.4, nil, { 0, 360, 0 }) },
		},
	},
	secret = {
		duration = 2,
		tracks = {
			gun = { K(0), K(0.3, { 0, 0.1, 0 }), K(0.7, { 0, 0.9, 0 }, { 180, 0, 0 }, "out"), K(1.1, { 0, 0.1, 0 }, { 360, 0, 0 }, "in"), K(2) },
		},
		detach = { armR = true },
	},
}

return Anims
