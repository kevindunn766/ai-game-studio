# RELIQUARY — Pixel-Perfect Production Bible v0.1
**Art style:** early PlayStation 1, Castlevania: Symphony of the Night inspired. Dark gothic cathedral aesthetic. Rich shading, atmospheric lighting, detailed sprites.
**Rule:** AI generates texture-only base assets. All text, numerals, HUD readouts, and grid overlays are rendered by the coding agent at runtime using compositing specs below.

---

## 1. SYSTEM RULES

### 1.1 Alpha / Transparency Convention
- **No alpha channel** allowed in any exported asset.
- **Color-key transparency:** `#FF00FF` (magenta) is reserved as runtime transparency.
- **Constraint:** `#FF00FF` MUST NOT appear as an intentional visible color in any asset.
- Coding agent replaces every `#FF00FF` pixel with transparency during import.

### 1.2 Coordinate System
- Origin: top-left `(0,0)`
- All positions: `(x, y)` in pixels
- All sizes: `width × height` in pixels
- Base render resolution: **320×224** (PS1 SOTN-style)

---

## 2. FULL SCREEN LAYOUT — 320×224

### 2.1 Board Area
- **Grid:** 9×9 cathedral floor tiles
- **Tile size:** 32×32 px
- **Grid origin:** `(16, 16)`
- **Grid total:** `288×288` px
- **Note:** 9×9×32 = 288, which exceeds 224 height. Board is **scrollable** or uses **2-layer view**: upper 224 shows rows 0-6, lower 224 shows rows 3-8.
- **Preferred:** fixed 224-height viewport showing **7 rows × 9 columns** = `288×224`. Bottom 2 rows accessed by scrolling or auto-follow during movement phases.
- **Tile border spacing:** 0 px (tiles abut directly)
- **Tile content:** opaque terrain texture, no baked grid lines

### 2.2 HUD — Top Bar
- **Position:** `(0, 0)` to `(320, 24)`
- **Height:** 24 px
- **Background:** opaque dark stone texture
- **Left side (Player 1):**
  - **Faith bar:** `(8, 4)` width `80`, height `16`
    - Fill color: `#C41E3A` (deep red)
    - Background: `#1A1A1A`
  - **Candlelight readout:** `(96, 4)` width `48`, height `16`
    - Icon: `(96, 4)` size `16×16`
    - Number field: `(116, 4)` size `28×16`
  - **Piety readout:** `(150, 4)` width `40`, height `16`
- **Center:**
  - **Turn indicator:** `(140, 4)` size `40×16`
- **Right side (Player 2):**
  - **Faith bar:** `(232, 4)` width `80`, height `16`
  - **Candlelight readout:** `(176, 4)` width `48`, height `16`
  - **Piety readout:** `(130, 4)` width `40`, height `16`

### 2.3 HUD — Bottom Bar
- **Position:** `(0, 200)` to `(320, 224)`
- **Height:** 24 px
- **Background:** opaque dark stone texture
- **Hand slots:** 5 slots, each `(16 + i*60, 204)` size `56×20`
  - Slot background: `#2A2A2A` with `#FF00FF` key for card cutout area
  - Card art area: `(20 + i*60, 204)` size `48×16`
- **End Turn button area:** `(280, 204)` size `36×20`

### 2.4 Side Panels
- **Left panel (Player 1 info):** `(0, 24)` to `(16, 200)` width `16`
- **Right panel (Player 2 info):** `(304, 24)` to `(320, 200)` width `16`
- Both: opaque dark stone texture, no transparency

### 2.5 Battle Zoom Overlay
- **Full-screen dim:** `(0, 0)` to `(320, 224)` opaque black `#000000` at 60% alpha
  - **Note:** 60% alpha implemented as dithered pattern by coder, NOT as semi-transparent PNG
- **Center stage:** `(48, 32)` to `(272, 192)` size `224×160`
  - Background: cathedral stone texture
- **Attacker sprite area:** `(64, 64)` size `64×64`
- **Defender sprite area:** `(192, 64)` size `64×64`
- **VS text region:** `(152, 88)` size `16×16`
- **Result text region:** `(128, 144)` size `64×16`

---

## 3. TEXT RENDERING MAP (Coder-Composited)

All text is rendered by the coding agent using `font_ascii@1x.png` at runtime. Coordinates specify **upper-left corner** of text block.

| UI Element | Text Region | Sample Content | Font Size |
|------------|-------------|----------------|-----------|
| P1 Faith bar | `(10, 6)` | `12/15` | 8px |
| P1 Candlelight | `(118, 6)` | `7` | 8px |
| P1 Piety | `(154, 6)` | `5` | 8px |
| Turn indicator | `(146, 6)` | `P1` | 8px |
| P2 Faith bar | `(234, 6)` | `12/15` | 8px |
| P2 Candlelight | `(186, 6)` | `7` | 8px |
| P2 Piety | `(134, 6)` | `5` | 8px |
| Hand slot 1 | `(24, 206)` | Card name | 8px |
| Hand slot 2 | `(84, 206)` | Card name | 8px |
| Hand slot 3 | `(144, 206)` | Card name | 8px |
| Hand slot 4 | `(204, 206)` | Card name | 8px |
| Hand slot 5 | `(264, 206)` | Card name | 8px |
| End Turn | `(282, 206)` | `END` | 8px |
| Battle result | `(132, 146)` | `P1 WINS` | 8px |
| Relic name (battle) | `(96, 48)` | `Relic Name` | 8px |
| Faith delta | `(152, 112)` | `-3` | 8px |

