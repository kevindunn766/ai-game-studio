import sys
sys.path.insert(0, 'C:/Users/kevin/game-studio/tools')
from pixel_art_engine import PixelEngine

palette = ['#FF00FF', '#000000', '#8B4513', '#B22222', '#FF8C00', '#FFBF00', '#FFFFE0']
engine = PixelEngine(32, 32, palette)

# centered anchor
cx, cy = 16, 17

# Outer silhouette: jagged flame shape using rects
engine.fill_rect(cx-11, cy-8, 22, 16, '#B22222')      # main body
engine.fill_rect(cx-9, cy-12, 18, 4, '#B22222')       # upper flame
engine.fill_rect(cx-7, cy-16, 14, 4, '#B22222')       # crown spike
engine.fill_rect(cx-4, cy-20, 8, 4, '#B22222')        # tip

# scorch margin 1px — overwrite outermost ring
for x in range(cx-11, cx+12):
    engine.set_pixel(x, cy-8, '#8B4513')
    engine.set_pixel(x, cy+7, '#8B4513')
for y in range(cy-8, cy+8):
    engine.set_pixel(cx-11, y, '#8B4513')
    engine.set_pixel(cx+11, y, '#8B4513')

# core hotspot 6x6
engine.fill_rect(cx-3, cy-3, 6, 6, '#FF8C00')

# inner glow ring 2px around core
engine.fill_rect(cx-5, cy-5, 10, 2, '#FFBF00')
engine.fill_rect(cx-5, cy+3, 10, 2, '#FFBF00')
engine.fill_rect(cx-5, cy-3, 2, 6, '#FFBF00')
engine.fill_rect(cx+3, cy-3, 2, 6, '#FFBF00')

# shadow cracks — 1px black lines inside body
cracks = [
    (cx-2, cy-6), (cx-1, cy-5), (cx, cy-7), (cx+1, cy-4),
    (cx-3, cy-1), (cx+2, cy), (cx-1, cy+2), (cx+3, cy+3),
    (cx, cy+5), (cx-2, cy+6)
]
for x, y in cracks:
    engine.set_pixel(x, y, '#000000')

# top sparks — 3 isolated dots
engine.set_pixel(cx-6, cy-21, '#FFFFE0')
engine.set_pixel(cx+5, cy-20, '#FFFFE0')
engine.set_pixel(cx, cy-22, '#FFFFE0')

engine.save('C:/Users/kevin/game-studio/assets/ember_token_32x32.png')
