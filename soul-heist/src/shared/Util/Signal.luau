--[[
	Signal
	Minimal server/client signal for communication between modules (not across the network).
]]

export type Connection = { Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	local handlers = self._handlers
	return {
		Disconnect = function()
			handler.Connected = false
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	} :: any
end

function Signal:Fire(...: any)
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

return Signal