**Note:** No text is baked into any pixel art asset. All strings above are rendered by the coder.

---

## 4. BATTLE CHESS CINEMATIC LAYOUT

Zoom-in occurs when units duel. Entire screen redraws with layered assets:

1. **Background layer:** `bg_cathedral_choir@1x.png` — `320×224`, opaque stone architecture
2. **Midground:** attacker/defender sprites at `64,64` and `192,64`
3. **Foreground VFX:** particle layer at `0,0` to `320,224`
4. **Text overlay:** rendered by coder per Section 3 map

**Animation sequence (frame counts):**
- Frame 0-4: zoom from board to close-up
- Frame 5-12: attack/reveal animation
- Frame 13-18: damage flash + displacement
- Frame 19-24: zoom back to board

**Trigger:** when active relic moves onto enemy relic square.

---

## 5. ASSET LIST — EXACT SPECIFICATIONS

### 5.1 Tiles (9×9 grid, 32×32 each)
- `tile_sanctuary_floor@1x.png` — `32×32`, opaque stone
- `tile_sanctuary_floor_cracked@1x.png` — `32×32`, opaque cracked stone
- `tile_altar@1x.png` — `32×32`, opaque raised altar
- `tile_confessional@1x.png` — `32×32`, opaque booth
- `tile_station_cross@1x.png` — `32×32`, opaque station marker
- `tile_pew_left@1x.png` — `32×32`, opaque pew side
- `tile_pew_right@1x.png` — `32×32`, opaque pew side
- `tile_candle_glow@1x.png` — `32×32`, opaque floor with candle light pool
- `tile_stained_glass@1x.png` — `32×32`, opaque colored glass projection

### 5.2 Relic Sprites (Base Form)
- `relic_statue@1x.png` — `32×32`, opaque marble statue
- `relic_armor@1x.png` — `32×32`, opaque plate armor
- `relic_book@1x.png` — `32×32`, opaque holy book
- `relic_chalice@1x.png` — `32×32`, opaque golden chalice
- `relic_box@1x.png` — `32×32`, opaque reliquary box
- `relic_crozier@1x.png` — `32×32`, opaque bishop’s crozier

### 5.3 Relic Sprites (Battle Zoom — 64×64)
- `relic_statue_battle@1x.png` — `64×64`, opaque close-up
- `relic_armor_battle@1x.png` — `64×64`, opaque close-up
- `relic_book_battle@1x.png` — `64×64`, opaque close-up
- `relic_chalice_battle@1x.png` — `64×64`, opaque close-up
- `relic_box_battle@1x.png` — `64×64`, opaque close-up
- `relic_crozier_battle@1x.png` — `64×64`, opaque close-up

### 5.4 Card Assets
- **Card frame:** `card_frame@1x.png` — `152×212`, opaque gothic border, center transparent via `#FF00FF`
- **Card art backing:** `card_art_backing@1x.png` — `120×88`, opaque texture, fits inside frame
- **Element tint overlays** (border-only, center transparent via `#FF00FF`):
  - `tint_benedictine@1x.png` — `152×212`
  - `tint_franciscan@1x.png` — `152×212`
  - `tint_dominican@1x.png` — `152×212`
  - `tint_cistercian@1x.png` — `152×212`

### 5.5 HUD & UI Panels
- **Top bar background:** `hud_top@1x.png` — `320×24`, opaque stone
- **Bottom bar background:** `hud_bottom@1x.png` — `320×24`, opaque stone
- **Left panel:** `hud_side_left@1x.png` — `16×176`, opaque stone
- **Right panel:** `hud_side_right@1x.png` — `16×176`, opaque stone
- **Faith bar fill:** `bar_faith_fill@1x.png` — `80×16`, opaque red
- **Faith bar bg:** `bar_faith_bg@1x.png` — `80×16`, opaque dark
- **Candlelight icon:** `icon_candle@1x.png` — `16×16`, opaque flame
- **Hand slot bg:** `hand_slot@1x.png` — `56×20`, opaque dark
- **End turn button:** `button_end_turn@1x.png` — `36×20`, opaque stone
- **Battle stage bg:** `bg_cathedral_choir@1x.png` — `320×224`, opaque stone architecture

### 5.6 VFX Spritesheets (Row-based animation)
- **VFX sheet:** `vfx_reliquary@1x.png` — `256×128`, 2 rows × 8 cols
  - Row 0: Consecration flash, Penance reveal, Damage number float, Displacement poof
  - Row 1: Candlelight spark, Thread bind, Unravel dissolve, Icon collect

### 5.7 Cursor & Selection
- `cursor_select@1x.png` — `32×32`, opaque gothic crosshair, center transparent via `#FF00FF`
- `cursor_target@1x.png` — `32×32`, opaque target reticle, center transparent via `#FF00FF`

