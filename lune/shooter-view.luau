-- Предпросмотр моделей оружия и анимаций без Studio.
--   lune run shooter-view <модель> [скин] [анимация] [кадров]
-- Без анимации рисует вид от первого лица и модель с пяти сторон,
-- с анимацией — раскадровку вида от первого лица. Результат: out/view-*.png

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Scene = require("./lib/scene")
local shooter = require("./lib/shooter")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local modelId = process.args[1]
local skinId = process.args[2] or "Default"
local animName = process.args[3]
local frameCount = tonumber(process.args[4]) or 12
if not modelId then
	print("Использование: lune run shooter-view <модель> [скин] [анимация] [кадров]")
	process.exit(1)
end

local game = roblox.Instance.new("DataModel")
shooter.mount(game)
local loader = shooter.loader(game)
local Shared = game:GetService("ReplicatedStorage").Shared
local Anim = loader.require(Shared.Anim)
local Arsenal = loader.require(Shared.Arsenal)
local Rig = loader.require(Shared.Rig)

local rig = Arsenal.rig(modelId, skinId, "T")
if not rig then
	print(`Нет модели {modelId}`)
	process.exit(1)
end
if skinId ~= "Default" and not Arsenal.skin(modelId, skinId) then
	print(`У модели {modelId} нет скина {skinId}`)
	process.exit(1)
end

local IDENTITY = CFrame.new()

local function prims(camera, cframes, onlyGun)
	local list = {}
	for index, part in rig.parts do
		if not onlyGun or part.group == "gun" then
			table.insert(list, Scene.prim(camera, part.shape, part.size, cframes[index], part.color, 1 - part.transparency))
		end
	end
	return list
end

local frames = {}
if animName then
	local animation = Arsenal.animation(modelId, animName)
	if not animation then
		print(`У модели {modelId} нет анимации {animName}`)
		process.exit(1)
	end
	for i = 0, frameCount - 1 do
		local t = animation.duration * i / (frameCount - 1)
		local cframes = Rig.pose(rig, IDENTITY, Anim.sample(animation, t), animation.detach)
		table.insert(frames, { label = string.format("%s t=%.2f", animName, t), prims = prims(IDENTITY, cframes) })
	end
else
	table.insert(frames, { label = "first person", prims = prims(IDENTITY, Rig.pose(rig, IDENTITY)) })
	-- Модель без рук в собственных осях: считаем габариты и обходим камерой
	local saved = rig.spec.view
	rig.spec.view = IDENTITY
	local cframes = Rig.pose(rig, IDENTITY)
	rig.spec.view = saved
	local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local count = 0
	for index, part in rig.parts do
		if part.group == "gun" then
			count += 1
			local p, r = cframes[index].Position, part.size.Magnitude / 2
			low = Vector3.new(math.min(low.X, p.X - r), math.min(low.Y, p.Y - r), math.min(low.Z, p.Z - r))
			high = Vector3.new(math.max(high.X, p.X + r), math.max(high.Y, p.Y + r), math.max(high.Z, p.Z + r))
		end
	end
	local center = (low + high) / 2
	local size = high - low
	local distance = math.max(size.X, size.Y, size.Z) * 0.95
	print(`{modelId}: деталей {count}, габариты {string.format("%.2f x %.2f x %.2f", size.X, size.Y, size.Z)}`)
	for _, view in {
		{ "left side", Vector3.new(-1, 0.05, 0) },
		{ "right side", Vector3.new(1, 0.05, 0) },
		{ "top", Vector3.new(0.01, 1, 0.02) },
		{ "front 3/4", Vector3.new(0.6, 0.35, -0.7) },
		{ "back 3/4", Vector3.new(-0.6, 0.35, 0.7) },
	} do
		local camera = CFrame.lookAt(center + view[2].Unit * distance, center)
		table.insert(frames, { label = view[1], prims = prims(camera, cframes, true) })
	end
end

local out = `out/view-{modelId}-{skinId}{if animName then "-" .. animName else ""}.png`
Scene.render({ width = 480, height = 270, cols = if animName then 4 else 3, background = { 96, 110, 126 }, frames = frames }, out)
