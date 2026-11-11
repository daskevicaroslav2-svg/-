-- Dust II: упрощённая блочная копия планировки классической карты.
-- T появляются на юге, CT — на севере, точка A на северо-востоке, точка B на северо-западе.
-- Проверка и картинки: lune run shooter-map dust2

local kit = require("./kit")

local m = kit.map("Dust2", "Dust II")

m:style("tunnel", 128, 112, 92, "Concrete")
m:style("car", 146, 72, 58, "Metal")
m:style("glass", 52, 70, 84, "SmoothPlastic")

-- Высоты пола по зонам
local T_SPAWN, YARD, TOP_MID, MID, LOW_MID, CT_SPAWN = 10, 6, 8, 4, 2, 0
local LONG, PIT, A_SITE, CATWALK, B_SITE, TUNNEL = 4, 0, 10, 8, 4, 8
-- Верх крыши туннелей
local ROOF = 18

-- Здание: сплошной блок от основания карты до крыши на высоте top
local function building(x1, z1, x2, z2, top, style)
	m:box(x1, z1, x2, z2, kit.BASE, top, style or "wall")
end

-- Внешние стены и застройка за северной стеной
building(-128, 116, 130, 120, 30, "wall2")
building(-128, -132, -124, 116, 30, "wall2")
building(126, -132, 130, 116, 30, "wall2")
building(-128, -152, -28, -132, 30, "wall2")
building(-28, -152, 40, -148, 30, "wall2")
building(40, -152, 130, -132, 30, "wall2")

-- Появление T: плато на юге, спуски на запад (к туннелям) и на восток (к длине)
m:ground(-56, 76, 8, 116, T_SPAWN)
m:ramp(-68, 80, -56, 100, YARD, T_SPAWN, "+x")
m:ramp(8, 80, 20, 100, YARD, T_SPAWN, "-x")
building(-124, 102, -68, 116, 28)
building(-68, 100, -56, 116, 26, "wall2")
building(-68, 76, -56, 80, 28)
building(8, 100, 20, 116, 26, "wall2")
building(8, 76, 20, 80, 28)
building(20, 104, 70, 116, 28)
m:crate(-54, 108, 8, 8, 5, T_SPAWN)
m:crate(-2, 110, 6, 6, 4, T_SPAWN, "crate2")

-- Спуск с плато в мид («суицид») и верх мида
m:ramp(-22, 60, -6, 76, TOP_MID, T_SPAWN, "+z")
m:ground(-22, 44, -6, 60, TOP_MID)
m:ground(-28, 20, 0, 44, TOP_MID)
building(-76, 44, -22, 76, 30, "wall2")
building(-6, 44, 20, 76, 28, "wall2")
building(-76, 30, -28, 44, 26)
m:crate(-28, 22, 6, 6, 5, TOP_MID, "crate2")
-- Проход из верха мида к двору перед длиной
m:ramp(0, 30, 12, 44, YARD, TOP_MID, "-x")
m:ground(12, 30, 20, 44, YARD)

-- Мид: спуск на север к Xbox и дверям
m:ramp(-28, -2, 0, 20, MID, TOP_MID, "+z")
m:ground(-28, -26, 0, -2, MID)
m:ramp(-28, -34, 0, -26, LOW_MID, MID, "+z")
m:ground(-28, -40, 0, -34, LOW_MID)
building(-94, 14, -28, 30, 28, "wall2")
building(-92, -10, -28, 14, 24)
building(-68, -74, -28, -22, 30)
building(0, -2, 14, 30, 26, "wall2")
-- Xbox: большой ящик под краем кэтволка
m:crate(-8, -26, 8, 8, 5, MID)

-- Двери мида: двойные створки с проёмом посередине
m:ground(-22, -44, -6, -40, LOW_MID)
building(-28, -44, -22, -40, 24, "trim")
building(-6, -44, 0, -40, 24, "trim")
m:box(-22, -44, -6, -40, 14, 24, "trim")
m:box(-22, -44, -18, -42, LOW_MID, 12, "wood")
m:box(-10, -42, -6, -40, LOW_MID, 12, "wood")

