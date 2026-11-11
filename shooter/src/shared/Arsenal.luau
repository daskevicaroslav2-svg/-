--!strict
-- Единая точка доступа к моделям, анимациям и скинам всего оружия.

local Anim = require(script.Parent.Anim)
local GrenadeAnims = require(script.Parent.GrenadeAnims)
local GrenadeModels = require(script.Parent.GrenadeModels)
local GunAnims = require(script.Parent.GunAnims)
local GunModels = require(script.Parent.GunModels)
local GunSkins = require(script.Parent.GunSkins)
local KnifeAnims = require(script.Parent.KnifeAnims)
local KnifeModels = require(script.Parent.KnifeModels)
local KnifeSkins = require(script.Parent.KnifeSkins)
local Rig = require(script.Parent.Rig)

local Arsenal = {}

local NO_SKINS: { Rig.Skin } = {}

function Arsenal.model(modelId: string): Rig.ModelSpec?
	return GunModels[modelId] or KnifeModels[modelId] or GrenadeModels[modelId]
end

function Arsenal.isKnife(modelId: string): boolean
	return KnifeModels[modelId] ~= nil
end

-- Все типы ножей; стандартный Classic идёт первым
function Arsenal.knives(): { string }
	local ids = {}
	for id in KnifeModels do
		if id ~= "Classic" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	table.insert(ids, 1, "Classic")
	return ids
end

-- Анимации: equip, reload, inspect, secret у оружия; equip, slash, stab, inspect, secret у ножей;
-- equip, throw, inspect, secret у гранат (общие на все гранаты)
function Arsenal.animation(modelId: string, name: string): Anim.Animation?
	local set: { [string]: Anim.Animation }? = GunAnims[modelId] or KnifeAnims[modelId]
	if not set and GrenadeModels[modelId] then
		set = GrenadeAnims
	end
	return if set then set[name] else nil
end

-- Скины модели; первый в списке — стандартный. У всех ножей общий набор.
function Arsenal.skins(modelId: string): { Rig.Skin }
	if KnifeModels[modelId] then
		return KnifeSkins
	end
	return GunSkins[modelId] or NO_SKINS
end

function Arsenal.skin(modelId: string, skinId: string?): Rig.Skin?
	for _, skin in Arsenal.skins(modelId) do
		if skin.id == skinId then
			return skin
		end
	end
	return nil
end

function Arsenal.rig(modelId: string, skinId: string?, team: string?): Rig.Rig?
	local spec = Arsenal.model(modelId)
	return if spec then Rig.describe(spec, Arsenal.skin(modelId, skinId), team) else nil
end

return Arsenal
