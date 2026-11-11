--!strict
-- Вид от первого лица: руки и оружие из деталей перед камерой, анимации, покачивание и отдача.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anim = require(Shared.Anim)
local Arsenal = require(Shared.Arsenal)
local Build = require(Shared.Build)
local Rig = require(Shared.Rig)

local Viewmodel = {}

local IDENTITY = CFrame.new()

local folder = Instance.new("Folder")
folder.Name = "Viewmodel"

local rig: Rig.Rig? = nil
local parts: { BasePart } = {}
local modelId: string? = nil
local kickPart: string? = nil -- затвор, который дёргается при выстреле
local hidden = false

local animation: Anim.Animation? = nil
local animationName: string? = nil
local animationStart = 0

-- Плавные добавки к положению оружия
local swayX, swayY = 0, 0
local bobPhase = 0
local bobAmount = 0
local airOffset = 0
local kickBack, kickUp, slideBack = 0, 0, 0

local function clear()
	for _, instance in parts do
		instance:Destroy()
	end
	table.clear(parts)
	rig = nil
	modelId = nil
	animation = nil
	animationName = nil
end

local function applyHidden()
	for _, instance in parts do
		instance.LocalTransparencyModifier = if hidden then 1 else 0
	end
end

-- Показывает модель оружия со скином; nil убирает оружие из рук
function Viewmodel.show(newModelId: string?, skinId: string?, team: string)
	clear()
	hidden = false
	local newRig = if newModelId then Arsenal.rig(newModelId, skinId, team) else nil
	if not newRig then
		return
	end
	rig = newRig
	modelId = newModelId
	kickPart = nil
	for _, desc in newRig.parts do
		local instance = Build.part(desc)
		instance.Anchored = true
		instance.Parent = folder
		table.insert(parts, instance)
		if desc.name == "Slide" or (desc.name == "Bolt" and not kickPart) then
			kickPart = desc.name
		end
	end
end

-- Запускает анимацию текущей модели; возвращает её длительность (0, если такой нет)
function Viewmodel.play(name: string): number
	local track = if modelId then Arsenal.animation(modelId, name) else nil
	if not track then
		animation = nil
		animationName = nil
		return 0
	end
	animation = track
	animationName = name
	animationStart = os.clock()
	return track.duration
end

function Viewmodel.stop()
	animation = nil
	animationName = nil
end

function Viewmodel.playing(): string?
	return animationName
end

function Viewmodel.setHidden(value: boolean)
	if hidden ~= value then
		hidden = value
		applyHidden()
	end
end

-- Отдача: оружие толкает назад и подбрасывает, затвор отъезжает
function Viewmodel.kick(strength: number)
	kickBack = math.min(kickBack + 0.05 + strength * 0.02, 0.3)
	kickUp = math.min(kickUp + strength * 0.012, 0.12)
	slideBack = 0.14
end

local lastBase = IDENTITY

-- Точка дульного среза в мире (для вспышки и трассера)
function Viewmodel.muzzle(): Vector3?
	local current = rig
	if not current or hidden or not current.spec.muzzle then
		return nil
	end
	return Rig.gunCFrame(current, lastBase) * current.spec.muzzle
end

-- Вызывается каждый кадр после камеры. speed — скорость игрока по земле, grounded — стоит ли он.
function Viewmodel.update(dt: number, camera: Camera, speed: number, grounded: boolean, verticalSpeed: number)
	if folder.Parent ~= camera then
		folder.Parent = camera
	end
	local current = rig
	if not current then
		return
	end
	local blend = math.min(1, dt * 12)

	-- Оружие запаздывает за поворотом камеры
	local delta = UserInputService:GetMouseDelta()
	swayX += (math.clamp(-delta.X * 0.0016, -0.06, 0.06) - swayX) * blend
	swayY += (math.clamp(-delta.Y * 0.0016, -0.06, 0.06) - swayY) * blend

	-- Покачивание при ходьбе и смещение в прыжке
	local walking = grounded and speed > 1
	bobAmount += ((if walking then math.min(speed / 18, 1.3) else 0) - bobAmount) * blend
	if walking then
		bobPhase += dt * speed * 0.62
	end
	airOffset += (math.clamp(-verticalSpeed * 0.004, -0.09, 0.09) - airOffset) * blend
	local bobX = math.sin(bobPhase) * 0.035 * bobAmount
	local bobY = -math.abs(math.cos(bobPhase)) * 0.03 * bobAmount

	local decay = math.exp(-dt * 13)
	kickBack *= decay
	kickUp *= decay
	slideBack *= math.exp(-dt * 26)

	local base = camera.CFrame
		* CFrame.new(bobX, bobY + airOffset, kickBack)
		* CFrame.Angles(kickUp + swayY, swayX, swayX * 0.6)
	lastBase = base

	local pose: { [string]: CFrame }? = nil
	local detach: { [string]: boolean }? = nil
	local track = animation
	if track then
		local t = os.clock() - animationStart
		if t >= track.duration then
			animation = nil
			animationName = nil
		else
			pose = Anim.sample(track, t)
			detach = track.detach
		end
	end
	if kickPart and slideBack > 0.002 then
		local offsets: { [string]: CFrame } = pose or {}
		offsets[kickPart] = (offsets[kickPart] or IDENTITY) * CFrame.new(0, 0, slideBack)
		pose = offsets
	end

	Workspace:BulkMoveTo(parts, Rig.pose(current, base, pose, detach), Enum.BulkMoveMode.FireCFrameChanged)
end

return Viewmodel
