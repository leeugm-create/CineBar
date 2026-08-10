from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "scripts/assets"
MOVIES = ASSETS / "showcase-movies-current.png"
TV = ASSETS / "showcase-tv-current.png"
ANIME = ASSETS / "showcase-anime-current.png"
OUTPUT = ROOT / "public/cinebar-product-tour.gif"

WIDTH, HEIGHT = 900, 580
CARD_SIZE = (292, 510)


def rounded_card(source: Image.Image, alpha: float = 1.0, zoom: float = 1.0) -> Image.Image:
    fitted = ImageOps.contain(source, CARD_SIZE, Image.Resampling.LANCZOS)
    image = Image.new("RGB", CARD_SIZE, (20, 22, 42))
    image.paste(fitted, ((CARD_SIZE[0] - fitted.width) // 2, (CARD_SIZE[1] - fitted.height) // 2))
    if zoom != 1:
        scaled = image.resize(
            (round(image.width * zoom), round(image.height * zoom)),
            Image.Resampling.LANCZOS,
        )
        image = Image.new("RGB", CARD_SIZE, (20, 22, 42))
        image.paste(scaled, ((CARD_SIZE[0] - scaled.width) // 2, (CARD_SIZE[1] - scaled.height) // 2))

    card = Image.new("RGBA", CARD_SIZE, (0, 0, 0, 0))
    mask = Image.new("L", CARD_SIZE, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, CARD_SIZE[0] - 1, CARD_SIZE[1] - 1), radius=24, fill=255)
    card.paste(image.convert("RGBA"), (0, 0), mask)
    card.putalpha(mask.point(lambda value: round(value * alpha)))
    return card


def background() -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = image.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            glow = max(0, 1 - (((x - 650) / 500) ** 2 + ((y - 130) / 370) ** 2))
            pixels[x, y] = (
                round(12 + 32 * glow),
                round(15 + 23 * glow),
                round(34 + 42 * glow),
            )
    return image.convert("RGBA")


def frame(left: Image.Image, right: Image.Image, left_label: str, right_label: str, emphasis: int = 0) -> Image.Image:
    canvas = background()
    shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    left_x, right_x = 112, 496
    for x in (left_x, right_x):
        shadow_draw.rounded_rectangle(
            (x + 8, 34, x + CARD_SIZE[0] + 8, 34 + CARD_SIZE[1]),
            radius=26,
            fill=(0, 0, 0, 150),
        )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))

    canvas.alpha_composite(rounded_card(left), (left_x, 30))
    canvas.alpha_composite(rounded_card(right), (right_x, 30))

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((left_x, 8, left_x + 96, 25), radius=8, fill=(255, 174, 76, 228))
    draw.rounded_rectangle((right_x, 8, right_x + 96, 25), radius=8, fill=(255, 174, 76, 228))
    # A tiny visual cue between the two live app views; keep the composition quiet.
    draw.rounded_rectangle((451, 270, 463, 310), radius=6, fill=(255, 174, 76, 225))
    draw.ellipse((447, 255, 467, 275), fill=(255, 174, 76, 225))
    draw.ellipse((447, 305, 467, 325), fill=(255, 174, 76, 225))
    return canvas.convert("RGB")


def main() -> None:
    movie = Image.open(MOVIES).convert("RGB")
    tv = Image.open(TV).convert("RGB")
    anime = Image.open(ANIME).convert("RGB")
    frames = [
        frame(movie, tv, "电影", "电视剧"),
        frame(movie, tv, "电影", "电视剧"),
        frame(tv, anime, "电视剧", "动漫"),
        frame(tv, anime, "电视剧", "动漫"),
        frame(anime, movie, "动漫", "电影"),
        frame(anime, movie, "动漫", "电影"),
    ]
    frames[0].save(
        OUTPUT,
        save_all=True,
        append_images=frames[1:],
        duration=560,
        loop=0,
        optimize=True,
        disposal=2,
        colors=128,
    )
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
