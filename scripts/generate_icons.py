#!/usr/bin/env python3
"""Generate Android + iOS app icons from assets/logo.png"""

import os
import sys

try:
    from PIL import Image
except ImportError:
    print("Pillow required: pip install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "logo.png")

if not os.path.exists(SRC):
    print(f"Source icon not found: {SRC}", file=sys.stderr)
    sys.exit(1)

src = Image.open(SRC).convert("RGBA")

# Android mipmap icons
android_sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for folder, size in android_sizes.items():
    path = os.path.join(ROOT, "android", "app", "src", "main", "res", folder)
    os.makedirs(path, exist_ok=True)

    # launcher icon
    resized = src.resize((size, size), Image.LANCZOS)
    resized.save(os.path.join(path, "ic_launcher.png"))

    # adaptive foreground (108dp canvas, 72dp safe zone)
    adaptive_size = int(size * 108 / 48)
    canvas = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
    icon_size = int(size * 72 / 48)
    icon = src.resize((icon_size, icon_size), Image.LANCZOS)
    offset = (adaptive_size - icon_size) // 2
    canvas.paste(icon, (offset, offset), icon)
    canvas.save(os.path.join(path, "ic_launcher_foreground.png"))

print("Android icons generated")

# iOS icons
ios_path = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(ios_path, exist_ok=True)

ios_icons = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

for filename, size in ios_icons:
    resized = src.resize((size, size), Image.LANCZOS)
    if size == 1024:
        bg = Image.new("RGB", (size, size), (0, 0, 0))
        bg.paste(resized, mask=resized.split()[3])
        bg.save(os.path.join(ios_path, filename))
    else:
        resized.save(os.path.join(ios_path, filename))

print("iOS icons generated")