### 5.8 Portrait Assets (for card faces and duel UI)
- **Portrait frame:** `portrait_frame@1x.png` — `64×64`, opaque gothic frame, center transparent via `#FF00FF`
- **Relic portraits:**
  - `portrait_statue@1x.png` — `64×64`, opaque
  - `portrait_armor@1x.png` — `64×64`, opaque
  - `portrait_book@1x.png` — `64×64`, opaque
  - `portrait_chalice@1x.png` — `64×64`, opaque
  - `portrait_box@1x.png` — `64×64`, opaque
  - `portrait_crozier@1x.png` — `64×64`, opaque`

### 5.9 Font Strip
- `font_ascii@1x.png` — `128×16`, opaque pixel font atlas, no baked text strings

---

## 6. ASSET FOLDER STRUCTURE
```
assets/
  export/
    tiles/
      tile_sanctuary_floor@1x.png
      tile_sanctuary_floor_cracked@1x.png
      tile_altar@1x.png
      tile_confessional@1x.png
      tile_station_cross@1x.png
      tile_pew_left@1x.png
      tile_pew_right@1x.png
      tile_candle_glow@1x.png
      tile_stained_glass@1x.png
    spritesheets/
      vfx_reliquary@1x.png
    vfx/
      (individual VFX frames exported from spritesheet row slices)
    ui/
      hud_top@1x.png
      hud_bottom@1x.png
      hud_side_left@1x.png
      hud_side_right@1x.png
      bar_faith_fill@1x.png
      bar_faith_bg@1x.png
      icon_candle@1x.png
      hand_slot@1x.png
      button_end_turn@1x.png
      bg_cathedral_choir@1x.png
      card_frame@1x.png
      card_art_backing@1x.png
      tint_benedictine@1x.png
      tint_franciscan@1x.png
      tint_dominican@1x.png
      tint_cistercian@1x.png
      portrait_frame@1x.png
      portrait_statue@1x.png
      portrait_armor@1x.png
      portrait_book@1x.png
      portrait_chalice@1x.png
      portrait_box@1x.png
      portrait_crozier@1x.png
      cursor_select@1x.png
      cursor_target@1x.png
    sprites/
      relic_statue@1x.png
      relic_armor@1x.png
      relic_book@1x.png
      relic_chalice@1x.png
      relic_box@1x.png
      relic_crozier@1x.png
      relic_statue_battle@1x.png
      relic_armor_battle@1x.png
      relic_book_battle@1x.png
      relic_chalice_battle@1x.png
      relic_box_battle@1x.png
      relic_crozier_battle@1x.png
    fonts/
      font_ascii@1x.png
```

---

## 7. CARD FACE LAYOUT SPEC (152×212)

| Region | Position | Size | Content | Notes |
|--------|----------|------|---------|-------|
| Outer border | `(0,0)` | `152×212` | Gothic frame texture | Opaque, no text |
| Art area | `(12, 12)` | `128×88` | Card art backing + portrait | Center cutout via `#FF00FF` |
| Title bar | `(12, 108)` | `128×16` | Card name | Coder renders text here |
| Type bar | `(12, 128)` | `128×16` | Card type | Coder renders text here |
| Ability box | `(12, 148)` | `128×40` | Ability text | Coder renders text here |
| Stat footer | `(12, 192)` | `128×16` | Stats/numbers | Coder renders text here |
| Element tint | Full card overlay | `152×212` | Border-only glow | Center `#FF00FF` transparent |

**Text regions on card face (coder-composited):**
- Title: `(16, 110)` size `120×12`
- Type: `(16, 130)` size `120×12`
- Ability line 1: `(16, 150)` size `120×12`
- Ability line 2: `(16, 166)` size `120×12`
- Stats: `(16, 194)` size `120×12`

---

## 8. GENERATION BATCHES (P0)

**Batch 1:** Tiles (9 files)
**Batch 2:** Card frames + tints (5 files)
**Batch 3:** HUD panels (9 files)
**Batch 4:** Relic sprites base + battle (12 files)
**Batch 5:** VFX spritesheet (1 file) + individual frames (4 files)
**Batch 6:** Portraits + frames (7 files)
**Batch 7:** Cursor + font strip (3 files)

**Total P0:** 46 files

---

## 9. DO-NOT-GENERATE LIST
- No text strings
- No numerals
- No grid/checkerboard lines
- No button labels
- No readability-dependent symbols
- No `#FF00FF` as visible color

All above rendered by coder per coordinates in Sections 3 and 7.

---

## 10. ART DIRECTION NOTES
- Palette: deep burgundy `#722F37`, stone gray `#5A5A5A`, candle gold `#C9A227`, parchment `#C2C3C7`, shadow `#1A1A1A`
- Hard pixel edges, no anti-aliasing
- No gradients unless simulated with dithering
- Atmospheric lighting: candlelight pools, stained glass color casts
- Sprites: 32×32 base, 64×64 battle zoom close-ups with extra detail
- Tiles: 32×32, opaque, uniform top-down perspective
