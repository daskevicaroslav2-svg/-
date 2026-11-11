-- Стандартный блочный персонаж R6: одинаковые хитбоксы у игроков и ботов.
-- Названия деталей и соединений совпадают с классическим R6, поэтому работают
-- стандартные анимации Roblox.

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

-- Классические повороты соединений R6
local function right(x, y, z)
	return CFrame.new(x, y, z, 0, 0, 1, 0, 1, 0, -1, 0, 0)
end
local function left(x, y, z)
	return CFrame.new(x, y, z, 0, 0, -1, 0, 1, 0, 1, 0, 0)
end
local function center(x, y, z)
	return CFrame.new(x, y, z, -1, 0, 0, 0, 0, 1, 0, 1, 0)
end

local JOINTS = {
	{ name = "RootJoint", part0 = "HumanoidRootPart", part1 = "Torso", c0 = center(0, 0, 0), c1 = center(0, 0, 0) },
	{ name = "Neck", part0 = "Torso", part1 = "Head", c0 = center(0, 1, 0), c1 = center(0, -0.6, 0) },
	{ name = "Right Shoulder", part0 = "Torso", part1 = "Right Arm", c0 = right(1, 0.5, 0), c1 = right(-0.5, 0.5, 0) },
	{ name = "Left Shoulder", part0 = "Torso", part1 = "Left Arm", c0 = left(-1, 0.5, 0), c1 = left(0.5, 0.5, 0) },
	{ name = "Right Hip", part0 = "Torso", part1 = "Right Leg", c0 = right(1, -1, 0), c1 = right(0.5, 1, 0) },
	{ name = "Left Hip", part0 = "Torso", part1 = "Left Leg", c0 = left(-1, -1, 0), c1 = left(-0.5, 1, 0) },
}

local SIZES = {
	HumanoidRootPart = Vector3.new(2, 2, 1),
	Torso = Vector3.new(2, 2, 1),
	Head = Vector3.new(1.2, 1.2, 1.2),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
}

-- Создаёт модель персонажа: ступни на высоте y = 0 относительно origin
local function build(name, origin)
	local model = Instance.new("Model")
	model.Name = name

	local parts = {}
	local function part(partName, cf)
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = SIZES[partName]
		p.CFrame = cf
		p.Color = Color3.fromRGB(160, 160, 165)
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		parts[partName] = p
		return p
	end

	local root = part("HumanoidRootPart", CFrame.new(origin + Vector3.new(0, 3, 0)))
	root.Transparency = 1
	root.CanCollide = false
	for _, joint in JOINTS do
		local part0 = parts[joint.part0]
		local part1 = part(joint.part1, part0.CFrame * joint.c0 * joint.c1:Inverse())
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = joint.c0
		motor.C1 = joint.c1
		motor.Parent = part0
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid

	model.PrimaryPart = root
	return model
end

return { build = build }
