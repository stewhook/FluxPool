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
