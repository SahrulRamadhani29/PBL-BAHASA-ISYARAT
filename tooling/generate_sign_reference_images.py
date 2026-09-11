"""Split the dataset's real-photo ASL reference sheet into app assets."""

from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_PATH = ROOT / "tooling/reference_source/amer_sign2.png"
OUTPUT_DIR = ROOT / "assets/signs"
LABELS = "ABCDEFGHIKLMNOPQRSTUVWXY"


def main() -> None:
    sheet = Image.open(REFERENCE_PATH).convert("RGB")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    cell_width = sheet.width / 6
    cell_height = sheet.height / 4
    for index, letter in enumerate(LABELS):
        row, column = divmod(index, 6)
        left = round(column * cell_width) + 5
        right = round((column + 1) * cell_width) - 5
        top = round(row * cell_height) + 3
        bottom = round(row * cell_height) + 98
        photo = sheet.crop((left, top, right, bottom))
        photo = ImageOps.fit(
            photo,
            (280, 250),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.48),
        )
        canvas = Image.new("RGB", (280, 280), "#f2f4f1")
        canvas.paste(photo, (0, 15))
        canvas.save(OUTPUT_DIR / f"{letter.lower()}.png", optimize=True)

    print(f"Generated {len(LABELS)} reference photos in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
