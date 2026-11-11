--!strict
-- Покадровые анимации вида от первого лица: дорожки из ключей с позицией и поворотом.
--
-- Дорожка называется по тому, что она двигает:
--   gun          — всё оружие целиком (вместе с руками, если они не отцеплены);
--   armR, armL   — правая и левая рука;
--   имя детали   — одна деталь модели (и детали, у которых она указана как parent).
-- Смещение дорожки задаётся в локальных осях того, что она двигает.

export type Key = { t: number, cf: CFrame, ease: string? }

export type Animation = {
	duration: number,
	tracks: { [string]: { Key } },
	pivots: { [string]: Vector3 }?, -- точка, вокруг которой дорожка вращает (по умолчанию начало координат)
	detach: { [string]: boolean }?, -- armR/armL = true: рука не следует за оружием
	events: { { t: number, name: string } }?, -- метки для звуков
}

local Anim = {}

local IDENTITY = CFrame.new()

-- Ключ: время в секундах, смещение {x, y, z} в studs, поворот {тангаж, рысканье, крен} в градусах.
-- Оси: +X вправо, +Y вверх, -Z вперёд (от камеры). Тангаж + поднимает нос, рысканье + поворачивает
-- нос влево, крен + наклоняет верх влево. ease: smooth (по умолчанию), linear, in, out, hold.
function Anim.key(t: number, position: { number }?, rotation: { number }?, ease: string?): Key
	local p = position or { 0, 0, 0 }
	local r = rotation or { 0, 0, 0 }
	return {
		t = t,
		cf = CFrame.new(p[1], p[2], p[3]) * CFrame.fromOrientation(math.rad(r[1]), math.rad(r[2]), math.rad(r[3])),
		ease = ease,
	}
end

local function ease(kind: string?, x: number): number
	if kind == "linear" then
		return x
	elseif kind == "in" then
		return x * x
	elseif kind == "out" then
		return 1 - (1 - x) * (1 - x)
	elseif kind == "hold" then
		return 0
	end
	return x * x * (3 - 2 * x)
end

function Anim.sampleTrack(track: { Key }, t: number): CFrame
	local count = #track
	if count == 0 then
		return IDENTITY
	end
	if t <= track[1].t then
		return track[1].cf
	end
	for i = 2, count do
		local b = track[i]
		if t < b.t then
			local a = track[i - 1]
			return a.cf:Lerp(b.cf, ease(b.ease, (t - a.t) / (b.t - a.t)))
		end
	end
	return track[count].cf
end

-- Поза в момент t: имя дорожки -> смещение
function Anim.sample(animation: Animation, t: number): { [string]: CFrame }
	local pose = {}
	for name, track in animation.tracks do
		local cf = Anim.sampleTrack(track, t)
		local pivot = animation.pivots and animation.pivots[name]
		if pivot then
			cf = CFrame.new(pivot) * cf * CFrame.new(-pivot)
		end
		pose[name] = cf
	end
	return pose
end

return Anim
