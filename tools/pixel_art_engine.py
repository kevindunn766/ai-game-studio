#!/usr/bin/env python3
# Pixel Art Procedural Engine — deterministic code-based generator
# Usage: python pixel_art_engine.py <command> [args]
# Commands:
#   tile <width> <height> <output_path> --palette <hex1,hex2,...>
#   rect <width> <height> <output_path> <x> <y> <w> <h> <hex> [--palette <hexes>]
#   pixel <width> <height> <output_path> <x> <y> <hex> [--palette <hexes>]

from PIL import Image
import argparse

DEFAULT_PALETTE = [
    '#FF00FF', '#000000', '#8B4513', '#B22222',
    '#FF8C00', '#FFBF00', '#FFFFE0'
]

class PixelEngine:
    def __init__(self, width, height, palette=None, transparent_color='#FF00FF'):
        self.width = width
        self.height = height
        self.palette = {hex.upper(): idx for idx, hex in enumerate(palette or DEFAULT_PALETTE)}
        self.transparent_color = transparent_color.upper()
        self.pixels = [[self.transparent_color] * width for _ in range(height)]

    def set_pixel(self, x, y, hex_color):
        if 0 <= x < self.width and 0 <= y < self.height:
            self.pixels[y][x] = hex_color.upper()

    def fill_rect(self, x0, y0, w, h, hex_color):
        for y in range(y0, min(y0 + h, self.height)):
            for x in range(x0, min(x0 + w, self.width)):
                self.set_pixel(x, y, hex_color)

    def save(self, path):
        img = Image.new('P', (self.width, self.height), self.palette[self.transparent_color])
        img.putpalette([int(h.lstrip('#')[i:i+2], 16) for h in sorted(self.palette, key=lambda h: self.palette[h]) for i in (0, 2, 4)])
        for y in range(self.height):
            for x in range(self.width):
                color = self.pixels[y][x]
                img.putpixel((x, y), self.palette.get(color, self.palette[self.transparent_color]))
        img.save(path, transparency=self.palette[self.transparent_color])

def main():
    parser = argparse.ArgumentParser(description='Pixel Art Procedural Engine')
    subparsers = parser.add_subparsers(dest='command')

    # tile command
    tile_parser = subparsers.add_parser('tile')
    tile_parser.add_argument('width', type=int)
    tile_parser.add_argument('height', type=int)
    tile_parser.add_argument('output', type=str)
    tile_parser.add_argument('--palette', type=str, default=','.join(DEFAULT_PALETTE))

    # rect command
    rect_parser = subparsers.add_parser('rect')
    rect_parser.add_argument('width', type=int)
    rect_parser.add_argument('height', type=int)
    rect_parser.add_argument('output', type=str)
    rect_parser.add_argument('x', type=int)
    rect_parser.add_argument('y', type=int)
    rect_parser.add_argument('w', type=int)
    rect_parser.add_argument('h', type=int)
    rect_parser.add_argument('hex', type=str)
    rect_parser.add_argument('--palette', type=str, default=','.join(DEFAULT_PALETTE))

    # pixel command
    pixel_parser = subparsers.add_parser('pixel')
    pixel_parser.add_argument('width', type=int)
    pixel_parser.add_argument('height', type=int)
    pixel_parser.add_argument('output', type=str)
    pixel_parser.add_argument('x', type=int)
    pixel_parser.add_argument('y', type=int)
    pixel_parser.add_argument('hex', type=str)
    pixel_parser.add_argument('--palette', type=str, default=','.join(DEFAULT_PALETTE))

    args = parser.parse_args()

    palette = [h.strip() for h in (args.palette or ','.join(DEFAULT_PALETTE)).split(',') if h.strip()]
    engine = PixelEngine(args.width, args.height, palette)

    if args.command == 'tile':
        pass  # blank tile
    elif args.command == 'rect':
        engine.fill_rect(args.x, args.y, args.w, args.h, args.hex)
    elif args.command == 'pixel':
        engine.set_pixel(args.x, args.y, args.hex)
    else:
        parser.print_help()
        return

    engine.save(args.output)

if __name__ == '__main__':
    main()
