--!strict
-- Звуки: названия берутся из Config.Sounds. Если файл звука недоступен, игра просто молчит.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Sounds = {}

local ids: { [string]: string } = Config.Sounds
local cache: { [string]: Sound } = {}

local function template(name: string): Sound?
	local id = ids[name]
	if not id or id == "" then
		return nil
	end
	local cached = cache[name]
	if cached then
		return cached
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Parent = SoundService
	cache[name] = sound
	return sound
end

-- Без position звук слышен одинаково везде, с position — из точки в мире
function Sounds.play(name: string, volume: number?, position: Vector3?)
	local sound = template(name)
	if not sound then
		return
	end
	if not position then
		sound.Volume = volume or 0.5
		SoundService:PlayLocalSound(sound)
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = Workspace.Terrain
	local copy = sound:Clone()
	copy.Volume = volume or 0.6
	copy.RollOffMaxDistance = 300
	copy.Parent = anchor
	copy:Play()
	Debris:AddItem(anchor, 4)
end

return Sounds
