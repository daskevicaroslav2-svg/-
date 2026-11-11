--!strict
-- Камера: вид от первого лица в бою, обзор карты в меню, слежение за союзником после гибели,
-- а также отдача и приближение прицела.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Game = require(script.Parent.Game)

local View = {}

local player = Game.player

local recoilUp, recoilSide = 0, 0
local zoomFov: number? = nil
local defaultFov = 70
local mode = ""
local spectated: Model? = nil

-- Подброс камеры от выстрела в градусах; сам возвращается к точке прицеливания
function View.kick(degrees: number)
	recoilUp = math.min(recoilUp + degrees, 9)
	recoilSide = math.clamp(recoilSide + (math.random() - 0.5) * degrees * 0.8, -3, 3)
end

-- Поле зрения прицела; nil — обычный вид
function View.setZoom(fov: number?)
	zoomFov = fov
	UserInputService.MouseDeltaSensitivity = if fov then math.clamp(fov / defaultFov, 0.2, 1) else 1
end

function View.reset()
	recoilUp, recoilSide = 0, 0
	View.setZoom(nil)
end

local function humanoidOf(model: Model?): Humanoid?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

-- Живые союзники: игроки и боты своей команды
local function teammates(): { Model }
	local result = {}
	local team = Game.team()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other ~= player and other:GetAttribute("Team") == team and character and humanoidOf(character) then
			table.insert(result, character)
		end
	end
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") and bot:GetAttribute("Team") == team and humanoidOf(bot) then
				table.insert(result, bot)
			end
		end
	end
	return result
end

-- Следующий союзник для наблюдения (по клику)
function View.nextSpectate()
	local list = teammates()
	if #list == 0 then
		spectated = nil
		return
	end
	local index = if spectated then table.find(list, spectated) or 0 else 0
	spectated = list[index % #list + 1]
end

function View.spectatedName(): string?
	return if mode == "spectate" and spectated then spectated.Name else nil
end

local function setMode(newMode: string)
	if mode == newMode then
		return
	end
	mode = newMode
	if newMode == "play" then
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 14
		player.CameraMinZoomDistance = 14
		View.reset()
	end
end

-- Вызывается каждый кадр после стандартной камеры Roblox
function View.update(dt: number, camera: Camera)
	local character = player.Character
	local humanoid = if Game.alive() then humanoidOf(character) else nil

	if humanoid then
		setMode("play")
		camera.CameraType = Enum.CameraType.Custom
		if camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	else
		if not humanoidOf(spectated) then
			spectated = nil
			if Game.team() ~= "" then
				View.nextSpectate()
			end
		end
		local target = humanoidOf(spectated)
		if target then
			setMode("spectate")
			camera.CameraType = Enum.CameraType.Custom
			if camera.CameraSubject ~= target then
				camera.CameraSubject = target
			end
		else
			-- Смотреть не на кого: показываем общий вид карты
			setMode("menu")
			local map = Game.map()
			local overview = map and map:FindFirstChild("Overview")
			camera.CameraType = Enum.CameraType.Scriptable
			if overview and overview:IsA("BasePart") then
				camera.CFrame = overview.CFrame
			end
		end
	end

	local target = if mode == "play" and zoomFov then zoomFov else defaultFov
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 18)

	if mode == "play" then
		camera.CFrame *= CFrame.Angles(math.rad(recoilUp), math.rad(recoilSide), 0)
		recoilUp = math.max(0, recoilUp - dt * (6 + recoilUp * 5))
		recoilSide *= math.exp(-dt * 7)
	end
end

return View