-- Мид CT и спуск к появлению CT
m:ground(-28, -96, 0, -44, LOW_MID)
m:ramp(-28, -104, 0, -96, CT_SPAWN, LOW_MID, "+z")
building(0, -92, 34, -34, 28)
building(0, -104, 24, -92, 24, "wall2")
m:crate(-28, -72, 6, 6, 4, LOW_MID)
m:crate(-6, -62, 6, 8, 5, LOW_MID, "crate2")

-- Появление CT: самая низкая площадь, на восток пандус к точке A
m:ground(-28, -148, 40, -104, CT_SPAWN)
m:ground(24, -104, 40, -92, CT_SPAWN)
m:ramp(40, -104, 66, -92, CT_SPAWN, A_SITE, "+x")
building(40, -132, 66, -104, 30)
building(46, -92, 66, -86, 24, "wall2")
m:crate(32, -148, 8, 8, 5, CT_SPAWN)
m:crate(-28, -148, 8, 6, 4, CT_SPAWN, "crate2")
m:crate(8, -110, 6, 6, 4, CT_SPAWN)

-- Кэтволк: пандус из мида у Xbox и мостки на северо-восток
m:ground(0, -8, 14, -2, MID)
m:ramp(0, -20, 14, -8, MID, CATWALK, "-z")
m:ground(0, -34, 14, -20, CATWALK)
m:ground(14, -34, 34, -22, CATWALK)
building(14, -22, 46, -8, 24, "wall2")
building(14, -8, 56, 30, 30)
-- Шорт: выход с кэтволка к точке A, с северного края можно спрыгнуть к CT
m:ground(34, -92, 46, -22, CATWALK)
m:ground(46, -86, 54, -72, CATWALK)
m:ramp(54, -86, 66, -72, CATWALK, A_SITE, "+x")

-- Точка A: приподнятая площадка с ящиками
m:ground(66, -132, 92, -72, A_SITE, "site")
m:ground(92, -112, 106, -72, A_SITE, "site")
building(46, -72, 76, -8, 32)
building(76, -72, 106, -8, 26, "wall2")
m:crate(80, -108, 8, 8, 6, A_SITE)
m:crate(88, -104, 6, 6, 4, A_SITE, "crate2")
m:crate(72, -82, 6, 8, 5, A_SITE)
m:crate(100, -92, 6, 6, 4, A_SITE, "crate2")
-- «Гусь»: северо-восточный угол площадки
m:wall(78, -132, 80, -124, A_SITE, 7, "wall2")
m:crate(86, -132, 6, 6, 5, A_SITE)

-- Длина A: дорожка вдоль восточной стены, на севере пандус на запад к точке
m:ground(106, -132, 126, 30, LONG)
m:ramp(92, -132, 106, -112, LONG, A_SITE, "-x")
m:crate(106, -46, 4, 8, 4, LONG)
m:crate(120, -86, 6, 6, 5, LONG, "crate2")
-- Машина на повороте к пандусу
m:box(114, -132, 126, -126, LONG, LONG + 3, "car")
m:box(116, -132, 122, -126, LONG + 3, LONG + 5, "glass")
-- Яма в юго-восточном конце длины
m:ramp(106, 30, 126, 46, PIT, LONG, "-z")
m:ground(106, 46, 126, 64, PIT)
m:crate(120, 56, 6, 8, 4, PIT)

-- Угол длины и ниша с синим контейнером
m:ground(56, 4, 106, 24, LONG)
m:ground(56, -8, 72, 4, LONG)
building(72, -8, 106, 4, 28)
m:box(56, -8, 64, 4, LONG, LONG + 7, "accent")
m:crate(98, 4, 8, 6, 5, LONG)

