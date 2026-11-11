--!strict
-- Модели гранат в руке. Ячейки палитры: body, cap, lever, band.

local Rig = require(script.Parent.Rig)

local P, paint, place = Rig.part, Rig.paint, Rig.place

local Models: { [string]: Rig.ModelSpec } = {}

Models.HE = {
	view = place({ 0.5, -0.45, -1.0 }, { 0, 10, -10 }),
	armR = place({ 0.05, -0.12, 0.2 }, { 30, 12, 0 }),
	palette = {
		body = paint(70, 90, 60, "Metal"),
		cap = paint(50, 50, 54, "Metal"),
		lever = paint(110, 110, 115, "Metal"),
		band = paint(210, 180, 50),
	},
	parts = {
		P("Body", "body", { 0.42, 0.42, 0.42 }, { 0, 0.05, 0 }, nil, "Ball"),
		P("Band", "band", { 0.06, 0.44, 0.44 }, { 0, 0.05, 0 }, { 0, 0, 90 }, "CylinderX"),
		P("Cap", "cap", { 0.16, 0.14, 0.16 }, { 0, 0.3, 0 }),
		P("Lever", "lever", { 0.06, 0.3, 0.05 }, { 0, 0.2, 0.14 }, { -18, 0, 0 }),
	},
}

return Models
