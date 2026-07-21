# Pixel Art Game — Design Brief

## Governing Rules (Never Broken)

1. All work proceeds from a design brief created together. The design brief is the single source of truth for every asset, screen, and interaction.
2. The design brief must provide instructions of use, screen space/location descriptions, and pixel-by-pixel use descriptions for absolutely every detail.
3. Every graphical element generation must include a highly detailed prompt specifying pixel size, resolution, viewpoint (isometric or otherwise), and an explicit prohibition on text or grid overlays.
4. Alpha channel use must be stated when necessary. All colors must be pixel-perfect and named with hex values. Transparency is indicated by exact color `#FF00FF` only; all `#FF00FF` pixels represent fully transparent regions. No alpha channels, no white backgrounds for transparency.
5. Graphical elements are generated one at a time. Each generation cycle is independently prompted and described using the rules above. Final assets are produced by deterministic procedural/code-based pixel generation; AI-generated outputs are allowed only as style drafts and never as final shipped assets.

---

## Game Identity

**Title:** `Arcanum Clash`
**Genre:** 90s-style fantasy battle card game with animated combat resolution
**Perspective:** Top-down 2D board with 2.5D isometric card art
**Resolution Target:** 320×200 and 640×400 gameplay UI (authentic retro), cards rendered as crisp scaled sprites
**Art Style:** Early '90s dark-fantasy retro 3D-era pixel art in the spirit of early isometric dungeon titles — hard pixels, no antialiasing, gothic medieval fantasy
**Color Key Transparency:** `#FF00FF` / magenta used for every transparency mask; no per-pixel alpha in battle sprites
**Palette:** 32-color EGA-inspired dungeon palette with 16 reserved colors for UI chrome; creature sprites use 24-color subsets
**Fonts:** All in-game text rendered as bitmap font in UI layer only; battle animations contain zero text

---

## Game Concept: `Arcanum Clash`

### Overview
A two-player fantasy battle card game with a battlefield board and animated miniature-style clash vignettes. The design favors fast 90s arcade pacing: short turns, clear numbers, and visual payoff exactly when needed.

### Core Design Philosophy
- Two layers: the **board layer** showing straightforward game state, and the **battle layer** triggered only for attack resolution.
- **One animation style only**, reused across fights, with a cooldown so it feels like a power move, not mandatory slowdown.
- All truths are visible on the board: HP/ATK/DEF, Veinwell line, and phase timer.

---

## Rules of Play

### Players
- **2 players**, mirrored layout.
- **Legion Deck:** 40 cards.
- **Starting LP:** 20.
- **Starting hand:** 5 cards; **one mulligan** allowed to draw 4 and place 1 face-down **Sigil Ward**.

### Card Types
- **Creature** — ATK / DEF / HP, Exertion 1–3
- **Instant Spell** — resolves before attack steps
- **Trap** — facedown, triggers on condition
- **Terrain** — persistent 1-slot modifier per side

### Card Anatomy / Board Contract
- **Name** — top center bitmap font
- **Veinwell Cost** — top right
- **Type Line** — top left
- **Art Rect** — centered **128×128 px**
- **Power/Defense** — bottom numerals `ATK/DEF`
- **Exertion track** — bottom icons, max 3 per round
- **Ability Text** — bottom bitmap text block
- **Tier ring:** Gray=I / Green=II / Blue=III / Purple=IV / Orange=V / Red=VI
- **Hover outline:** `#FF00FF` blink

### Veinwell Flow
- Both sides share a global **Veinwell** that rises automatically each turn; no cards spend Veinwell to enter play. Costs are paid from Veinwell.
- Maximum Veinwell: **12 tokens**.
- **Cost rule:** a card’s Tier equals the number of Veinwell tokens it consumes when played.
- Excess Veinwell above 12 is lost; deficits prevent play.
- Terrain can increase income or reduce costs; replacing terrain costs **3 Veinwell tokens**.

### Turn Structure
Short 5-phase loop:

1. **Awaken** — return all exerted creatures; Veinwell +2 tokens
2. **Draw** — draw 1; if empty deck, lose 1 LP
3. **Deploy** — play Terrain if empty, then creatures/spells/traps
4. **Clash** — attacks, blocks, trap windows
5. **End** — bury destroyed creatures, check triggers

### Combat Flow
1. Declare attacker.
2. Opponent may declare **one blocker**.
3. Simultaneous damage: `remaining DEF HP damage`.
4. Both corpses enter Graveyard on a tie.
5. Clash Overlay may play depending on trigger/cooldown settings; otherwise skip.
6. After animation/cleanup, finalize LP.

### Screen Farming / Speed Rules
- Attack declared = enters cooldown for that card pair.
- Repeated attacks between same cards/clones reduce animation chance each time.
- Player may skip animation after first trigger to accelerate play.
- Phase timer defaults to **90 seconds**; auto-pass applies.

### Win Conditions
- Reduce opponent LP to 0.
- Opponent draws with 0 LP.
- **Dominion:** control 3 Terrain Objectives simultaneously, if using Tier IV/V terrain.

---

## Clash Overlay

### Trigger Policy
- Triggered ONLY at attack resolution, not on every action.
- Symmetric for both players; opponent view is rotated 180°.
- Cooldown by `(attacker_id, defender_id)` pair to avoid spam.

