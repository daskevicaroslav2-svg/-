--!strict
-- Модели огнестрельного оружия из деталей. Оси: -Z вперёд, +Y вверх, +X вправо,
-- начало координат в рукояти. Детали Slide и Bolt дёргаются назад при выстреле.

local Rig = require(script.Parent.Rig)

local P, paint, place = Rig.part, Rig.paint, Rig.place

local Models: { [string]: Rig.ModelSpec } = {}

Models.AK47 = {
	view = place({ 0.5, -0.52, -1.05 }, { 0, 3, 0 }),
	armR = place({ 0.04, -0.3, 0.1 }, { 55, 20, 0 }),
	armL = place({ -0.04, -0.08, -1.1 }, { 50, -38, 0 }),
	muzzle = Vector3.new(0, 0.16, -2.5),
	palette = {
		body = paint(48, 48, 52, "Metal"),
		metal = paint(30, 30, 32, "Metal"),
		wood = paint(120, 72, 40, "Wood"),
		mag = paint(60, 60, 64, "Metal"),
		grip = paint(40, 30, 24),
	},
	parts = {
		P("Receiver", "body", { 0.2, 0.3, 1.0 }, { 0, 0.12, -0.3 }),
		P("DustCover", "body", { 0.18, 0.08, 0.8 }, { 0, 0.3, -0.3 }),
		P("Handguard", "wood", { 0.22, 0.24, 0.72 }, { 0, 0.1, -1.15 }),
		P("GasTube", "metal", { 0.08, 0.08, 0.7 }, { 0, 0.26, -1.15 }, nil, "CylinderZ"),
		P("Barrel", "metal", { 0.07, 0.07, 1.0 }, { 0, 0.16, -1.95 }, nil, "CylinderZ"),
		P("Muzzle", "metal", { 0.1, 0.1, 0.14 }, { 0, 0.16, -2.43 }, nil, "CylinderZ"),
		P("FrontSight", "metal", { 0.05, 0.2, 0.06 }, { 0, 0.28, -2.2 }),
		P("RearSight", "metal", { 0.12, 0.07, 0.1 }, { 0, 0.37, -0.62 }),
		P("Bolt", "metal", { 0.06, 0.06, 0.16 }, { 0.13, 0.22, -0.35 }),
		P("Mag", "mag", { 0.15, 0.5, 0.26 }, { 0, -0.24, -0.62 }, { 12, 0, 0 }),
		P("MagTip", "mag", { 0.15, 0.3, 0.24 }, { 0, -0.56, -0.74 }, { 30, 0, 0 }, nil, "Mag"),
		P("Grip", "grip", { 0.15, 0.44, 0.2 }, { 0, -0.24, 0.08 }, { -16, 0, 0 }),
		P("TriggerGuard", "metal", { 0.05, 0.04, 0.3 }, { 0, -0.1, -0.2 }),
		P("Stock", "wood", { 0.17, 0.26, 0.85 }, { 0, 0.02, 0.62 }, { 6, 0, 0 }),
		P("StockButt", "wood", { 0.18, 0.4, 0.12 }, { 0, -0.06, 1.04 }),
	},
}

return Models
