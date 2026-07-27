from pathlib import Path

from PIL import Image, ImageFilter


project = Path(__file__).resolve().parents[1]
source_path = project / "Assets" / "CineBar-icon-1024.png"
output_path = project / "Assets" / "MenuBarIcon-template.png"

source = Image.open(source_path).convert("RGB")

# The app mark is warm gold on a cool navy background. Build the template from
# that color separation so the menu bar symbol preserves the ticket/play shape
# but lets macOS choose black or white according to the current appearance.
def alpha_for(pixel: tuple[int, int, int]) -> int:
    red, green, blue = pixel
    warmth = red - blue
    is_gold = red > 105 and green > 55 and warmth > 38 and red > green
    return max(0, min(255, (warmth - 30) * 4)) if is_gold else 0


alpha = Image.new("L", source.size)
alpha.putdata([alpha_for(pixel) for pixel in source.getdata()])
alpha = alpha.filter(ImageFilter.GaussianBlur(0.7))

bbox = alpha.getbbox()
if bbox is None:
    raise RuntimeError("Could not isolate the gold CineBar mark")

mark = Image.new("RGBA", source.size, (0, 0, 0, 0))
mark.putalpha(alpha)
mark = mark.crop(bbox)

side = max(mark.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.alpha_composite(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
square.thumbnail((100, 100), Image.Resampling.LANCZOS)

template = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
template.alpha_composite(
    square,
    ((template.width - square.width) // 2, (template.height - square.height) // 2),
)
template.save(output_path)
print(output_path)
