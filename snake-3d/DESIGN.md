# Snake 3D — Minimal Hyper-Casual Game

## Aesthetic
- Low-poly neon on dark background
- Snake segments: small glowing colored cubes
- Food: pulsing bright gem/cube
- Floor: subtle dark grid plane
- Minimal UI: score top-right, game-over prompt only

## Mechanics (LOCKED - do NOT add more)
1. Grid-based movement on XZ plane
2. 4-directional input: WASD or arrow keys
3. Wall = instant death
4. Eating food grows snake by 1, increases score
5. Speed increases slightly every 5 food
6. Game over screen: show score + restart prompt
7. High score persisted via config file
8. Structural twist: paired portal gates. A rare pair of linked gates
   spawns near the snake; stepping onto either one instantly teleports
   the whole snake (every segment, rigidly) to the other, letting a run
   cut across the map or escape a tight obstacle pocket.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- Scripts: `snake.gd`, `food.gd`, `game_manager.gd`
- Use MeshLibrary or BoxMesh for visuals — NO external art imports
- Use StandardMaterial3D with emission for glow
- Colors must have alpha in Color() calls: `Color(r,g,b,a)`
- Godot 4.7 compatible
- Build must run headless for APK export later

## What NOT to do
- NO power-ups
- NO menus
- NO sounds (yet)
- NO particle effects (yet)
- NO multiplayer
- NO in-app purchases

## Verification
Project must open in Godot 4.7 without errors. Press F5 to run and playtest.
