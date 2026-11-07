"""App icon: Thea, Ivan and Kai sitting together on a soft rounded square."""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

out = Path(sys.argv[1])
root = Path(__file__).parent / "sprites"
base = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
d = ImageDraw.Draw(base)
d.rounded_rectangle([60, 60, 964, 964], radius=200, fill=(250, 236, 222, 255))
d.rounded_rectangle([60, 640, 964, 964], radius=200, fill=(238, 214, 196, 255))
d.rectangle([60, 640, 964, 760], fill=(238, 214, 196, 255))
for name, cx, s in (("ivan", 300, 13), ("kai", 512, 15), ("thea", 724, 13)):
    im = Image.open(root / name / "sit_0.png")
    im = im.resize((im.width * s, im.height * s), Image.NEAREST)
    base.alpha_composite(im, (cx - im.width // 2, 770 - im.height + 70))
with tempfile.TemporaryDirectory() as t:
    iconset = Path(t) / "AppIcon.iconset"
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for k in (1, 2):
            px = size * k
            name = f"icon_{size}x{size}{'@2x' if k == 2 else ''}.png"
            base.resize((px, px), Image.LANCZOS if px < 256 else Image.NEAREST).save(iconset / name)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out / "AppIcon.icns")], check=True)
