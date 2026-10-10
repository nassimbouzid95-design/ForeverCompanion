# Generates the addon textures (uncompressed 32-bit TGA, bottom-left origin).
import math, struct, sys
from PIL import Image, ImageDraw, ImageFilter
OUT = sys.argv[1]

def save_tga(img, path):
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    px = img.transpose(Image.FLIP_TOP_BOTTOM).tobytes()
    data = bytearray()
    for i in range(0, len(px), 4):
        r, g, b, a = px[i:i+4]
        data += bytes((b, g, r, a))
    open(path, "wb").write(header + bytes(data))

S = 4  # supersampling
def canvas(w, h): return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
def down(img, w, h): return img.resize((w, h), Image.LANCZOS)

# Arrow: white, pointing up, with a light-to-darker vertical shading and a dark outline.
W = 128
img = canvas(W, W)
d = ImageDraw.Draw(img)
pts = [(64, 8), (112, 112), (64, 86), (16, 112)]
pts = [(x * S, y * S) for x, y in pts]
shadow = canvas(W, W)
ImageDraw.Draw(shadow).polygon([(x + 3 * S, y + 4 * S) for x, y in pts], fill=(0, 0, 0, 170))
shadow = shadow.filter(ImageFilter.GaussianBlur(4 * S))
img.alpha_composite(shadow)
outline = canvas(W, W)
ImageDraw.Draw(outline).polygon(pts, fill=(10, 10, 14, 255))
outline = outline.filter(ImageFilter.MaxFilter(9))
img.alpha_composite(outline)
body = canvas(W, W)
bd = ImageDraw.Draw(body)
bd.polygon(pts, fill=(255, 255, 255, 255))
# shade the right half slightly darker for a 3D look
shade = canvas(W, W)
ImageDraw.Draw(shade).polygon([(64 * S, 8 * S), (112 * S, 112 * S), (64 * S, 86 * S)], fill=(0, 0, 0, 70))
mask = body.split()[3]
body.alpha_composite(Image.composite(shade, canvas(W, W), mask))
img.alpha_composite(body)
save_tga(down(img, W, W), OUT + "/Arrow.tga")

# Ring: dark disc with a thin bright rim (behind the arrow).
img = canvas(W, W)
d = ImageDraw.Draw(img)
d.ellipse((6 * S, 6 * S, 122 * S, 122 * S), fill=(8, 10, 16, 200))
d.ellipse((6 * S, 6 * S, 122 * S, 122 * S), outline=(255, 255, 255, 120), width=3 * S)
save_tga(down(img, W, W), OUT + "/Ring.tga")

# Glow: soft radial white.
G = 64
img = Image.new("RGBA", (G, G))
for y in range(G):
    for x in range(G):
        r = math.hypot(x - G / 2 + 0.5, y - G / 2 + 0.5) / (G / 2)
        a = max(0.0, 1 - r) ** 2
        img.putpixel((x, y), (255, 255, 255, int(a * 255)))
save_tga(img, OUT + "/Glow.tga")

# Bar: smooth status bar texture (white, soft vertical gradient and a top highlight).
img = Image.new("RGBA", (256, 32))
for y in range(32):
    t = y / 31
    v = int(255 * (1 - 0.35 * t))
    if y < 2: v = 255
    for x in range(256): img.putpixel((x, y), (v, v, v, 255))
save_tga(img, OUT + "/Bar.tga")

# Logo: the CurseForge logo, 64x64.
logo = Image.open(sys.argv[2]).convert("RGBA").resize((64, 64), Image.LANCZOS)
save_tga(logo, OUT + "/Logo.tga")
print("ok")