-- Двери длины: коридор с двумя рамами подряд
m:ground(56, 24, 70, 36, LONG)
m:ramp(56, 36, 70, 46, LONG, YARD, "+z")
m:ground(56, 46, 70, 56, YARD)
building(70, 24, 106, 64, 28, "wall2")
building(44, 30, 56, 56, 26)
for _, frame in { { z = 48, y = YARD }, { z = 26, y = LONG } } do
	local z, y = frame.z, frame.y
	m:box(56, z, 58, z + 4, y, y + 14, "trim")
	m:box(68, z, 70, z + 4, y, y + 14, "trim")
	m:box(58, z, 68, z + 4, y + 11, y + 14, "trim")
	-- Распахнутые створки вдоль стен
	m:box(56, z + 4, 58, z + 8, y, y + 10, "wood")
	m:box(68, z + 4, 70, z + 8, y, y + 10, "wood")
end

-- Двор перед длиной
m:ground(20, 56, 70, 104, YARD)
m:ground(20, 30, 44, 56, YARD)
building(70, 64, 126, 116, 32)
m:crate(38, 70, 8, 8, 5, YARD)
m:crate(46, 72, 6, 6, 3, YARD, "crate2")
m:crate(64, 96, 6, 8, 4, YARD)
m:crate(20, 46, 6, 8, 4, YARD, "crate2")

-- Двор перед туннелями
m:ground(-124, 30, -76, 102, YARD)
m:ground(-76, 76, -68, 102, YARD)
m:crate(-92, 30, 8, 8, 5, YARD)
m:crate(-124, 58, 6, 10, 4, YARD, "crate2")
m:crate(-102, 82, 8, 8, 5, YARD)

-- Верхние туннели: вход со двора, зал под крышей и спуск к точке B
m:ramp(-108, 14, -94, 30, YARD, TUNNEL, "-z", "tunnel")
m:ground(-124, -30, -92, 14, TUNNEL, "tunnel")
m:ground(-112, -40, -98, -30, TUNNEL, "tunnel")
m:ramp(-112, -56, -98, -40, B_SITE, TUNNEL, "+z", "tunnel")
m:ground(-112, -64, -98, -56, B_SITE, "tunnel")
building(-124, 14, -108, 30, 26)
building(-124, -64, -112, -30, 26, "wall2")
building(-98, -64, -68, -30, 28, "wall2")
building(-92, -30, -68, -22, 24)
m:platform(-108, 14, -94, 30, ROOF, 2, "roof")
m:platform(-124, -30, -92, 14, ROOF, 1, "roof")
m:platform(-112, -56, -98, -30, ROOF, 1, "roof")
m:platform(-112, -64, -98, -56, ROOF, 5, "roof")
m:crate(-124, 4, 8, 10, 4, TUNNEL, "crate2")
m:crate(-124, -30, 8, 8, 5, TUNNEL)

-- Нижние туннели: из зала на восток и вниз в мид
m:ground(-92, -22, -70, -10, TUNNEL, "tunnel")
m:ramp(-70, -22, -50, -10, MID, TUNNEL, "-x", "tunnel")
m:ground(-50, -22, -28, -10, MID, "tunnel")
m:platform(-92, -22, -50, -10, ROOF, 1, "roof")
m:platform(-50, -22, -28, -10, ROOF, 5, "roof")

-- Точка B: закрытый двор с площадкой, выход из туннелей на юге
m:ground(-124, -132, -68, -64, B_SITE)
m:box(-114, -122, -82, -96, B_SITE, B_SITE + 1.5, "site")
m:crate(-104, -114, 8, 8, 6, B_SITE + 1.5)
m:crate(-96, -112, 6, 6, 3, B_SITE + 1.5, "crate2")
m:box(-124, -132, -104, -124, B_SITE, B_SITE + 1.5, "floor2")
m:crate(-124, -94, 6, 10, 5, B_SITE)
-- Машина у выхода из туннелей
m:box(-96, -76, -84, -70, B_SITE, B_SITE + 3, "car")
m:box(-92, -76, -86, -70, B_SITE + 3, B_SITE + 5, "glass")

