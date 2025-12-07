--!strict

local Pool = {}
Pool.__index = Pool

-- Generic helpers
export type InstanceList<I> = { I }
export type InstanceMap<I, T> = { [I]: T? }
export type ConnectionMap<I> = { [I]: RBXScriptConnection }
export type TimeoutMap<I> = { [I]: number }
export type FactoryFn<I> = () -> I
export type ConstructFn<I, O> = (instance: I, opts: O?) -> ()

-- Pool type: I = instance type, O = options type
export type Pool<I, O> = {
	active: boolean,
	size: number,
	timeout: number,

	-- Where live / in-use instances are parented
	hotSpot: Instance,
	-- Where pooled / idle instances are parented
	coldSpot: Instance,

	-- Bookkeeping lists for instances
	hotStorage: InstanceList<I>,
	coldStorage: InstanceList<I>,

	-- Destroying connections per-instance
	connections: ConnectionMap<I>,
	activeTimeouts: TimeoutMap<I>,

	factoryFunction: FactoryFn<I>,

	_getInstanceTotal: (self: Pool<I, O>) -> number,
	_needConstruct: (self: Pool<I, O>, amount: number?) -> boolean,
	construct: (
		self: Pool<I, O>,
		constructFunction: ConstructFn<I, O>,
		constructOpts: O?
	) -> I?,
	store: (self: Pool<I, O>, part: I) -> (),
	_queueTake: (self: Pool<I, O>) -> I?,
	_destroyListener: (self: Pool<I, O>, part: I) -> (),
	_removeTimeout: (self: Pool<I, O>, part: I) -> (),
	_startTimeout: (self: Pool<I, O>, part: I) -> (),
	_swapArray: (self: Pool<I, O>, part: I, startList: InstanceList<I>, endList: InstanceList<I>) -> (),
}

function Pool.new<I, O>(
	size: number, -- Max size of the pool.
	factoryFunction: FactoryFn<I>, -- The de-facto core function that creates the "template" of an object.
	timeout: number?, -- Optional timeout, auto stores objects after a set amount of time.
	hotStorage: Instance?,
	coldStorage: Instance?
): Pool<I, O>
	local self = setmetatable({}, Pool) :: Pool<I, O>

	hotStorage = hotStorage or workspace
	coldStorage = coldStorage or game.ReplicatedStorage
	timeout = timeout or 0
	if timeout < 0 then
		timeout = 0
	end	

	self.active = true
	self.size = size
	self.timeout = timeout
	self.hotSpot = hotStorage :: Instance
	self.coldSpot = coldStorage :: Instance
	self.hotStorage = {} :: InstanceList<I>
	self.coldStorage = {} :: InstanceList<I>
	self.connections = {} :: ConnectionMap<I>
	self.activeTimeouts = {} :: TimeoutMap<I>
	self.factoryFunction = factoryFunction

	task.spawn(function()
		while self.active do
			local currentTime = DateTime.now().UnixTimestamp
			for object, timeoutTime in self.activeTimeouts do
				if currentTime < timeoutTime then
					continue
				end
				self:_removeTimeout(object)
				self:store(object)
			end
			task.wait(1)
		end
	end)

	return self
end

function Pool._swapArray<I, O>(
	self: Pool<I, O>,
	part: I,
	startList: InstanceList<I>,
	endList: InstanceList<I>
): ()
	for i, obj in ipairs(startList) do
		if part == obj then
			table.remove(startList, i)
			table.insert(endList, part)
			break
		end
	end
end

function Pool._getInstanceTotal<I, O>(self: Pool<I, O>): number
	return #self.coldStorage + #self.hotStorage
end

function Pool._needConstruct<I, O>(self: Pool<I, O>, amount: number?): boolean
	amount = amount or 1

	local instanceCount: number = self:_getInstanceTotal()
	if instanceCount + (amount :: number) > self.size then
		return false
	end

	return true
end

-- Queue stack data structure. Return the oldest instance and re-append to the end.
function Pool._queueTake<I, O>(self: Pool<I, O>): I?
	local oldest: I?

	-- First check coldstorage, if coldstorage is empty we just take the last object from hotstorage.
	if #self.coldStorage > 0 then
		oldest = table.remove(self.coldStorage, 1)
	elseif #self.hotStorage > 0 then
		oldest = table.remove(self.hotStorage, 1)
	else
		error("[FluxPool] There is no instance in any storage to take.")
		return nil
	end
	return oldest
end

function Pool._destroyListener<I, O>(self: Pool<I, O>, part: I): ()
	if self.connections[part] then return end
	local connection: RBXScriptConnection = (part :: any).Destroying:Connect(function()
		self:_removeTimeout(part)

		local conn = self.connections[part]
		if conn ~= nil then
			conn:Disconnect()
			self.connections[part] = nil
		end

		for i, obj in ipairs(self.hotStorage) do
			if obj == part then
				table.remove(self.hotStorage, i)
				return
			end
		end
		for i, obj in ipairs(self.coldStorage) do
			if obj == part then
				table.remove(self.coldStorage, i)
				return
			end
		end
		return
	end)
	self.connections[part] = connection
end

function Pool._removeTimeout<I, O>(self: Pool<I, O>, part: I): ()
	if not self.activeTimeouts[part] then
		return
	end
	self.activeTimeouts[part] = nil
end

function Pool._startTimeout<I, O>(self: Pool<I, O>, part: I): ()
	if self.timeout <= 0 then
		return
	end -- Timeout of 0 equals no timeout.

	self.activeTimeouts[part] = DateTime.now().UnixTimestamp + self.timeout
end

function Pool.construct<I, O>(
	self: Pool<I, O>,
	constructFunction: ConstructFn<I, O>,
	constructOpts: O?
): I?
	constructOpts = constructOpts or nil

	local object: I?

	if self:_needConstruct() then
		object = self.factoryFunction()
	else
		object = self:_queueTake()
	end

	if constructOpts then
		constructFunction(object :: I, constructOpts)
	else
		constructFunction(object :: I, nil)
	end

	table.insert(self.hotStorage, object :: I)
	self:_destroyListener(object :: I)
	self:_startTimeout(object)
	
	local inst = object :: Instance
	if inst.Parent ~= self.hotSpot then
		inst.Parent = self.hotSpot
	end
	
	return object
end

function Pool.store<I, O>(self: Pool<I, O>, part: I): ()
	self:_swapArray(part, self.hotStorage, self.coldStorage)
	self:_removeTimeout(part)
	local inst = part :: Instance
	inst.Parent = self.coldSpot
end

return Pool