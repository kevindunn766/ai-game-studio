extends RefCounted

# Shared combat constants for the enemy/weapon system. No class_name (headless
# safe -- referenced via preload const, see the docs/godot notes in CLAUDE.md).
#
# Collision layers use the same raw-int bit convention the rest of this project
# already uses (pickups = 2, environment hazard = 4). Combat adds three more bits
# that never overlap those two, so combat detection is fully independent of the
# existing pickup/hazard wiring:
#   LAYER_ENEMY       (8)  -- an enemy's hurtbox. Detected BY player shots and BY
#                            the ship's CombatDetector (contact damage).
#   LAYER_PLAYER_SHOT (16) -- a player projectile (masks LAYER_ENEMY).
#   LAYER_ENEMY_SHOT  (32) -- an enemy projectile (detected by the ship's
#                            CombatDetector, which masks 8|32).
const LAYER_ENEMY: int = 8
const LAYER_PLAYER_SHOT: int = 16
const LAYER_ENEMY_SHOT: int = 32

# Group names used for type dispatch on Area3D overlaps (cheaper + clearer than
# reflecting on the collision layer at the callsite).
const GROUP_ENEMY_HURTBOX := "enemy_hurtbox"
const GROUP_ENEMY_SHOT := "enemy_shot"
const GROUP_PLAYER_SHOT := "player_shot"

const TEAM_PLAYER: int = 0
const TEAM_ENEMY: int = 1

# Running count of enemies the player has destroyed this level. LevelDirector
# resets it to 0 when a level (re)builds and reads it at the win screen so the
# beauty shot can show a real "ENEMIES DOWNED" stat. Static so enemy_base can
# bump it without a reference to the director.
static var player_kills: int = 0
# Current sector (1-based), set by LevelDirector each level. Drives progression
# scaling of dropped part stat values (see stat_util / enemy_spawner).
static var sector: int = 1
