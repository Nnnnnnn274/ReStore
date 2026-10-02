"""Render ReStore's original vector monogram into checked-in Xcode icon sizes.

Run with Python and Pillow when changing the brand artwork; Xcode uses the PNGs.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTLINE = "M300 740V284H518C626 284 690 345 690 436C690 519 650 568 593 586L728 740H595L480 600H412V740Z M412 390V490H518C559 490 580 470 580 439C580 408 560 390 518 390Z"
PALETTES = {
    "Blue": ((21, 43, 131), (63, 112, 255)),
    "Dark": ((14, 19, 33), (44, 54, 75)),
    "Honeydew": ((14, 95, 87), (52, 163, 114)),
    "Pride": ((107, 48, 164), (235, 102, 122)),
    "Sandy": ((135, 86, 45), (218, 164, 90)),
    "Sky": ((18, 95, 158), (76, 176, 223)),
    "Snow": ((100, 124, 153), (159, 191, 219)),
    "Starburst": ((151, 50, 34), (247, 137, 62)),
    "Storm": ((46, 48, 74), (103, 96, 151)),
    "Vista": ((13, 88, 99), (50, 163, 147)),
    "Winter": ((52, 66, 133), (140, 141, 219)),
}


def curve(start, control1, control2, end):
    points = []
    for i in range(1, 65):
        t = i / 64
        points.append(tuple((1-t)**3*a + 3*(1-t)**2*t*b + 3*(1-t)*t*t*c + t**3*d
                            for a, b, c, d in zip(start, control1, control2, end)))
    return points


def render(palette):
    size = 2048
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    top, bottom = palette
    for y in range(size):
        t = y / (size - 1)
        draw.line((0, y, size, y), fill=tuple(round(a+(b-a)*t) for a,b in zip(top,bottom)))
    outline = [(300,740),(300,284),(518,284)]
    outline += curve((518,284),(626,284),(690,345),(690,436))
    outline += curve((690,436),(690,519),(650,568),(593,586))
    outline += [(728,740),(595,740),(480,600),(412,600),(412,740)]
    hole = [(412,390),(412,490),(518,490)]
    hole += curve((518,490),(559,490),(580,470),(580,439))
    hole += curve((580,439),(580,408),(560,390),(518,390))
    mask = Image.new("L", (size,size))
    mask_draw = ImageDraw.Draw(mask)
    scale = lambda points: [(x*2,y*2) for x,y in points]
    mask_draw.polygon(scale(outline), fill=255)
    mask_draw.polygon(scale(hole), fill=0)
    image.paste((255,255,255), mask=mask)
    draw.polygon(scale([(480,600),(593,586),(728,740),(595,740)]), fill=(112,239,216))
    return image


def main():
    primary = PALETTES["Blue"]
    for catalog in [ROOT / "ReStoreApp/Resources/Icons.xcassets",
                    ROOT / "ReStoreApp/Resources/Assets.xcassets/ReStore.imageset",
                    ROOT / "ReStoreWidget/Assets.xcassets/ReStore.imageset"]:
        for manifest in catalog.rglob("Contents.json"):
            data = json.loads(manifest.read_text())
            palette = PALETTES.get(manifest.parent.name.split(".")[0].replace("Icon", ""), primary)
            image = render(palette)
            for item in data.get("images", []):
                filename = item.get("filename")
                if not filename or not filename.endswith(".png"):
                    continue
                path = manifest.parent / filename
                if item.get("size"):
                    side = round(float(item["size"].split("x")[0]) * float(item.get("scale", "1x").rstrip("x")))
                else:
                    # Named previews in the existing catalog are all square PNGs.
                    side = Image.open(path).size[0] if path.exists() else 1024
                image.resize((side,side), Image.Resampling.LANCZOS).save(path)
    vector = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
              f'<path fill="white" fill-rule="evenodd" d="{OUTLINE}"/></svg>\n')
    (ROOT / "ReStoreWidget/Assets.xcassets/Badge.imageset/restore-logo.svg").write_text(vector, encoding="utf-8")
    (ROOT / "ReStoreWidget/Assets.xcassets/SmallIcon.imageset/cir.svg").write_text(vector, encoding="utf-8")
    print("Rendered ReStore app icons, previews, and widget monograms")


if __name__ == "__main__":
    main()
