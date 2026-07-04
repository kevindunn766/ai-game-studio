# Arcadia Clash — Pixel Card Battle Game
## Design Brief v1.0
### Hotbed Games

---

## Concept

Arcadia Clash is a pixel art card battle game blending **Magic the Gathering** deck depth with **Clash Royale** lane tactics, **Battle Chess** animated combat, and **Slay the Spire** progression. When creatures clash, they "come to life" into mini pixel-art battle sequences before returning to the board state.

---

## Core Loop

1. Build a deck (40 cards)
2. Fight through overworld encounters (Slay the Spire-style map)
3. In combat: place creatures across 3 lanes, cast spells, defeat opponent
4. Animated pixel battles when creatures engage
5. Earn rewards for deck-building between encounters

---

## Influences

| Source | Borrowed |
|---|---|
| **Magic the Gathering** | Color identity (5), deck building, creature/artifact/enchantment/instant/sorcery types, loyalty counters |
| **Clash Royale** | 3-lane battlefield, towers per lane, real-time feel (turn-based but brisk), elixir pace |
| **Battle Chess** | Animated combat — when two creatures clash, zoom into a 10-second pixel battle scene |
| **Slay the Spire** | Branching overworld map, event encounters, boss fights, relic rewards |
| **Pokemon TCG** | Simplified energy: one currency "Crystal" pool, no color-lock |
| **Hearthstone** | Hero power, weapon system, secret cards |

---

## Unique Twist

**The Clash System:** When a creature attacks an opposing creature, the camera zooms into a 320x240 pixel-art battle arena. The two creatures animate and fight for 5-10 seconds, with the winner determined by stats + a small randomness factor + player interaction prompts ("Hero Power" tap). Results are applied back to the board state.

---

## Card Types

| Type | Role | Count in Deck | Battle Behavior |
|---|---|---|---|
| **Creature** | Lane fighters with attack/defense | 20-30 | Clash with other creatures, attack towers |
| **Spell** | One-shot effects | 8-15 | Instant or turn-delayed; can buff, damage, portal-shift |
| **Terrain** | Lane modifiers | 4-8 | Permanent lane effect until destroyed |
| **Secret** | Face-down traps | 0-4 | Triggered by opponent actions |
| **Relic** | Passive buff | 2-4 | Never played; immediate effect on draw |
| **Hero Power** | Special action | 1 | Defined by Hero choice; usable every 3 turns |

---

## Battle System

### Setup
- 3 lanes, each with:
  - 3 friendly creature slots per lane
  - 3 enemy creature slots
  - 1 friendly tower (100 HP)
  - 1 enemy tower (100 HP)
- 1 King tower behind each side (200 HP)
- Hero Power button

### Turn Flow
1. Draw 1 card
2. Gain 3 Crystal
3. Place creatures in empty lanes/slots (costs Crystal)
4. Order creatures to attack lane, tower, or specific enemy creature
5. Resolve all attacks → if attacker meets defender, trigger **CLASH**
6. Cast Spells / activate Hero Power
7. End turn → enemy repeats

### Clash Resolution (Battle Chess Style)
- Camera focuses on battlefield cell where clash occurred
- Two creatures enter a 320x240 pixel combat ring
- Each creature has an idle animation + 2-3 attack animations
- Animation plays for 5-8 seconds
- Deterministic: creature stats decide winner, but random +-10% swing
- On certain cards: player gets a "Hero Strike" timing prompt tap during the animation for bonus
- Winner returns to board state with -1 defense if surviving
- Loser destroyed, summoned to discard

---

## Hero Classes

| Hero | Hero Power | Archetype |
|---|---|---|
| **Flame Knight** | Flame Burst - deal 2 damage to one lane | Aggro |
| **Crystal Mage** | Essence Surge - gain 2 extra Crystal this turn | Midrange |
| **Shadow Rogue** | Shadow Strike - silently destroy a Secret | Control |
| **Forest Warden** | Heal Tower - restore 15 HP to any tower | Defensive |
| **Void Walker** | Portal Shift - move your creatures between lanes | Swarm |

---

## Deck Building Rules

- Minimum: 40 cards, Maximum: 60 cards
- Max copies of a card: 3
- Must choose 1 Hero (determines Hero Power)
- Deck color identity: up to 2 colors per deck
- Starter decks: pre-built per Hero, 40 cards each

---

## Progression (Overworld Map)

- Branching node map (like Slay the Spire)
- 5 acts per region
- Each node is either:
  - **Battle** - normal fight
  - **Elite** - harder fight, better reward
  - **Rest** - heal towers, upgrade relics
  - **Shop** - buy new cards
  - **Treasure** - relic, bonus card, or gold
  - **Boss** - acts end with boss fight
- Rare events: "Mystic Portal" - add a wildcard card to deck; "Crystal Forge" - upgrade a card to golden pixel version

---

## Meta Progression

