--!strict
-- Состояние матча на сервере и его копия для клиентов в атрибутах ReplicatedStorage.State.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("State")

local State = {
	phase = "Waiting", -- Waiting, Freeze, Live, RoundEnd, MatchEnd
	phaseEnds = 0,
	buyEnds = 0,
	round = 0,
	map = "",
	score = { T = 0, CT = 0 },
}

function State.now(): number
	return Workspace:GetServerTimeNow()
end

function State.setPhase(phase: string, duration: number)
	State.phase = phase
	State.phaseEnds = State.now() + duration
	folder:SetAttribute("PhaseEnds", State.phaseEnds)
	folder:SetAttribute("Phase", phase)
end

function State.setBuyTime(duration: number)
	State.buyEnds = State.now() + duration
	folder:SetAttribute("BuyEnds", State.buyEnds)
end

function State.publish()
	folder:SetAttribute("Round", State.round)
	folder:SetAttribute("Map", State.map)
	folder:SetAttribute("ScoreT", State.score.T)
	folder:SetAttribute("ScoreCT", State.score.CT)
end

function State.setAlive(t: number, ct: number)
	folder:SetAttribute("AliveT", t)
	folder:SetAttribute("AliveCT", ct)
end

function State.isLive(): boolean
	return State.phase == "Live"
end

function State.canBuy(): boolean
	return (State.phase == "Freeze" or State.phase == "Live") and State.now() < State.buyEnds
end

State.setPhase("Waiting", 0)
State.setBuyTime(0)
State.setAlive(0, 0)
State.publish()

return State
