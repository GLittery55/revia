#!/usr/bin/env python3
"""Generate thesis-ready overview and appendix assets for the 22 reflection cards.

The card order is read from CardService's fixed local catalogue so the paper stays
aligned with the order used by the application. The unrelated card2_1.png asset is
therefore excluded automatically.
"""

from __future__ import annotations

import argparse
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


@dataclass(frozen=True)
class Card:
    number: int
    title: str
    image_name: str
    image_path: Path

    @property
    def label(self) -> str:
        return f"图像卡 {self.number:02d}  {self.title}"


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="生成论文正文用卡牌总览图和附录 PDF。"
    )
    parser.add_argument("--repo-root", type=Path, default=repo_root)
    parser.add_argument("--dpi", type=int, default=300)
    parser.add_argument(
        "--image-dir",
        type=Path,
        default=None,
        help="Optional card image directory; defaults to the app's production card directory.",
    )
    parser.add_argument(
        "--output-prefix",
        default="reflection_cards",
        help="Stable filename prefix for generated assets.",
    )
    parser.add_argument(
        "--preview-only",
        action="store_true",
        help="Generate only the overview PNG and skip both PDF outputs.",
    )
    return parser.parse_args()


def load_catalogue(repo_root: Path, image_dir: Path | None = None) -> list[Card]:
    service_path = repo_root / "BeyondComfort/Services/AppServices.swift"
    source = service_path.read_text(encoding="utf-8")
    catalogue_start = source.index("private let catalogue: [Definition]")
    catalogue_end = source.index("private let referenceCatalogue", catalogue_start)
    catalogue_source = source[catalogue_start:catalogue_end]

    entries = re.findall(
        r'\.init\(title:\s*"([^"]+)",\s*imageName:\s*"([^"]+)"',
        catalogue_source,
    )
    if len(entries) != 22:
        raise RuntimeError(
            f"Expected 22 cards in CardService catalogue, found {len(entries)}."
        )

    image_dir = image_dir or repo_root / "BeyondComfort/Resources/card"
    cards = [
        Card(
            number=index,
            title=title,
            image_name=image_name,
            image_path=image_dir / f"{image_name}.png",
        )
        for index, (title, image_name) in enumerate(entries, start=1)
    ]

    missing = [str(card.image_path) for card in cards if not card.image_path.is_file()]
    if missing:
        raise FileNotFoundError("Missing card images:\n" + "\n".join(missing))
    return cards


