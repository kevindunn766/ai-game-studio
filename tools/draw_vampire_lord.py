import sys
sys.path.insert(0, 'C:/Users/kevin/game-studio/tools')
from pixel_art_engine import PixelEngine

# Character sprite — 23x47 px, SOTN-size
# Style: tall gothic vampire figure, dark cloak, pale skin accents
palette = [
    '#FF00FF', '#000000', '#FFFFFF', '#E0E0E0', '#B0B0B0',
    '#8B4513', '#B22222', '#FF8C00', '#FFBF00', '#2A1A0A'
]
engine = PixelEngine(23, 47, palette)

cx = 11  # center x roughly

# Cape behind body — large flowing shape
cape_x = [3, 2, 1, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6]
cape_top = 8
for i, w in enumerate(cape_x):
    y = cape_top + i
    for x in range(cx - w, cx + w + 1):
        engine.set_pixel(x, y, '#2A1A0A')
# cape bottom flare
for y in range(cape_top + len(cape_x), 44):
    engine.fill_rect(max(0, cx-6), y, 13, 1, '#2A1A0A')

# Legs — two columns
engine.fill_rect(cx-3, 30, 3, 14, '#1A1A1A')
engine.fill_rect(cx, 30, 3, 14, '#1A1A1A')
# Boot tops
engine.fill_rect(cx-3, 42, 3, 2, '#8B4513')
engine.fill_rect(cx, 42, 3, 2, '#8B4513')

# Torso — dark coat
engine.fill_rect(cx-4, 18, 8, 12, '#1A1A1A')
# Coat center line gold trim
engine.fill_rect(cx-1, 18, 2, 12, '#FFBF00')
# Belt
engine.fill_rect(cx-4, 27, 8, 1, '#8B4513')

# Arms
engine.fill_rect(cx-6, 20, 2, 16, '#1A1A1A')  # left arm
engine.fill_rect(cx+4, 20, 2, 16, '#1A1A1A')   # right arm
# Hands
engine.fill_rect(cx-6, 36, 2, 2, '#E0E0E0')
engine.fill_rect(cx+4, 36, 2, 2, '#E0E0E0')

# Head — oval-ish
engine.fill_rect(cx-3, 5, 6, 8, '#E0E0E0')
# Hair — slicked back, spiky crown
engine.fill_rect(cx-3, 2, 6, 3, '#1A1A1A')
engine.fill_rect(cx-4, 3, 2, 2, '#1A1A1A')
engine.fill_rect(cx+2, 3, 2, 2, '#1A1A1A')
engine.fill_rect(cx-5, 4, 1, 1, '#1A1A1A')
engine.fill_rect(cx+4, 4, 1, 1, '#1A1A1A')
# Eyes — slits, red
engine.set_pixel(cx-2, 9, '#B22222')
engine.set_pixel(cx-1, 9, '#B22222')
engine.set_pixel(cx+1, 9, '#B22222')
engine.set_pixel(cx+2, 9, '#B22222')

# Collar / cloak clasp at neck
engine.fill_rect(cx-2, 15, 4, 3, '#FF8C00')

engine.save('C:/Users/kevin/game-studio/assets/characters/vampire_lord_23x47.png')
