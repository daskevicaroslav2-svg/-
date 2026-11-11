--!strict
-- Мир: активная карта, точки появления, метки и проверки видимости лучами.

local Workspace = game:GetService("Workspace")

local World = {}

local mapsFolder = Workspace:WaitForChild("Maps")

local function folder(name: string): Folder
	local instance = Instance.new("Folder")
	instance.Name = name
	instance.Parent = Workspace
	return instance
end

World.effects = folder("Effects") -- гранаты в полёте, огонь: лучи их не замечают
World.smokes = folder("Smokes") -- дым: пули пролетают, но боты сквозь него не видят
World.bots = folder("Bots")

local active: Model? = nil
local solid = RaycastParams.new() -- только стены и пол активной карты
solid.FilterType = Enum.RaycastFilterType.Include
local sight = RaycastParams.new() -- стены и дым
sight.FilterType = Enum.RaycastFilterType.Include

function World.has(name: string): boolean
	return mapsFolder:FindFirstChild(name) ~= nil
end

function World.setMap(name: string)
	local map = mapsFolder:FindFirstChild(name)
	assert(map and map:IsA("Model"), `нет карты {name}`)
	active = map
	local geometry = map:FindFirstChild("Geometry")
	solid.FilterDescendantsInstances = { geometry :: Instance }
	sight.FilterDescendantsInstances = { geometry :: Instance, World.smokes }
end

function World.spawns(team: string): { CFrame }
	local result = {}
	local spawns = active and active:FindFirstChild("Spawns")
	local teamFolder = spawns and spawns:FindFirstChild(team)
	if teamFolder then
		for _, child in teamFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(result, child.CFrame)
			end
		end
	end
	return result
end

function World.marks(): { [string]: Vector3 }
	local result = {}
	local marks = active and active:FindFirstChild("Marks")
	if marks then
		for _, child in marks:GetChildren() do
			if child:IsA("BasePart") then
				result[child.Name] = child.CFrame.Position
			end
		end
	end
	return result
end

-- Есть ли стена между двумя точками
function World.blocked(from: Vector3, to: Vector3): boolean
	local offset = to - from
	local result = Workspace:Raycast(from, offset, solid)
	return result ~= nil and result.Distance < offset.Magnitude - 1
end

-- Закрыта ли точка стеной или дымом (зрение ботов)
function World.hidden(from: Vector3, to: Vector3): boolean
	local offset = to - from
	local result = Workspace:Raycast(from, offset, sight)
	return result ~= nil and result.Distance < offset.Magnitude - 1
end

-- Точка на земле под position
function World.ground(position: Vector3, depth: number): Vector3?
	local result = Workspace:Raycast(position, Vector3.new(0, -depth, 0), solid)
	return if result then result.Position else nil
end

function World.clear()
	World.effects:ClearAllChildren()
	World.smokes:ClearAllChildren()
end

return World