### Animation Spec
- **Frame budget:** 120 frames @ 30 fps = 4 seconds.
- **Overlay resolution:** 256×144 px centered on field; board chrome remains visible.
- **Sprite size:** 32×32 px tiles; heroes 48×48 px.
- **Parallax:** 2 layers inside overlay only; none on the board layer.
- **Transparency:** `#FF00FF` only; no alpha channels.

### Motion Style
- Three short clips only: **lunge/contact/recoil**, **raise/deflect/stagger**, **dissolve/bone-scatter/fade**.
- No branching text or story moments; purely motion-graphic combat beat.

---

## Keywords / Tooltip Contract
All keywords shown as a single tooltip line in bitmap font.

| Keyword | Definition |
|---------|------------|
| Ready | May act this turn |
| Exerted | Cannot act until Awaken |
| Barrier | Ignores first spell/damage per round |
| Flying | Blocks only by Flying/Tower |
| Mastery | Acts first in speed ties |
| Veil | Cannot be targeted by spells/traps |
| Sunder | Enters play with -1 enemy terrain modifier |
| Frenzy | On death, destroys one random Ready enemy |
| Guardian | Can redirect champion attack to self |

---

## Champion Archetypes
Each defines starting LP, opening Terrain, and one signature ability.

- **Knight:** +5 LP, Keep terrain, **Breaker** — lock one enemy Terrain at round start
- **Sorcerer:** -3 LP, Arcane Vein terrain, **Weaver** — spend 2 LP to cast an extra spell
- **Rogue:** 0 LP, Shadow Alley terrain, **Ambush** — one creature per match enters Ready
- **Cleric:** +8 LP, Sacred Glade terrain, **Aegis** — destroyed creatures can be returned at double Veinwell cost

### Champion Select UI
- Full-screen modal.
- Portrait previews at selection size **128×128 px** from **256×256 px** art.
- Hover plays a single short creature preview from that archetype.

---

## UI Specifications

### 320×200 Boot Screen
- Internal render: 320×200 → nearest-neighbor integer scale.
- Animated title portal, menu items at `160,160`, `160,176`, `160,192`.

### Match Setup: 640×400
- Deck selector: `0,0–255,399`
- Terrain selector: `384,0–639,240`
- Champion selector: `384,240–639,399`
- START button: `272,368`, `96×24` px

### In-Game HUD
- Top bar: `0,0–639,64`
- Hand strip: `0,540–639,599`, max 7 cards
- Central field: `0,64–639,479` = **640×416 px**
- Tile grid inside field: **16×16 px** tiles, snap-to-grid placement

### Card Drop Zones
- Integer-div snap to nearest tile center.
- Valid placement checked against terrain/count limits before drop accepts.

## Trait Interaction Tree

This is a compact reference you can hand to the implementation agent. It focuses on interaction, not lore.

- **Barrier > Spell/Sunder:** Barrier absorbs one incoming spell or -1 modifier.
- **Veil > Spell/Trap:** Veil negates targeting, but not area globals.
- **Flying > Ground Blockers:** Flying ignores ground blockers; only Flying/Tower may block.
- **Mastery > Speed Tie:** Mastery acts first when Speed matches.
- **Frenzy > Death:** On death, Frenzy checks once for a valid Ready enemy and destroys it.
- **Guardian > Champion Attacks:** Guardian can intercept an attack aimed at the champion.
- **Ready/Exerted phases:** Ready means attack/block allowed this turn; Exerted disables action until Awaken.

## Match Loop State Machine

A 6-state loop the agent can implement directly.

1. `Awaken` — reset Ready/Exerted, add Veinwell
2. `Draw` — draw one; 0 deck = -1 LP
3. `Deploy` — place terrain/creature/spell/trap
4. `Clash` — declare attacker → blocker/trap → animation gate → damage eval
5. `End` — burial, LP updates, AI/input pass
6. `WinCheck` — 0 LP, empty draw, or Dominion then loop or end match

## Animation Binding Matrix

Use this for coded triggers rather than broad rules.

| Trigger | Animation | Length |
|--------|-----------|--------|
| Melee attack | Clash clip | 120 frames |
| Block | Deflect clip | 120 frames |
| Death | Dissolve clip | 120 frames |
| Champion ability | 1-frame flash freeze | 6 frames |

## Modding / Data

Card definition JSON schema:

```json
{
  "id": "C-0042",
  "name": "",
  "tier": 2,
  "type": "creature",
  "atk": 3,
  "def": 2,
  "hp": 14,
  "speed": 2,
  "abilities": [],
  "artRect": "128x128",
  "palette": "warrior_crimson"
}
```

- Every `palette` references a named 24-color EGA subset used by clash overlay sprites.
- Community content must validate against Governing Rules #2–#4 before inclusion.

## Canonical Asset Tooling

- Deterministic pixel assets are generated with `tools/pixel_art_engine.py` under `C:\Users\kevin\game-studio`.
- The engine uses exact palette-locked `#FF00FF` transparency and supports `tile`, `rect`, and `pixel` commands.
- AI-generated outputs remain style-draft only and must never ship as final assets.
