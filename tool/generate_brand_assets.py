"""Generate Serenut logo exports from the approved geometric mark.

The script intentionally uses only Pillow and deterministic vector geometry so
all raster exports can be reproduced without the original reference PNG.
"""

from pathlib import Path
import shutil
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "branding"
GREEN = "#1B6B3C"
YELLOW = "#E6B134"
WHITE = "#FFFFFF"
BLACK = "#111111"
INK = "#19231F"
FONT_BOLD = Path(r"C:\Windows\Fonts\segoeuib.ttf")


def mark(size: int, variant: str = "color", padding: float = 0.08) -> Image.Image:
    # 2x supersampling keeps diagonal edges clean while making full-kit
    # regeneration fast enough for CI and local development.
    scale = 2
    canvas = size * scale
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    pad = int(canvas * padding)
    span = canvas - (2 * pad)
    center = canvas // 2
    bar = int(span * 0.18)

    if variant == "color":
        plus_color, cross_color = YELLOW, GREEN
    elif variant == "green":
        plus_color = cross_color = GREEN
    elif variant == "yellow":
        plus_color = cross_color = YELLOW
    elif variant == "white":
        plus_color = cross_color = WHITE
    else:
        plus_color = cross_color = BLACK

    draw.rectangle(
        (center - bar // 2, pad, center + bar // 2, canvas - pad),
        fill=plus_color,
    )
    draw.rectangle(
        (pad, center - bar // 2, canvas - pad, center + bar // 2),
        fill=plus_color,
    )

    cross_layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    cross_draw = ImageDraw.Draw(cross_layer)
    cross_draw.rectangle(
        (center - bar // 2, pad, center + bar // 2, canvas - pad),
        fill=cross_color,
    )
    cross_draw.rectangle(
        (pad, center - bar // 2, canvas - pad, center + bar // 2),
        fill=cross_color,
    )
    cross_layer = cross_layer.rotate(45, resample=Image.Resampling.BICUBIC)
    image.alpha_composite(cross_layer)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def rounded_icon(
    size: int,
    background: str,
    variant: str,
    mark_padding: float,
    corner_ratio: float = 0.22,
) -> Image.Image:
    scale = 2
    canvas = size * scale
    icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    radius = int(canvas * corner_ratio)
    draw.rounded_rectangle((0, 0, canvas - 1, canvas - 1), radius, fill=background)
    symbol = mark(canvas, variant=variant, padding=mark_padding)
    icon.alpha_composite(symbol)
    return icon.resize((size, size), Image.Resampling.LANCZOS)


def social_card(width: int = 1200, height: int = 630) -> Image.Image:
    scale = 2
    image = Image.new("RGB", (width * scale, height * scale), WHITE)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 26 * scale, height * scale), fill=GREEN)
    symbol_size = 330 * scale
    symbol = mark(symbol_size, padding=0.08)
    image.paste(symbol, (90 * scale, (height * scale - symbol_size) // 2), symbol)
    # Keep the card font-independent: product text is added by the consuming page.
    return image.resize((width, height), Image.Resampling.LANCZOS)


def lockup(height: int, label: str, reverse: bool = False) -> Image.Image:
    """Create a horizontal symbol + wordmark lockup on a transparent canvas."""
    scale = 2
    output_height = height * scale
    symbol_size = int(output_height * 0.78)
    gap = int(output_height * 0.10)
    font_size = int(output_height * 0.39)
    font = ImageFont.truetype(str(FONT_BOLD), font_size)
    scratch = Image.new("RGBA", (1, 1))
    bbox = ImageDraw.Draw(scratch).textbbox((0, 0), label, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    side_padding = int(output_height * 0.11)
    width = side_padding * 2 + symbol_size + gap + text_width
    image = Image.new("RGBA", (width, output_height), (0, 0, 0, 0))
    symbol = mark(symbol_size, "white" if reverse else "color", 0.08)
    symbol_y = (output_height - symbol_size) // 2
    image.alpha_composite(symbol, (side_padding, symbol_y))
    draw = ImageDraw.Draw(image)
    text_x = side_padding + symbol_size + gap
    text_y = (output_height - text_height) // 2 - bbox[1]
    draw.text(
        (text_x, text_y),
        label,
        font=font,
        fill=WHITE if reverse else INK,
    )
    return image.resize(
        (round(width / scale), height),
        Image.Resampling.LANCZOS,
    )


def save_png(image: Image.Image, relative_path: str) -> None:
    path = OUT / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def save_project_png(image: Image.Image, relative_path: str) -> None:
    path = ROOT / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def main() -> None:
    for variant in ("color", "green", "yellow", "black", "white"):
        for size in (24, 32, 48, 64, 96, 128, 256, 512, 1024):
            save_png(mark(size, variant), f"png/{variant}/logo-{variant}-{size}.png")

    for size in (48, 72, 96, 144, 192, 512, 1024):
        save_png(
            rounded_icon(size, WHITE, "color", 0.19),
            f"app/icon-color-{size}.png",
        )
        save_png(
            rounded_icon(size, GREEN, "white", 0.19),
            f"app/icon-reverse-{size}.png",
        )

    for slug, label in (("serenut", "Serenut"), ("serenut-os", "Serenut OS")):
        for height in (64, 128, 256, 512):
            save_png(
                lockup(height, label),
                f"lockups/{slug}-color-{height}h.png",
            )
            save_png(
                lockup(height, label, reverse=True),
                f"lockups/{slug}-white-{height}h.png",
            )

    # Maskable/PWA icons keep all critical artwork inside the central safe zone.
    for size in (192, 512):
        save_png(
            rounded_icon(size, WHITE, "color", 0.25, corner_ratio=0),
            f"web/icon-maskable-{size}.png",
        )
        save_png(
            rounded_icon(size, WHITE, "color", 0.19),
            f"web/icon-{size}.png",
        )

    for size in (16, 32, 48):
        save_png(mark(size, "color", 0.10), f"web/favicon-{size}.png")

    save_png(social_card(), "web/social-card-1200x630.png")

    ico_frames = [mark(size, "color", 0.10) for size in (16, 24, 32, 48, 64, 128, 256)]
    ico_path = OUT / "windows" / "app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    ico_frames[-1].save(ico_path, format="ICO", sizes=[im.size for im in ico_frames])

    # Flutter runtime images. Keep the historic filenames because they are
    # referenced by login, splash, settings and print workflows.
    save_project_png(lockup(256, "Serenut OS"), "assets/logo.png")
    save_project_png(lockup(512, "Serenut OS"), "assets/serenutoslogo.png")

    # Android legacy launcher icons.
    android_sizes = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in android_sizes.items():
        launcher = rounded_icon(size, WHITE, "color", 0.19)
        save_project_png(
            launcher,
            f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
        )
        save_project_png(
            launcher,
            f"android/app/src/main/res/mipmap-{density}/ic_launcher_round.png",
        )
    save_project_png(
        mark(432, "color", 0.25),
        "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png",
    )
    save_project_png(
        mark(432, "white", 0.25),
        "android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png",
    )

    # iOS AppIcon. iOS applies its own mask; source artwork must be opaque and
    # square, so no rounded corners or alpha are used.
    ios_icons = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for filename, size in ios_icons.items():
        icon = Image.new("RGB", (size, size), WHITE)
        symbol = mark(size, "color", 0.19).convert("RGBA")
        icon.paste(symbol, (0, 0), symbol)
        save_project_png(
            icon,
            f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}",
        )

    # Flutter web PWA/favicons.
    web_copies = {
        "icons/Icon-192.png": rounded_icon(192, WHITE, "color", 0.19),
        "icons/Icon-512.png": rounded_icon(512, WHITE, "color", 0.19),
        "icons/Icon-maskable-192.png": rounded_icon(
            192, WHITE, "color", 0.25, corner_ratio=0
        ),
        "icons/Icon-maskable-512.png": rounded_icon(
            512, WHITE, "color", 0.25, corner_ratio=0
        ),
        "icons/apple-touch-icon.png": rounded_icon(
            180, WHITE, "color", 0.19, corner_ratio=0
        ),
        "favicon.png": mark(32, "color", 0.10),
    }
    for relative_path, image in web_copies.items():
        save_project_png(image, f"web/{relative_path}")

    # Windows runner.
    windows_icon = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ico_path, windows_icon)

    # Server website/app shared assets and browser metadata.
    shared_assets = ROOT / "server" / "public" / "shared" / "assets"
    shared_assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUT / "svg" / "logo-color.svg", shared_assets / "logo-color.svg")
    shutil.copy2(OUT / "svg" / "logo-white.svg", shared_assets / "logo-white.svg")
    for filename in (
        "serenut-color.svg",
        "serenut-white.svg",
        "serenut-os-color.svg",
        "serenut-os-white.svg",
    ):
        shutil.copy2(OUT / "svg" / filename, shared_assets / filename)
    shutil.copy2(ico_path, ROOT / "server" / "public" / "favicon.ico")
    save_project_png(mark(32, "color", 0.10), "server/public/favicon-32.png")
    save_project_png(
        rounded_icon(180, WHITE, "color", 0.19, corner_ratio=0),
        "server/public/apple-touch-icon.png",
    )
    save_project_png(
        rounded_icon(192, WHITE, "color", 0.19),
        "server/public/icon-192.png",
    )
    save_project_png(
        rounded_icon(512, WHITE, "color", 0.19),
        "server/public/icon-512.png",
    )
    save_project_png(social_card(), "server/public/social-card-1200x630.png")


if __name__ == "__main__":
    main()
