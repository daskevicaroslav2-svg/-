--!strict
-- Движение: скорость зависит от оружия, Shift — тихий шаг, во время закупки игрок стоит.
-- Банихоп: прыжок сразу после приземления продолжает серию и добавляет скорость.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Game = require(script.Parent.Game)

local Movement = {}

local hops = 0
local landedAt = 0
local bound: Humanoid? = nil
local jumpEnabled = true

function Movement.hops(): number
	return hops
end

-- Подключается к новому персонажу
function Movement.bind(humanoid: Humanoid)
	bound = humanoid
	hops = 0
	jumpEnabled = true
	humanoid.StateChanged:Connect(function(_, state)
		if state == Enum.HumanoidStateType.Landed then
			landedAt = os.clock()
		elseif state == Enum.HumanoidStateType.Jumping then
			local chained = os.clock() - landedAt <= Config.Bhop.window and humanoid.MoveDirection.Magnitude > 0.1
			hops = if chained then math.min(hops + 1, Config.Bhop.maxHops) else 0
		end
	end)
end

-- Каждый кадр: weaponSpeed — скорость с оружием в руках, slowed — множитель (прицел)
function Movement.update(weaponSpeed: number, slowed: number)
	local humanoid = bound
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local frozen = Game.phase() == "Freeze"
	if jumpEnabled == frozen then
		jumpEnabled = not frozen
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpEnabled)
	end
	if frozen then
		humanoid.WalkSpeed = 0
		hops = 0
		return
	end
	-- Серия обрывается, если задержаться на земле
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded and hops > 0 and os.clock() - landedAt > Config.Bhop.window + 0.15 then
		hops = 0
	end
	local walking = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	local speed = weaponSpeed * slowed * (1 + hops * Config.Bhop.step)
	humanoid.WalkSpeed = if walking then speed * Config.WalkScale else speed
end

return Movement
