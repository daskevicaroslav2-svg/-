--!strict
-- Локальные эффекты: трассеры, вспышки выстрелов, следы от пуль, взрывы.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weapons = require(Shared.Weapons)
local Game = require(script.Parent.Game)
local Sounds = require(script.Parent.Sounds)

local Effects = {}

-- Папка локальных эффектов: лучи выстрелов её не замечают
local folder = Instance.new("Folder")
folder.Name = "LocalEffects"
folder.Parent = Workspace
Effects.folder = folder

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.CastShadow = false
	instance.Size = size
	instance.CFrame = cf
	instance.Color = color
	instance.Material = material
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Parent = folder
	return instance
end

function Effects.tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 6 then
		return
	end
	local tracer = part(Vector3.new(0.05, 0.05, length), CFrame.lookAt((from + to) / 2, to), Color3.fromRGB(255, 228, 150), Enum.Material.Neon)
	tracer.Transparency = 0.35
	Debris:AddItem(tracer, 0.06)
end

function Effects.muzzleFlash(position: Vector3)
	local flash = part(Vector3.new(0.4, 0.4, 0.4), CFrame.new(position), Color3.fromRGB(255, 220, 130), Enum.Material.Neon)
	flash.Shape = Enum.PartType.Ball
	flash.Transparency = 0.2
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 14
	light.Brightness = 3
	light.Parent = flash
	Debris:AddItem(flash, 0.05)
end

-- След от пули на стене
function Effects.impact(position: Vector3, normal: Vector3)
	local hole = part(Vector3.new(0.22, 0.22, 0.04), CFrame.lookAt(position + normal * 0.02, position + normal), Color3.fromRGB(30, 28, 26), Enum.Material.SmoothPlastic)
	Debris:AddItem(hole, 8)
end

local function boom(position: Vector3)
	local ball = part(Vector3.new(6, 6, 6), CFrame.new(position), Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.3
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 90)
	light.Range = 40
	light.Brightness = 6
	light.Parent = ball
	Debris:AddItem(ball, 0.12)
	Sounds.play("Explosion", 1, position)
end

local function weaponPosition(model: Model): Vector3?
	local arm = model:FindFirstChild("Right Arm")
	if arm and arm:IsA("BasePart") then
		return (arm.CFrame * CFrame.new(0, -1.6, 0)).Position
	end
	local root = model.PrimaryPart
	return if root then root.CFrame.Position else nil
end

-- Выстрелы и удары других бойцов; свои эффекты клиент рисует сразу сам
Net.on("Shot", function(model: any, weaponId: any, endPosition: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or model == Game.player.Character then
		return
	end
	local from = weaponPosition(model)
	if from and typeof(endPosition) == "Vector3" and typeof(weaponId) == "string" then
		local weapon = Weapons.get(weaponId)
		Effects.tracer(from, endPosition)
		Effects.muzzleFlash(from)
		Sounds.play(if weapon and weapon.heavy then "FireHeavy" else "Fire", 0.8, from)
	end
end)

Net.on("Swing", function(model: any, heavy: any)
	if typeof(model) == "Instance" and model:IsA("Model") and model ~= Game.player.Character then
		local from = weaponPosition(model)
		if from then
			Sounds.play(if heavy == true then "Stab" else "Slash", 0.6, from)
		end
	end
end)

Net.on("Boom", function(position: any)
	if typeof(position) == "Vector3" then
		boom(position)
	end
end)

Net.on("FlashBang", function(position: any)
	if typeof(position) == "Vector3" then
		local flash = part(Vector3.new(3, 3, 3), CFrame.new(position), Color3.new(1, 1, 1), Enum.Material.Neon)
		flash.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Range = 60
		light.Brightness = 10
		light.Parent = flash
		Debris:AddItem(flash, 0.1)
		Sounds.play("Flash", 1, position)
	end
end)

Net.on("Burn", function(position: any)
	if typeof(position) == "Vector3" then
		Sounds.play("Explosion", 0.5, position)
	end
end)

return Effects
