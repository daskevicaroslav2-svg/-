--!strict
-- Форматирование чисел для табличек и интерфейса.

local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

local function trimZeros(text: string): string
	return (text:gsub("%.?0+$", ""))
end

-- 1234 -> "$1,234"; 2500000 -> "$2.5M"
function Format.money(amount: number): string
	amount = math.max(0, math.floor(amount))
	if amount < 1e6 then
		local grouped = tostring(amount):reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if grouped:sub(1, 1) == "," then
			grouped = grouped:sub(2)
		end
		return "$" .. grouped
	end
	local index = 0
	while amount >= 1000 and index < #SUFFIXES do
		amount /= 1000
		index += 1
	end
	return "$" .. trimZeros(string.format("%.2f", amount)) .. SUFFIXES[index]
end

-- 1.5 -> "1.5"; 2 -> "2"
function Format.multiplier(value: number): string
	return trimZeros(string.format("%.2f", value))
end

return Format
