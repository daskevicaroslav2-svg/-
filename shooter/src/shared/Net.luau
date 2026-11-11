--!strict
-- Сообщения между клиентом и сервером через два RemoteEvent: имя сообщения и аргументы.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local toServer = remotes:WaitForChild("ToServer") :: RemoteEvent
local toClient = remotes:WaitForChild("ToClient") :: RemoteEvent

local Net = {}

local handlers: { [string]: (...any) -> () } = {}
-- Сообщения, пришедшие раньше, чем модуль-получатель подписался
local pending: { [string]: { { any } } } = {}

local function dispatch(name: any, ...: any)
	if typeof(name) ~= "string" then
		return
	end
	local handler = handlers[name]
	if handler then
		handler(...)
	elseif not RunService:IsServer() then
		local queue = pending[name] or {}
		pending[name] = queue
		if #queue < 32 then
			table.insert(queue, table.pack(...))
		end
	end
end

-- На сервере обработчик получает игрока первым аргументом
function Net.on(name: string, handler: (...any) -> ())
	handlers[name] = handler
	local queue = pending[name]
	if queue then
		pending[name] = nil
		for _, args in queue do
			handler(table.unpack(args, 1, (args :: any).n))
		end
	end
end

function Net.send(name: string, ...: any)
	toServer:FireServer(name, ...)
end

function Net.sendTo(player: Player, name: string, ...: any)
	toClient:FireClient(player, name, ...)
end

function Net.broadcast(name: string, ...: any)
	toClient:FireAllClients(name, ...)
end

if RunService:IsServer() then
	toServer.OnServerEvent:Connect(function(player: Player, name: any, ...: any)
		if typeof(name) == "string" then
			local handler = handlers[name]
			if handler then
				handler(player, ...)
			end
		end
	end)
else
	toClient.OnClientEvent:Connect(dispatch)
end

return Net
