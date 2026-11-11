-- Сцены для tools/render.py: переводит детали в координаты камеры и запускает рендер.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Scene = {}

-- Компоненты CFrame в порядке Roblox: позиция и матрица поворота по строкам
function Scene.components(cf)
	local p, r, u, l = cf.Position, cf.RightVector, cf.UpVector, cf.LookVector
	return { p.X, p.Y, p.Z, r.X, u.X, -l.X, r.Y, u.Y, -l.Y, r.Z, u.Z, -l.Z }
end

function Scene.prim(camera, shape, size, cf, color, alpha)
	return {
		shape = shape,
		size = { size.X, size.Y, size.Z },
		cf = Scene.components(camera:Inverse() * cf),
		color = { color.R * 255, color.G * 255, color.B * 255 },
		alpha = alpha or 1,
	}
end

function Scene.point(camera, position)
	local p = camera:Inverse() * position
	return { p.X, p.Y, p.Z }
end

-- Рисует сцену в PNG. Нужен python3 с numpy и pillow.
function Scene.render(scene, out)
	local dir = out:match("^(.*)/[^/]*$")
	if dir and not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local jsonPath = out .. ".json"
	fs.writeFile(jsonPath, serde.encode("json", scene))
	local result = process.exec("python3", { "tools/render.py", jsonPath, out })
	fs.removeFile(jsonPath)
	if not result.ok then
		error("tools/render.py: " .. result.stderr)
	end
	print("  " .. out)
end

return Scene
