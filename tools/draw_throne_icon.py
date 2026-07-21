import sys
sys.path.insert(0, 'C:/Users/kevin/game-studio/tools')
from pixel_art_engine import PixelEngine

palette = ['#FF00FF', '#000000', '#8B4513', '#B22222', '#FF8C00', '#FFBF00', '#FFFFE0']
engine = PixelEngine(64, 64, palette)

# Miniature throne icon — dark volcanic style
# Seat base
engine.fill_rect(20, 40, 24, 6, '#8B4513')
# Legs
engine.fill_rect(22, 46, 4, 10, '#8B4513')
engine.fill_rect(38, 46, 4, 10, '#8B4513')
# Backrest pillars
engine.fill_rect(22, 18, 4, 22, '#8B4513')
engine.fill_rect(38, 18, 4, 22, '#8B4513')
# Backrest top rail
engine.fill_rect(20, 16, 24, 4, '#8B4513')
# Cushion seat
engine.fill_rect(22, 38, 20, 4, '#B22222')
# Cushion back
engine.fill_rect(24, 24, 16, 14, '#B22222')
# Ember glow through cracks
engine.fill_rect(30, 26, 4, 4, '#FF8C00')
engine.fill_rect(28, 32, 8, 2, '#FFBF00')
engine.fill_rect(26, 36, 12, 2, '#FFBF00')
# Crown detail on top
engine.fill_rect(28, 10, 8, 6, '#8B4513')
engine.fill_rect(30, 6, 4, 4, '#FF8C00')
# Shadow cracks
cracks = [
    (24, 28), (25, 30), (26, 32), (27, 34), (28, 36),
    (38, 28), (37, 30), (36, 32), (35, 34), (34, 36)
]
for x, y in cracks:
    engine.set_pixel(x, y, '#000000')
# Highlight edge on right side
engine.set_pixel(42, 24, '#FFFFE0')
engine.set_pixel(42, 28, '#FFFFE0')
engine.set_pixel(42, 32, '#FFFFE0')

engine.save('C:/Users/kevin/game-studio/assets/throne_icon_64x64.png')