def find_pillow_font() -> Path:
    candidates = [
        Path("/System/Library/Fonts/STHeiti Medium.ttc"),
        Path("/System/Library/Fonts/STHeiti Light.ttc"),
        Path("/System/Library/Fonts/Supplemental/Songti.ttc"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("No Chinese font found for overview labels.")


def place_contained_image(
    destination: Image.Image,
    image_path: Path,
    box: tuple[int, int, int, int],
) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    target_size = (right - left, bottom - top)
    with Image.open(image_path) as original:
        source = ImageOps.exif_transpose(original).convert("RGB")
        fitted = ImageOps.contain(source, target_size, Image.Resampling.LANCZOS)
    x = left + (target_size[0] - fitted.width) // 2
    y = top + (target_size[1] - fitted.height) // 2
    destination.paste(fitted, (x, y))
    return x, y, x + fitted.width, y + fitted.height


def generate_overview_png(cards: list[Card], output_path: Path, dpi: int) -> None:
    # A4 landscape at 300 dpi. A 7-8-7 layout makes the final row intentional
    # while keeping every portrait card large enough for an overview figure.
    page_width = round(11.6929 * dpi)
    page_height = round(8.2677 * dpi)
    background = Image.new("RGB", (page_width, page_height), "white")
    draw = ImageDraw.Draw(background)

    card_width = round(1.32 * dpi)
    card_height = round(1.98 * dpi)
    column_gap = round(0.065 * dpi)
    row_gap = round(0.16 * dpi)
    label_gap = round(0.04 * dpi)
    label_height = round(0.17 * dpi)
    row_height = card_height + label_gap + label_height
    layout = (7, 8, 7)
    total_height = len(layout) * row_height + (len(layout) - 1) * row_gap
    top = (page_height - total_height) // 2

    font = ImageFont.truetype(str(find_pillow_font()), round(0.09 * dpi))
    border_width = max(1, round(dpi / 150))
    index = 0

    for row_index, column_count in enumerate(layout):
        row_width = column_count * card_width + (column_count - 1) * column_gap
        row_left = (page_width - row_width) // 2
        card_top = top + row_index * (row_height + row_gap)

        for column_index in range(column_count):
            card = cards[index]
            card_left = row_left + column_index * (card_width + column_gap)
            image_bounds = place_contained_image(
                background,
                card.image_path,
                (
                    card_left,
                    card_top,
                    card_left + card_width,
                    card_top + card_height,
                ),
            )
            draw.rectangle(
                image_bounds,
                outline=(125, 125, 125),
                width=border_width,
            )

            label_y = card_top + card_height + label_gap
            label_bounds = draw.textbbox((0, 0), card.label, font=font)
            label_width = label_bounds[2] - label_bounds[0]
            label_x = card_left + (card_width - label_width) // 2
            draw.text((label_x, label_y), card.label, fill=(32, 32, 32), font=font)
            index += 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    background.save(output_path, format="PNG", dpi=(dpi, dpi), optimize=True)


def generate_overview_pdf(
    overview_png: Path,
    output_path: Path,
    temporary_dir: Path,
) -> None:
    page_width, page_height = landscape(A4)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    overview_jpeg = temporary_dir / "overview-for-pdf.jpg"
    with Image.open(overview_png) as image:
        image.convert("RGB").save(
            overview_jpeg,
            format="JPEG",
            quality=95,
            subsampling=0,
            optimize=True,
            dpi=(300, 300),
        )

    pdf = canvas.Canvas(
        str(output_path),
        pagesize=(page_width, page_height),
        pageCompression=1,
    )
    pdf.setTitle("22张反思图像卡总览")
    pdf.setAuthor("Beyond Comfort")
    pdf.drawImage(
        ImageReader(str(overview_jpeg)),
        0,
        0,
        width=page_width,
        height=page_height,
        preserveAspectRatio=True,
        anchor="c",
    )
    pdf.showPage()
    pdf.save()


def draw_appendix_card(
    pdf: canvas.Canvas,
    card: Card,
    pdf_image_path: Path,
    cell_left: float,
    cell_bottom: float,
    cell_width: float,
    cell_height: float,
) -> None:
    label_height = 24
    card_box_width = min(216, cell_width - 8)
    card_box_height = min(324, cell_height - label_height - 8)
    # All production images are approximately 2:3; this keeps small source-size
    # differences from creating visible alignment drift.
    card_box_width = min(card_box_width, card_box_height * 2 / 3)
    card_box_height = card_box_width * 3 / 2
    x = cell_left + (cell_width - card_box_width) / 2
    y = cell_bottom + label_height + (cell_height - label_height - card_box_height) / 2

    pdf.setStrokeColorRGB(0.55, 0.55, 0.55)
    pdf.setLineWidth(0.5)
    pdf.rect(x, y, card_box_width, card_box_height, stroke=1, fill=0)
    pdf.drawImage(
        ImageReader(str(pdf_image_path)),
        x,
        y,
        width=card_box_width,
        height=card_box_height,
        preserveAspectRatio=True,
        anchor="c",
        mask="auto",
    )

    pdf.setFont("ThesisChinese", 10.5)
    pdf.setFillColorRGB(0.12, 0.12, 0.12)
    pdf.drawCentredString(cell_left + cell_width / 2, cell_bottom + 7, card.label)


def prepare_appendix_images(cards: list[Card], temporary_dir: Path) -> dict[int, Path]:
    prepared: dict[int, Path] = {}
    for card in cards:
        output_path = temporary_dir / f"card-{card.number:02d}.jpg"
        with Image.open(card.image_path) as original:
            image = ImageOps.exif_transpose(original).convert("RGB")
            image.thumbnail((720, 1080), Image.Resampling.LANCZOS)
            image.save(
                output_path,
                format="JPEG",
                quality=93,
                subsampling=0,
                optimize=True,
                dpi=(240, 240),
            )
        prepared[card.number] = output_path
    return prepared


def generate_appendix_pdf(
    cards: list[Card],
    pdf_images: dict[int, Path],
    output_path: Path,
) -> None:
    pdfmetrics.registerFont(
        TTFont(
            "ThesisChinese",
            str(find_pillow_font()),
            subfontIndex=0,
        )
    )
    page_width, page_height = A4
    output_path.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(output_path), pagesize=A4, pageCompression=1)
    pdf.setTitle("附录 A 反思图像卡完整图集")
    pdf.setAuthor("Beyond Comfort")
    pdf.setSubject("22张反思图像卡，按应用固定目录顺序排列")

    margin_x = 42
    content_bottom = 48
    content_top = page_height - 66
    column_gap = 22
    row_gap = 20
    cell_width = (page_width - 2 * margin_x - column_gap) / 2
    cell_height = (content_top - content_bottom - row_gap) / 2

    for page_index, page_start in enumerate(range(0, len(cards), 4), start=1):
        title = "附录 A  反思图像卡完整图集" if page_index == 1 else "附录 A（续）"
        pdf.setFont("ThesisChinese", 15 if page_index == 1 else 12)
        pdf.setFillColorRGB(0.08, 0.08, 0.08)
        pdf.drawString(margin_x, page_height - 38, title)
        pdf.setStrokeColorRGB(0.72, 0.72, 0.72)
        pdf.setLineWidth(0.5)
        pdf.line(margin_x, page_height - 47, page_width - margin_x, page_height - 47)

        page_cards = cards[page_start : page_start + 4]
        for local_index, card in enumerate(page_cards):
            row = local_index // 2
            column = local_index % 2
            left = margin_x + column * (cell_width + column_gap)
            bottom = content_top - (row + 1) * cell_height - row * row_gap
            draw_appendix_card(
                pdf,
                card,
                pdf_images[card.number],
                left,
                bottom,
                cell_width,
                cell_height,
            )

        pdf.setFont("Helvetica", 9)
        pdf.setFillColorRGB(0.35, 0.35, 0.35)
        pdf.drawCentredString(page_width / 2, 24, f"A-{page_index}")
        pdf.showPage()

    pdf.save()


def main() -> None:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    image_dir = args.image_dir.resolve() if args.image_dir else None
    cards = load_catalogue(repo_root, image_dir)

    prefix = args.output_prefix
    if not re.fullmatch(r"[A-Za-z0-9_-]+", prefix):
        raise ValueError("--output-prefix may contain only letters, digits, underscores, and hyphens.")
    overview_png = repo_root / f"output/figures/{prefix}_overview_7-8-7.png"
    overview_pdf = repo_root / f"output/pdf/{prefix}_overview_7-8-7.pdf"
    appendix_pdf = repo_root / f"output/pdf/appendix_A_{prefix}.pdf"

    generate_overview_png(cards, overview_png, args.dpi)
    print(f"Generated {overview_png}")
    if args.preview_only:
        return

    temporary_root = repo_root / "tmp/pdfs"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="card-thesis-",
        dir=temporary_root,
    ) as temporary_dir_string:
        temporary_dir = Path(temporary_dir_string)
        generate_overview_pdf(overview_png, overview_pdf, temporary_dir)
        pdf_images = prepare_appendix_images(cards, temporary_dir)
        generate_appendix_pdf(cards, pdf_images, appendix_pdf)

    print(f"Generated {overview_pdf}")
    print(f"Generated {appendix_pdf}")


if __name__ == "__main__":
    main()
