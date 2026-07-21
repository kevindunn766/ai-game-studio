from PIL import Image

class PixelAssetRenderer:
    def __init__(self, width, height, palette, transparent_color='#FF00FF'):
        self.width = width
        self.height = height
        self.palette = {hex.upper(): idx for idx, hex in enumerate(palette)}
        self.transparent_color = transparent_color.upper()
        self.pixels = [[self.transparent_color] * width for _ in range(height)]

    def set_pixel(self, x, y, hex_color):
        if 0 <= x < self.width and 0 <= y < self.height:
            self.pixels[y][x] = hex_color.upper()

    def fill_rect(self, x0, y0, w, h, hex_color):
        for y in range(y0, min(y0 + h, self.height)):
            for x in range(x0, min(x0 + w, self.width)):
                self.set_pixel(x, y, hex_color)

    def apply_dither_horizontal(self, y, x_start, x_end, color_a, color_b, pattern):
        for i, x in enumerate(range(x_start, min(x_end, self.width))):
            if 0 <= y < self.height and 0 <= x < self.width:
                color = color_a if pattern[i % len(pattern)] == 0 else color_b
                self.set_pixel(x, y, color)

    def apply_dither_vertical(self, x, y_start, y_end, color_a, color_b, pattern):
        for i, y in enumerate(range(y_start, min(y_end, self.height))):
            if 0 <= x < self.width and 0 <= y < self.height:
                color = color_a if pattern[i % len(pattern)] == 0 else color_b
                self.set_pixel(x, y, color)

    def save(self, path):
        img = Image.new('P', (self.width, self.height), self.palette[self.transparent_color])
        img.putpalette([int(h.lstrip('#')[i:i+2], 16) for h in sorted(self.palette, key=lambda h: self.palette[h]) for i in (0, 2, 4)])
        for y in range(self.height):
            for x in range(self.width):
                color = self.pixels[y][x]
                if color in self.palette:
                    img.putpixel((x, y), self.palette[color])
                else:
                    img.putpixel((x, y), self.palette[self.transparent_color])
        img.save(path, transparency=self.palette[self.transparent_color])

if __name__ == '__main__':
    palette = ['#FF00FF', '#000000', '#8B4513', '#B22222', '#FF8C00', '#FFBF00', '#FFFFE0']
    renderer = PixelAssetRenderer(16, 16, palette)
    for i in range(16):
        renderer.set_pixel(i, 15, '#8B4513')
    for i in range(16):
        renderer.set_pixel(i, 14, '#B22222')
    renderer.save('C:/Users/kevin/game-studio/assets/tile_volcanic_floor.png')
