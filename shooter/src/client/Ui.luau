--!strict
-- Короткие помощники для сборки интерфейса из кода.

local Ui = {}

Ui.font = Enum.Font.GothamBold
Ui.dark = Color3.fromRGB(18, 20, 26)
Ui.white = Color3.new(1, 1, 1)
Ui.teamColors = {
	T = Color3.fromRGB(232, 166, 62),
	CT = Color3.fromRGB(92, 158, 240),
} :: { [string]: Color3 }

-- Создаёт объект: сначала свойства, потом дети, в конце Parent
function Ui.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance: any = Instance.new(className :: any)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function merge(defaults: { [string]: any }, props: { [string]: any }): { [string]: any }
	for key, value in props do
		defaults[key] = value
	end
	return defaults
end

function Ui.frame(props: { [string]: any }, children: { Instance }?): Frame
	return Ui.new("Frame", merge({ BackgroundColor3 = Ui.dark, BorderSizePixel = 0 }, props), children)
end

function Ui.label(props: { [string]: any }, children: { Instance }?): TextLabel
	return Ui.new(
		"TextLabel",
		merge({ BackgroundTransparency = 1, BorderSizePixel = 0, Font = Ui.font, TextColor3 = Ui.white, TextSize = 18, Text = "" }, props),
		children
	)
end

function Ui.button(props: { [string]: any }, children: { Instance }?): TextButton
	return Ui.new(
		"TextButton",
		merge({
			BackgroundColor3 = Color3.fromRGB(40, 44, 54),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Ui.font,
			TextColor3 = Ui.white,
			TextSize = 18,
			Text = "",
		}, props),
		children
	)
end

function Ui.corner(radius: number): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Ui.stroke(color: Color3, thickness: number): UIStroke
	return Ui.new("UIStroke", { Color = color, Thickness = thickness })
end

function Ui.list(direction: Enum.FillDirection, padding: number): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

return Ui