-- Двери B: двойные створки в восточной стене и проход к миду CT
m:ground(-68, -90, -64, -74, B_SITE)
m:box(-68, -90, -64, -74, 15, 26, "trim")
m:box(-68, -90, -66, -86, B_SITE, 14, "wood")
m:box(-66, -78, -64, -74, B_SITE, 14, "wood")
m:ground(-64, -90, -54, -74, B_SITE)
m:ramp(-54, -90, -44, -74, LOW_MID, B_SITE, "-x")
m:ground(-44, -90, -28, -74, LOW_MID)

-- Окно B: комната над проходом, из неё можно спрыгнуть на точку
m:ground(-64, -94, -54, -90, B_SITE)
m:ramp(-64, -104, -54, -94, B_SITE, 7, "-z")
m:ground(-64, -112, -54, -104, 7)
building(-68, -112, -64, -104, 8)
m:box(-68, -112, -64, -104, 14.5, 28)
building(-68, -132, -54, -112, 28)
building(-54, -132, -28, -90, 28)
building(-68, -104, -64, -90, 28)
m:platform(-64, -112, -54, -90, ROOF, 1, "roof")
m:crate(-74, -112, 6, 8, 4, B_SITE)

-- Точки появления
for i, x in { -14, -22, -6 } do
	m:spawn("T", x, 84, T_SPAWN, 0)
	m:spawn("T", x + 4, 92, T_SPAWN, 0)
	m:spawn("CT", 4 + (i - 1) * 8, -140, CT_SPAWN, 180)
	m:spawn("CT", 8 + (i - 1) * 8, -132, CT_SPAWN, 180)
end

-- Метки мест
m:mark("TSpawn", -24, 100, T_SPAWN)
m:mark("CTSpawn", 12, -124, CT_SPAWN)
m:mark("ASite", 90, -114, A_SITE)
m:mark("BSite", -98, -102, B_SITE + 1.5)
m:mark("Mid", -14, -10, MID)
m:mark("TopMid", -14, 32, TOP_MID)
m:mark("Xbox", -14, -22, MID)
m:mark("MidDoors", -14, -42, LOW_MID)
m:mark("CTMid", -14, -70, LOW_MID)
m:mark("OutsideLong", 44, 84, YARD)
m:mark("LongDoors", 62, 40, 5)
m:mark("LongA", 116, -50, LONG)
m:mark("Pit", 114, 56, PIT)
m:mark("ARamp", 100, -122, 7)
m:mark("Catwalk", 24, -28, CATWALK)
m:mark("Short", 40, -70, CATWALK)
m:mark("BDoors", -66, -82, B_SITE)
m:mark("UpperTunnels", -108, -8, TUNNEL)
m:mark("LowerTunnels", -40, -16, MID)
m:mark("OutsideTunnels", -100, 60, YARD)

-- Ракурсы предпросмотра и камера меню
m:view("outside long -> long doors", 40, 10.5, 84, 62, 10, 50)
m:view("long A towards A site", 116, 8.5, 20, 112, 9, -120)
m:view("A site from the long ramp", 112, 8.5, -118, 78, 13, -102)
m:view("A site from short", 50, 12.5, -80, 92, 13, -104)
m:view("top mid towards mid doors", -14, 12.5, 40, -14, 6, -44)
m:view("catwalk and xbox from mid", -20, 8.5, 0, 6, 9, -30)
m:view("mid doors from CT mid", -14, 6.5, -84, -14, 6, -40)
m:view("upper tunnels", -100, 12.5, 10, -106, 11, -40)
m:view("B site from the tunnel exit", -105, 8.5, -60, -92, 8, -110)
m:view("B doors and window from B site", -100, 8.5, -100, -66, 9, -90)
m:view("CT spawn towards the A ramp", -8, 4.5, -120, 44, 6, -98)
m:view("outside tunnels", -80, 10.5, 92, -102, 10, 28)
m:overview(150, 170, 150, 0, 0, -20)

return m
