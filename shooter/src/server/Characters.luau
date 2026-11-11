--!strict
-- Персонажи: появление игроков и ботов, форма команды, оружие в руках от третьего лица.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arsenal = require(Shared.Arsenal)
local Build = require(Shared.Build)
local Weapons = require(Shared.Weapons)
local Fighters = require(script.Parent.Fighters)
local World = require(script.Parent.World)

type Fighter = Fighters.Fighter

local Characters = {}

-- Вызывается при смерти персонажа бойца; назначает Combat
Characters.onDied = nil :: ((Fighter) -> ())?

local botRig = ServerStorage:WaitForChild("BotRig") :: Model

-- Оружие крепится к правой руке так же, как стандартный Tool: ствол вдоль руки
local GRIP = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

local UNIFORMS = {
	T = { body = Color3.fromRGB(150, 122, 84), legs = Color3.fromRGB(74, 62, 50), head = Color3.fromRGB(206, 164, 122) },
	CT = { body = Color3.fromRGB(44, 58, 88), legs = Color3.fromRGB(38, 42, 52), head = Color3.fromRGB(54, 60, 72) },
}
local BODY_PARTS: { [string]: string } = {
	Torso = "body",
	["Left Arm"] = "body",
	["Right Arm"] = "body",
	["Left Leg"] = "legs",
	["Right Leg"] = "legs",
	Head = "head",
}

-- Стандартные анимации R6 от Roblox: рука с оружием и бег
local HOLD_ANIMATION = "rbxassetid://182393478"
local RUN_ANIMATION = "rbxassetid://180426354"

local function loadTrack(humanoid: Humanoid, id: string): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	return if ok then track else nil
end

local function setup(fighter: Fighter, model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return false
	end
	Fighters.bind(fighter, model)
	fighter.humanoid = humanoid
	fighter.root = root
	fighter.alive = true
	fighter.lastHit = nil
	fighter.blindUntil = 0

	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:SetAttribute("Team", fighter.team)

	local uniform = UNIFORMS[fighter.team] or UNIFORMS.T
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Fighters"
			local role = BODY_PARTS[part.Name]
			if role then
				part.Color = (uniform :: any)[role]
			end
		end
	end

	local hold = loadTrack(humanoid, HOLD_ANIMATION)
	if hold then
		hold.Priority = Enum.AnimationPriority.Action
		hold.Looped = true
		hold:Play()
	end

	humanoid.Died:Connect(function()
		if fighter.model == model and Characters.onDied then
			Characters.onDied(fighter)
		end
	end)
	return true
end

-- Загружает персонажа игрока и ставит его в точку появления
function Characters.spawnPlayer(fighter: Fighter, cf: CFrame): boolean
	local player = fighter.player
	if not player then
		return false
	end
	local ok = pcall(function()
		player:LoadCharacter()
	end)
	local character = player.Character
	if not ok or not character then
		return false
	end
	character:PivotTo(cf)
	return setup(fighter, character)
end

function Characters.spawnBot(fighter: Fighter, cf: CFrame): boolean
	local model = botRig:Clone()
	model.Name = fighter.name
	model:PivotTo(cf)
	model.Parent = World.bots
	if not setup(fighter, model) then
		model:Destroy()
		return false
	end
	local humanoid = fighter.humanoid :: Humanoid
	-- Движение бота считает сервер
	pcall(function()
		(fighter.root :: BasePart):SetNetworkOwner(nil)
	end)
	local run = loadTrack(humanoid, RUN_ANIMATION)
	if run then
		run.Looped = true
		humanoid.Running:Connect(function(speed)
			if speed > 1 then
				if not run.IsPlaying then
					run:Play()
				end
			elseif run.IsPlaying then
				run:Stop()
			end
		end)
	end
	return true
end

-- Пересобирает модель оружия в руке (её видят другие игроки)
function Characters.holdWeapon(fighter: Fighter)
	local model = fighter.model
	if not model then
		return
	end
	local old = model:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	local arm = model:FindFirstChild("Right Arm")
	local modelId = Weapons.modelId(fighter.equipped, fighter.prefs.knife)
	local skinKey = if fighter.equipped == "Knife" then "Knife" else fighter.equipped
	local rig = Arsenal.rig(modelId, fighter.prefs.skins[skinKey], fighter.team)
	if not rig or not arm or not arm:IsA("BasePart") then
		return
	end

	local holder = Instance.new("Model")
	holder.Name = "Weapon"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = arm.CFrame * GRIP
	handle.Parent = holder
	for _, desc in rig.parts do
		if desc.group == "gun" then
			local part = Build.part(desc)
			part.CFrame = handle.CFrame * desc.rest * (desc.fix or CFrame.new())
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
			part.Parent = holder
		end
	end
	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part0 = arm
	grip.Part1 = handle
	grip.C0 = GRIP
	grip.Parent = handle
	holder.Parent = model
end

function Characters.remove(fighter: Fighter)
	local model = fighter.model
	Fighters.bind(fighter, nil)
	fighter.humanoid = nil
	fighter.root = nil
	fighter.alive = false
	if model then
		model:Destroy()
	end
end

return Characters