- **Gold**: earned after each battle (quantity based on performance)
- **Relics**: permanent passive buffs (carry across all runs)
- **Gold Pixel Cards**: cosmetic golden versions of cards, permanently unlocked for collection
- **Hero portraits**: unlock new Hero classes after beating bosses

---

## Monetization

- **Free-to-play**
- **No loot boxes**
- Cosmetic golden pixel card skins purchase
- Ad-supported optional "double gold" reward after battle
- No pay-to-win

---

## Pixel Art Style

- 320x240 battle ring resolution for clash animations
- Base UI/cards: 16-bit inspired, high-contrast pixel art
- Battle animations: 8-10 frame sprite sheets, 60fps playback
- Lane battlefield: isometric perspective, grid-based
- Color palette: vibrant but limited — 16 base colors, 4 per card

---

## Asset Architecture (For Automated Pipeline)

All pixel art components follow strict naming so the build pipeline knows where to place them.

### Folder Structure

```
snake-3d/
  assets/
    cards/
      hero_powers/
      creatures/
      spells/
      terrain/
      secrets/
      relics/
    animations/
      clashes/
        flame_knight_clash/
        crystal_mage_clash/
        shadow_rogue_clash/
        forest_warden_clash/
        void_walker_clash/
      idle/
      attack/
      death/
      hero_power/
    ui/
      card_frames/
        by_color/
        by_rarity/
      battle_ring/
      hero_select/
      overworld/
      store/
    terrain/
      lanes/
      towers/
      battlefield/
    effects/
      crystal_explosion/
      portal_shift/
      heal_beam/
    characters/
      heroes/
      npcs/
      monsters/
```

### Naming Convention

Format: `{type}_{subtype}_{name/variant}_{direction}_{state}_{frame}.png`

**Card Art:**
- `creature_goblin_001_idle_front_0001.png`
- `creature_dragon_idle_breath_0001.png`
- `spell_fireball_cast_0001.png`
- `hero_power_flame_burst_0001.png`
- `terrain_void_rune_ambient_0001.png`

**Animation Sheets:**
- `clash_knight_slash_attack_0001.png` through `clash_knight_slash_attack_0010.png`
- `idle_wizard_float_0001.png` through `idle_wizard_float_0004.png`

**UI Elements:**
- `card_frame_creature_common.png`
- `card_frame_spell_rare.png`
- `card_back_hero_flame_knight.png`
- `battle_ring_neon_lane3.png`
- `crystal_counter_full.png`

### Asset Manifest

```yaml
cards:
  creatures:
    - id: goblin_01
      name: Goblin Shaman
      colors: [green, red]
      total_art_frames: 8
      sheet_size: [256, 32]  # 8 frames across, 32px tall
      clash_animation: clash_goblin_wild_attack
    - id: crystal_sprite
      name: Crystal Sprite
      colors: [cyan, white]
      total_art_frames: 6
      clash_animation: clash_sprite_beam

  hero_powers:
    - id: flame_burst
      frames: 12
      sheet_size: [384, 32]

  spells:
    - id: fireball
      frames: 10
      sheet_size: [320, 32]

animations:
  clashes:
    - hero: flame_knight
      move: slash
      frames: 10
      resolution: [320, 240]

ui:
  card_frames:
    - type: creature
      rarity: common
      width: 200
      height: 280
    - type: creature
      rarity: rare
      width: 200
      height: 280
```

---

## Quick Reference for Art Generator

| Asset | Size | Quantity | Priority |
|---|---|---|---|
| Hero select portraits | 128x128 | 5 | P0 |
| Card back (per hero) | 200x280 | 5 | P0 |
| Card frame overlay | 200x280 | 5 rarities | P0 |
| Creature idle | 64x64 | first 10 creatures | P1 |
| Spell effect | 320x32 | 8 spells | P1 |
| Hero power effect | 320x32 | 5 powers | P1 |
| Clash background | 320x240 | 5 lane themes | P1 |
| Tower sprite | 96x128 | 2 (friendly/enemy) | P2 |
| Lane floor tiles | 64x64 | 3 lane types | P2 |
| Hero idle portrait | 128x128 | 5 | P0 |
| Overworld nodes | 64x64 | 6 node types | P2 |
| Crystal counter | 32x32 | 3 states | P2 |

P0 = must ship at launch
P1 = core gameplay
P2 = polish, can iterate post-launch

---

## Splash / First Screen (LOCKED)

- The **splash screen is the first thing the player sees**, before title/load.
- Source image: `assets/ui/splash/splash_1080x1920.png` (portrait 1080x1920) and `splash_1920x1080.png` (landscape fallback).
- Behavior: display full-bleed for `SPLASH_DURATION` seconds, then transition to title screen.
- No buttons or interactivity on splash — it is purely atmospheric branding.
- Sound: plays a short 1-2 second chiptune fanfare sting during splash.

## Verification

For Fable/Claude Code to confirm before committing:
1. All P0 assets are present at their expected sizes with correct naming convention
2. Master sprite sheets verify correct row/column packing
3. No PNG has embedded non-pixel alpha artifacts
4. Run check_assets.py (included in repo root)

