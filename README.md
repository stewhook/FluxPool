# stewhook — Flux
Flux is a fast, modular, and scalable instance pooling framework that handles all back-end logic required to create an efficient instance pool while giving you the flexibility to create & recycle objects with custom (and potentially dynamic) logic / data.

## ❔ How does it work?
Flux manages your instances across two internal pools: Hot Storage (active & in use), and Cold Storage (idle & stored away).
When creating an instance, Flux will first check to see if the pool is at capacity.
#### If the object pool isn't at capacity, Flux will:
1. Create an instance from scratch using your Factory Function.
2. Apply the Construction Function to the created instance.
3. Add this instance to the pool.
#### If the object pool is at capacity, Flux will:
1. Check Cold Storage and retrieve the oldest instance.
2. If Cold Storage is empty it, retrieve the oldest instance from Hot Storage.
3. Apply the Construction Function to the retrieved instance.
4. Cycle the instance through the pool.

This results in a fast, controlled, and low-overhead instance lifecycle that avoids expensive creation and destruction methods while still giving you full control over how instances are created, reused, and stored.

## ⚙️ Installation
### Install from Roblox
You can download the model from Roblox here.
### Install from Wally
Wally install logic etc etc

## 👀 Usage
### Importing Flux
```luau
local Flux = require(ReplicatedStorage.Flux)
```
### Creating & Configuring a Pool
Building the pool foundation.
```luau
local pool = Flux.new()
pool.size = 100 -- Max instances in the pool.
pool._hotSpot = Workspace -- Where instances go when created.
pool._coldSpot = ReplicatedStorage -- Where instances go when stored.
pool.timeout = 10 -- How long instances exist before being automatically cleaned (set this to 0 for no timeout)
pool.factoryFunction = function()
  local block = Instance.new("Part")
  block.Size = Vector3.new(2, 2, 2)
  block.CollisionGroup = "Blocks"
  return block
end -- The function that handles object creation from scratch.
```
### Defining Pool Behaviors
The constructFunction serves as the customizable creation function that handles instance setup. It can take an optional opts table ("string" : any Roblox value). The opts table allows for the passing of dynamic and custom data to be used within the construction function such as colors, players, etc.
```luau
local function constructFunction(instance: Part, opts)
  -- opts = {
  --	color = any Brickcolor
  -- }
  local fountainStrength = 150
  local fountainWidth = 10.0
  local fountainAngle = Vector3.new((math.random()*2-1)*fountainWidth, fountainStrength, (math.random()*2-1)*fountainWidth)
  instance.BrickColor = opts.color
  instance.Position = fountainFolder.LaunchPoint.Position
  instance.AssemblyLinearVelocity = fountainAngle
end
```
### Creating & Recycling Instances
Wherever you would consider running Instance.new() or :Clone() replace it with pool:construct(). This allows you the same functionality of creating an instance from scratch using your factory function (expensive), while giving you the ability to recycle old instances depending on pool size (cheap).
```luau
local fountainActive = false

local opts = {
  color = BrickColor.Blue()
}
	
while fountainActive do
  pool:construct(
    constructFunction,
    opts
  )
  task.wait(.01)
end
```
### Manual Storing of Instances
In the event you'd like to manually store an instance into cold storage. Run pool:store(instance). This provides all background cleanup while storing the instance into cold storage. Cold storage items take priority in being recycled compared to hot storage items.
```luau
-- Example
pool:store(instance)
```
