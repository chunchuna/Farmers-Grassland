---
description: Create a new multiplayer map scene with all standard systems (environment, lighting, game manager, weather, chat, debug panel, spawn point)
---

# New Map Scene Workflow

Use this workflow when you need to create a new map/level scene that includes all the standard multiplayer systems.

## Steps

1. **Determine the map name and assets**
   - Ask the user for the map name (e.g., `forest`, `city`, `house`)
   - Identify any 3D model assets (.fbx, .gltf, .glb) to include
   - Note the asset paths under `res://Assest/`

2. **Create the scene file** at `res://scenes/<map_name>_map.tscn`
   
   The scene MUST include these standard nodes:
   ```
   <MapName> (Node3D)               ← Root node
   ├── WorldEnvironment              ← ExtResource env_day.tres
   ├── DirectionalLight3D            ← Main sun light, shadow_enabled=true
   ├── FillLight (DirectionalLight3D)← Ambient fill light, lower energy
   ├── <Your 3D assets here>         ← The map's visual models
   ├── <Collision bodies>            ← StaticBody3D + CollisionShape3D for ground/walls
   ├── SpawnPoint (Marker3D)         ← Where players spawn, Y should be above ground
   ├── GameManager (Node)            ← script: game_manager.gd
   │   └── SpawnContainer (Node)     ← Empty, players spawned here at runtime
   ├── WeatherSystem (Node3D)        ← script: weather_system.gd
   ├── DebugPanel (CanvasLayer)      ← script: debug_panel.gd
   └── ChatSystem (CanvasLayer)      ← script: chat_system.gd
   ```

3. **Required ext_resources** (copy UIDs from existing scenes):
   ```
   Environment:    uid://cfg6vrqq7ksno  → res://resources/env_day.tres
   GameManager:    uid://d1m7g5qnsqxhi  → res://scripts/game_manager.gd
   WeatherSystem:  uid://bhw2kv3shqrch  → res://scripts/weather_system.gd
   DebugPanel:     uid://dhetcbdynsu7f  → res://scripts/debug_panel.gd
   ChatSystem:     uid://c8thgl1c4sdsd  → res://scripts/chat_system.gd
   ```

4. **Ensure collision** — The map needs at least a ground collision:
   - If the model has a separate collider file (like `House_Colliders.fbx`), instance it
   - Otherwise, add a `StaticBody3D` with a `BoxShape3D` as a floor plane
   - If using Terrain3D, set `collision_mode = 2`

5. **Set SpawnPoint position** — Place it where players should appear:
   - Y should be 1-2 meters above the ground/floor
   - Avoid spawning inside walls

6. **DirectionalLight3D settings** (standard sun):
   ```
   light_color = Color(1, 0.95, 0.85, 1)
   light_energy = 0.7
   light_angular_distance = 1.0
   shadow_enabled = true
   shadow_bias = 0.03
   ```

7. **FillLight settings** (ambient bounce):
   ```
   light_color = Color(0.6, 0.7, 0.9, 1)
   light_energy = 0.3
   ```

8. **Register the map in lobby_ui.gd**
   - Add an entry to the `MAPS` array at the top of `res://scripts/lobby_ui.gd`:
   ```gdscript
   const MAPS := [
       {"name": "Grassland", "scene": "res://scenes/grassland.tscn"},
       {"name": "House", "scene": "res://scenes/house_map.tscn"},
       {"name": "NewMap", "scene": "res://scenes/new_map.tscn"},  # ← add here
   ]
   ```

9. **Test the scene**
   - Open Godot, select the new scene, run it
   - Verify: player spawns correctly, can walk on ground, flashlight works, chat works, weather works
   - If assets are too large/small, adjust the root transform scale

## Notes
- The `env_day.tres` and `env_night.tres` are shared across all maps
- Weather system auto-finds WorldEnvironment and DirectionalLight3D in the scene tree
- Game manager handles player spawning, multiplayer sync, and state snapshots automatically
- Always test both single-player (just run scene) and multiplayer (via lobby)
