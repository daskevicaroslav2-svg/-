--!strict
-- Превращает описание детали из Rig в настоящую деталь Roblox.

local Rig = require(script.Parent.Rig)

local Build = {}

local function material(name: string): Enum.Material
	local ok, value = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	return Enum.Material.SmoothPlastic
end

Build.material = material

-- Деталь оружия: невесомая, ни с чем не сталкивается и не ловит лучи
function Build.part(desc: Rig.RigPart): BasePart
	local part: BasePart
	if desc.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if desc.shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		elseif desc.shape == "Ball" then
			block.Shape = Enum.PartType.Ball
		end
		part = block
	end
	local size = desc.size
	if desc.shape == "Ball" then
		local diameter = math.min(size.X, size.Y, size.Z)
		size = Vector3.new(diameter, diameter, diameter)
	end
	part.Name = desc.name
	part.Size = size
	part.Color = desc.color
	part.Material = material(desc.material)
	part.Transparency = desc.transparency
	part.Reflectance = desc.reflectance
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	return part
end

return Build
