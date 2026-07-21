import sys
sys.path.insert(0, 'C:/Users/kevin/game-studio/tools')
from pixel_art_engine import PixelEngine

palette = [
    '#FF00FF', '#000000', '#2A1A0A', '#8B4513',
    '#B22222', '#FF8C00', '#FFBF00'
]
engine = PixelEngine(64, 64, palette)

cx, cy = 32, 36

# Legs — thick pillars, wide stance
engine.fill_rect(cx-14, cy+4, 12, 18, '#2A1A0A')
engine.fill_rect(cx+2, cy+4, 12, 18, '#2A1A0A')
# Boot/hoof caps
engine.fill_rect(cx-14, cy+18, 12, 3, '#8B4513')
engine.fill_rect(cx+2, cy+18, 12, 3, '#8B4513')

# Torso — hunched ribcage
engine.fill_rect(cx-12, cy-14, 24, 20, '#8B4513')
# ribcage hollows filled with magma
engine.fill_rect(cx-10, cy-10, 4, 10, '#FF8C00')
engine.fill_rect(cx-4, cy-10, 4, 10, '#FF8C00')
engine.fill_rect(cx+2, cy-10, 4, 10, '#FF8C00')
engine.fill_rect(cx+8, cy-10, 4, 10, '#FF8C00')
# spine line
engine.fill_rect(cx-1, cy-16, 2, 18, '#2A1A0A')

# Left arm — massive club
engine.fill_rect(cx-22, cy-10, 10, 22, '#8B4513')
# club head
engine.fill_rect(cx-28, cy-14, 8, 10, '#8B4513')
engine.fill_rect(cx-30, cy-10, 4, 4, '#8B4513')
# club cracks
engine.fill_rect(cx-26, cy-12, 2, 2, '#FF8C00')

# Right arm — clawed guard
engine.fill_rect(cx+20, cy-10, 8, 18, '#8B4513')
# claws
engine.set_pixel(cx+24, cy-12, '#FFBF00')
engine.set_pixel(cx+26, cy-12, '#FFBF00')
engine.set_pixel(cx+23, cy-11, '#FFBF00')
engine.set_pixel(cx+25, cy-11, '#FFBF00')

# Head — oversized cranium
engine.fill_rect(cx-10, cy-28, 20, 14, '#8B4513')
# eye sockets
engine.fill_rect(cx-7, cy-25, 5, 4, '#000000')
engine.fill_rect(cx+2, cy-25, 5, 4, '#000000')
# jaw — agape
engine.fill_rect(cx-8, cy-16, 16, 4, '#8B4513')
engine.fill_rect(cx-6, cy-14, 12, 2, '#000000')  # mouth void
engine.fill_rect(cx-4, cy-14, 3, 2, '#FF8C00')  # teeth glow
engine.fill_rect(cx+2, cy-14, 3, 2, '#FF8C00')

# Shoulders glow
engine.fill_rect(cx-16, cy-18, 6, 4, '#B22222')
engine.fill_rect(cx+10, cy-18, 6, 4, '#B22222')

# Embers — 1px sparks
engine.set_pixel(cx-18, cy-24, '#FFBF00')
engine.set_pixel(cx+16, cy-24, '#FFBF00')
engine.set_pixel(cx-20, cy-20, '#FFBF00')
engine.set_pixel(cx+18, cy-22, '#FFBF00')
engine.set_pixel(cx-14, cy-30, '#FFBF00')
engine.set_pixel(cx+14, cy-30, '#FFBF00')
engine.set_pixel(cx, cy-32, '#FFBF00')

engine.save('C:/Users/kevin/game-studio/assets/monster_volcanic_bone_brute_64x64.png')
