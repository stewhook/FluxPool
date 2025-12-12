# stewhook — Flux
```sql
__/\\\\\\\\\\\\\\\__/\\\______________/\\\________/\\\__/\\\_______/\\\_        
 _\/\\\///////////__\/\\\_____________\/\\\_______\/\\\_\///\\\___/\\\/__       
  _\/\\\_____________\/\\\_____________\/\\\_______\/\\\___\///\\\\\\/____      
   _\/\\\\\\\\\\\_____\/\\\_____________\/\\\_______\/\\\_____\//\\\\______     
    _\/\\\///////______\/\\\_____________\/\\\_______\/\\\______\/\\\\______    
     _\/\\\_____________\/\\\_____________\/\\\_______\/\\\______/\\\\\\_____   
      _\/\\\_____________\/\\\_____________\//\\\______/\\\_____/\\\////\\\___  
       _\/\\\_____________\/\\\\\\\\\\\\\\\__\///\\\\\\\\\/____/\\\/___\///\\\_ 
        _\///______________\///////////////_____\/////////_____\///_______\///__
```
Flux is a fast, modular, and scalable instance pooling framework that handles all back-end logic required to create an efficient instance pool while giving you the flexibility to create & recycle objects with custom (and potentially dynamic) logic / data.

## ❔ How does it work?
Flux manages your instances across two internal pools: Hot Storage (active & in use), and Cold Storage (idle & stored away).
When creating an instance, Flux will first check to see if the pool is at capacity.

Flux (by default) operates using an O(1) queue datastructure. Recycling the oldest instances, prioritizing cold state over hot state. This results in an extremely fast pooling framework that maintains speed regardless of pool size.
#### If the object pool isn't at capacity, Flux will:
1. Create an instance from scratch using your Factory Function.
2. Apply the Construction Function to the created instance.
3. Add this instance to the pool.
#### If the object pool is at capacity, Flux will:
1. Check Cold Storage and retrieve the oldest instance.
2. If Cold Storage is empty it, retrieve the oldest instance from Hot Storage.
3. Apply the Construction Function to the retrieved instance.
4. Cycle the instance through the pool.

## 📖 API Reference
### Public Fields (Config)
`pool.size : number`\
`pool.timeout : number`\
`pool.hotSpot : Instance`\
`pool.coldSpot : Instance`\
`pool.factoryFunction : () -> Instance`

### Public Methods
`Flux.new(config?) -> pool`\
`pool:construct(constructFn, opts) -> instance`\
`pool:store(instance)`\
`pool:destroy(instance)`\
`pool:wipe()`\
`pool:getActiveCount() -> number`\
`pool:getIdleCount() -> number`

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
pool.hotSpot = Workspace -- Where instances go when created.
pool.coldSpot = ReplicatedStorage -- Where instances go when stored.
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
	-- Expected Options
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

## ⚙️ Installation
### Install from Roblox
[Download the model from the Roblox library.](https://create.roblox.com/store/asset/120278572872003/Flux)
### Install from Wally
```
flux = "stewhook/flux@1.2.0"
```
[Or download from Wally's website.](https://wally.run/package/stewhook/flux?version=1.2.0)