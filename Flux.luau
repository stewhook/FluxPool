--[[
v1.1.0
Created by stewhook.
Flux is a modular object pooling framework designed for simplicity and scalability.
Open-source and maintained at: https://github.com/stewhook/FluxPool
Report any issues to the github above. Feel free to contribute. Godspeed.

__/\\\\\\\\\\\\\\\__/\\\______________/\\\________/\\\__/\\\_______/\\\_        
 _\/\\\///////////__\/\\\_____________\/\\\_______\/\\\_\///\\\___/\\\/__       
  _\/\\\_____________\/\\\_____________\/\\\_______\/\\\___\///\\\\\\/____      
   _\/\\\\\\\\\\\_____\/\\\_____________\/\\\_______\/\\\_____\//\\\\______     
    _\/\\\///////______\/\\\_____________\/\\\_______\/\\\______\/\\\\______    
     _\/\\\_____________\/\\\_____________\/\\\_______\/\\\______/\\\\\\_____   
      _\/\\\_____________\/\\\_____________\//\\\______/\\\_____/\\\////\\\___  
       _\/\\\_____________\/\\\\\\\\\\\\\\\__\///\\\\\\\\\/____/\\\/___\///\\\_ 
        _\///______________\///////////////_____\/////////_____\///_______\///__

]]--

--!strict

local Pool = {}
Pool.__index = Pool

-- Generic helpers / types

export type InstanceList<I> = { I? }
export type ConnectionMap<I> = { [I]: RBXScriptConnection }
export type TimeoutMap<I> = { [I]: number }
export type FactoryFn<I> = () -> I
export type ConstructFn<I, O> = (instance: I, opts: O?) -> ()
export type CleanupFn<I> = (instance: I) -> ()

export type QueueName = "hot" | "cold"

export type Queue<I> = {
	head: number,
	tail: number,
	count: number,
	buffer: InstanceList<I>,
	free: { number },
}

export type IndexInfo<I> = {
	queue: QueueName,
	index: number,
}

export type IndexMap<I> = { [I]: IndexInfo<I> }

-- Pool type: I = instance type, O = options type
export type Pool<I, O> = {
	-- Config
	active: boolean,
	size: number,
	timeout: number,

	-- Parent Containers (Default to Replicated Storage + Workspace)
	hotSpot: Instance?,
	coldSpot: Instance?,

	-- Public API surface
	construct: (
		self: Pool<I, O>,
		constructFunction: ConstructFn<I, O>,
		constructOpts: O?
	) -> I?,
	store: (self: Pool<I, O>, part: I) -> (),
	wipe: (self: Pool<I, O>, cleanupFunction: CleanupFn<I>) -> (),
	getIdleCount: (self: Pool<I, O>) -> number,
	getActiveCount: (self: Pool<I, O>) -> number,
}

type InternalPool<I, O> = Pool<I, O> & {
	_hotQueue: Queue<I>,
	_coldQueue: Queue<I>,
	_indexMap: IndexMap<I>,

	connections: ConnectionMap<I>,
	activeTimeouts: TimeoutMap<I>,

	factoryFunction: FactoryFn<I>,
}

-- Private helpers

local function _getQueue<I, O>(self: InternalPool<I, O>, which: QueueName): Queue<I>
	if which == "hot" then
		return self._hotQueue
	else
		return self._coldQueue
	end
end

local function _getInstanceTotal<I, O>(self: InternalPool<I, O>): number
	return self._hotQueue.count + self._coldQueue.count
end

local function _needConstruct<I, O>(self: InternalPool<I, O>, amount: number?): boolean
	amount = amount or 1
	local instanceCount = _getInstanceTotal(self)
	if instanceCount + (amount :: number) > self.size then
		return false
	end
	return true
end

local function _enqueue<I, O>(self: InternalPool<I, O>, which: QueueName, obj: I)
	local queue = _getQueue(self, which)

	if queue.count >= self.size then
		error("[FluxPool] Internal queue overflow; more instances than pool size.")
	end

	local index: number
	local free: {number} = queue.free

	if #free > 0 then
		local popped = table.remove(free)
		if popped == nil then
			error("[FluxPool] free list empty despite #free > 0")
		end
		index = popped -- now index: number
	else
		local tail = queue.tail + 1
		if tail > self.size then
			tail = 1
		end
		queue.tail = tail
		index = tail
	end

	queue.buffer[index] = obj
	queue.count += 1

	self._indexMap[obj] = {
		queue = which,
		index = index,
	}
end

local function _dequeue<I, O>(self: InternalPool<I, O>, which: QueueName): I?
	local queue = _getQueue(self, which)
	if queue.count == 0 then
		return nil
	end

	local size = self.size

	while queue.count > 0 do
		local head = queue.head
		local obj = queue.buffer[head]

		local nextHead = head + 1
		if nextHead > size then
			nextHead = 1
		end
		queue.head = nextHead

		if obj ~= nil then
			queue.buffer[head] = nil
			queue.count -= 1

			table.insert(queue.free, head)

			local info = self._indexMap[obj]
			if info ~= nil then
				self._indexMap[obj] = nil
			end

			return obj
		end
	end

	return nil
end

local function _removeFromQueues<I, O>(self: InternalPool<I, O>, part: I): boolean
	local info = self._indexMap[part]
	if info == nil then
		return false
	end

	local queue = _getQueue(self, info.queue)
	local index = info.index
	local stored = queue.buffer[index]

	if stored == part then
		queue.buffer[index] = nil
		if queue.count > 0 then
			queue.count -= 1
		end

		table.insert(queue.free, index)

		self._indexMap[part] = nil
		return true
	end

	warn("[FluxPool] Cleaning up stale index reference for", part)
	self._indexMap[part] = nil
	return false
