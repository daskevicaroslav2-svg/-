--!strict
-- Модели ножей. Оси: -Z остриё, +Y обух, начало координат в середине рукояти.
-- Ячейки палитры у всех ножей одинаковые (blade, edge, guard, handle, accent),
-- поэтому любой скин из KnifeSkins подходит к любому ножу.

local Rig = require(script.Parent.Rig)

local P, paint, place = Rig.part, Rig.paint, Rig.place

local Models: { [string]: Rig.ModelSpec } = {}

Models.Classic = {
	view = place({ 0.5, -0.42, -0.95 }, { 8, 28, -8 }),
	armR = place({ 0, -0.02, 0.12 }, { 22, 10, 0 }),
	palette = {
		blade = paint(190, 195, 205, "Metal", 0, 0.25),
		edge = paint(230, 230, 235, "Metal", 0, 0.3),
		guard = paint(45, 45, 50, "Metal"),
		handle = paint(35, 35, 38),
		accent = paint(70, 70, 75, "Metal"),
	},
	parts = {
		P("Handle", "handle", { 0.14, 0.2, 0.55 }, { 0, 0, 0.12 }),
		P("Pommel", "accent", { 0.15, 0.22, 0.06 }, { 0, 0, 0.42 }),
		P("Guard", "guard", { 0.2, 0.34, 0.06 }, { 0, 0, -0.18 }),
		P("Blade1", "blade", { 0.04, 0.22, 0.3 }, { 0, 0.01, -0.36 }),
		P("Blade2", "blade", { 0.04, 0.21, 0.3 }, { 0, 0.015, -0.66 }),
		P("Blade3", "blade", { 0.04, 0.18, 0.25 }, { 0, 0.03, -0.93 }),
		P("Tip", "blade", { 0.04, 0.18, 0.3 }, { 0, 0.03, -1.2 }, nil, "Wedge"),
		P("Edge", "edge", { 0.02, 0.03, 0.85 }, { 0, -0.1, -0.63 }),
	},
}

return Models
