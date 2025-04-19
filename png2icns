#!/usr/bin/env python3
import argparse
import sys
import os
import shutil
import subprocess
from PIL import Image

def main():
    parser = argparse.ArgumentParser(description="Convert a PNG image into an .icns icon")
    parser.add_argument("input_image", help="Path to the input PNG file")
    args = parser.parse_args()

    input_image = args.input_image
    if not os.path.isfile(input_image):
        print(f"Error: File '{input_image}' not found.", file=sys.stderr)
        sys.exit(1)

    try:
        with Image.open(input_image) as img:
            width, height = img.size
    except Exception:
        print(f"Error: Unable to determine dimensions of '{input_image}'.", file=sys.stderr)
        sys.exit(1)

    max_size = max(width, height)
    if max_size < 16:
        print("Error: Image resolution too small for icon generation.", file=sys.stderr)
        sys.exit(1)

    input_dir = os.path.dirname(input_image)
    base_name = os.path.splitext(os.path.basename(input_image))[0]
    iconset_dir = os.path.join(input_dir, f"{base_name}.iconset")
    icns_file = os.path.join(input_dir, f"{base_name}.icns")

    os.makedirs(iconset_dir, exist_ok=True)

    # Required icon sizes for macOS
    sizes = [16, 32, 64, 128, 256, 512]
    for size in sizes:
        # 1x
        if size <= max_size:
            output_1x = os.path.join(iconset_dir, f"icon_{size}x{size}.png")
            with Image.open(input_image) as img:
                img.resize((size, size), Image.LANCZOS).save(output_1x)

        # 2x (Retina)
        retina = size * 2
        if retina <= max_size:
            output_2x = os.path.join(iconset_dir, f"icon_{size}x{size}@2x.png")
            with Image.open(input_image) as img:
                img.resize((retina, retina), Image.LANCZOS).save(output_2x)

    # Build .icns using macOS iconutil
    result = subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_file])
    if result.returncode != 0:
        print("Error: Failed to generate .icns file via iconutil.", file=sys.stderr)
        sys.exit(1)

    # Cleanup intermediate iconset folder
    shutil.rmtree(iconset_dir)

    print(f"ICNS file generated: {icns_file}")

if __name__ == "__main__":
    main()