end

local function _queueTake<I, O>(self: InternalPool<I, O>): I?
	local obj = _dequeue(self, "cold")
	if obj ~= nil then
		return obj
	end

	obj = _dequeue(self, "hot")
	if obj ~= nil then
		return obj
	end

	error("[FluxPool] There is no instance in any storage to take.")
end

local function _removeTimeout<I, O>(self: InternalPool<I, O>, part: I): ()
	if not self.activeTimeouts[part] then
		return
	end
	self.activeTimeouts[part] = nil
end

local function _startTimeout<I, O>(self: InternalPool<I, O>, part: I): ()
	if self.timeout <= 0 then
		return
	end

	self.activeTimeouts[part] = DateTime.now().UnixTimestamp + self.timeout
end

local function _destroyListener<I, O>(self: InternalPool<I, O>, part: I): ()
	if self.connections[part] then
		return
	end

	local connection: RBXScriptConnection = (part :: any).Destroying:Connect(function()
		_removeTimeout(self, part)

		_removeFromQueues(self, part)

		local conn = self.connections[part]
		if conn ~= nil then
			conn:Disconnect()
			self.connections[part] = nil
		end
	end)

	self.connections[part] = connection
end

-- Public API

function Pool.new<I, O>(
	size: number,
	factoryFunction: FactoryFn<I>,
	timeout: number?,
	hotStorage: Instance?,
	coldStorage: Instance?
): Pool<I, O>
	local self = setmetatable({}, Pool) :: InternalPool<I, O>

	timeout = timeout or 0
	if timeout < 0 then
		timeout = 0
	end

	self.active = true
	self.size = size
	self.timeout = timeout

	local hotBuffer = {} :: InstanceList<I>
	local coldBuffer = {} :: InstanceList<I>

	self._hotQueue = {
		head = 1,
		tail = 0,
		count = 0,
		buffer = hotBuffer,
		free = {},
	}

	self._coldQueue = {
		head = 1,
		tail = 0,
		count = 0,
		buffer = coldBuffer,
		free = {},
	}
	
	self._indexMap = {} :: IndexMap<I>

	self.hotSpot = hotStorage :: Instance?
	self.coldSpot = coldStorage :: Instance?
	self.connections = {} :: ConnectionMap<I>
	self.activeTimeouts = {} :: TimeoutMap<I>
	self.factoryFunction = factoryFunction

	task.spawn(function()
		while self.active do
			local currentTime = DateTime.now().UnixTimestamp

			-- Build list of objects to store to avoid modifying table during iteration
			local objectsToStore: InstanceList<I> = {}

			for object, timeoutTime in self.activeTimeouts do
				if currentTime >= timeoutTime then
					table.insert(objectsToStore, object)
				end
			end

			for _, object in objectsToStore do
				-- Check if object is still in hot queue before storing
				local info = self._indexMap[object]
				if info == nil then
					_removeTimeout(self, object)
					continue
				end

				if info.queue ~= "hot" then
					_removeTimeout(self, object)
					continue
				end

				-- Verify the object is actually at the expected location
				local queue = self._hotQueue
				if queue.buffer[info.index] ~= object then
					_removeTimeout(self, object)
					continue
				end

				_removeTimeout(self, object)
				self:store(object)
			end

			task.wait(1)
		end
	end)

	return self
end

function Pool.construct<I, O>(
	self: InternalPool<I, O>,
	constructFunction: ConstructFn<I, O>,
	constructOpts: O?
): I?
	constructOpts = constructOpts or nil

	local object: I?

	if _needConstruct(self) then
		object = self.factoryFunction()
	else
		object = _queueTake(self)
	end

	if constructOpts then
		constructFunction(object :: I, constructOpts)
	else
		constructFunction(object :: I, nil)
	end

	_enqueue(self, "hot", object :: I)
	_destroyListener(self, object :: I)
	_startTimeout(self, object :: I)

	local inst = object :: Instance
	if inst.Parent ~= self.hotSpot then
		inst.Parent = self.hotSpot
	end

	return object
end

function Pool.store<I, O>(self: InternalPool<I, O>, part: I): ()
	_removeTimeout(self, part :: I)

	local removed = _removeFromQueues(self, part :: I)

	-- Only enqueue to cold if we successfully removed it from a queue
	-- This prevents double-enqueuing if store() is called multiple times
	if removed then
		_enqueue(self, "cold", part :: I)

		local inst = part :: Instance
		inst.Parent = self.coldSpot
	end
end

function Pool.wipe<I, O>(self: InternalPool<I, O>, cleanupFunction: CleanupFn<I>): ()
	local hotBuffer = self._hotQueue.buffer
	for i = 1, self.size do
		local obj = hotBuffer[i]
		if obj ~= nil then
			cleanupFunction(obj :: I)
		end
	end

	local coldBuffer = self._coldQueue.buffer
	for i = 1, self.size do
		local obj = coldBuffer[i]
		if obj ~= nil then
			cleanupFunction(obj :: I)
		end
	end
end

function Pool.getActiveCount<I, O>(self: InternalPool<I, O>): number
	return self._hotQueue.count :: number
end

function Pool.getIdleCount<I, O>(self: InternalPool<I, O>): number
	return self._coldQueue.count :: number
end

return Pool
