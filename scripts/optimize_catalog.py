#!/usr/bin/env python3
"""Create a card-optimized Serenut catalog ZIP without loading it into RAM."""

from __future__ import annotations

import argparse
import io
import json
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from PIL import Image, ImageOps, UnidentifiedImageError


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_FILES = 100_000
MAX_SINGLE_IMAGE = 100 * 1024 * 1024


def choose_source() -> Path | None:
    import tkinter as tk
    from tkinter import filedialog

    root = tk.Tk()
    root.withdraw()
    selected = filedialog.askopenfilename(
        title="Serenut katalog ZIP veya Excel dosyasını seçin",
        filetypes=[
            ("Katalog dosyaları", "*.zip *.xlsx"),
            ("ZIP arşivi", "*.zip"),
            ("Excel dosyası", "*.xlsx"),
        ],
    )
    root.destroy()
    return Path(selected) if selected else None


def safe_name(raw: str) -> PurePosixPath:
    normalized = PurePosixPath(raw.replace("\\", "/"))
    if normalized.is_absolute() or ".." in normalized.parts or "\x00" in raw:
        raise ValueError(f"Geçersiz arşiv yolu: {raw}")
    return normalized


def optimize_image(source: bytes, size: int, quality: int) -> bytes:
    with Image.open(io.BytesIO(source)) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
        image.thumbnail((size, size), Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", (size, size), "white")
        canvas.paste(
            image,
            ((size - image.width) // 2, (size - image.height) // 2),
        )
        output = io.BytesIO()
        canvas.save(
            output,
            format="JPEG",
            quality=quality,
            optimize=True,
            progressive=True,
        )
        return output.getvalue()


def iter_source(source: Path):
    if source.suffix.lower() == ".zip":
        archive = zipfile.ZipFile(source, "r")
        try:
            infos = [info for info in archive.infolist() if not info.is_dir()]
            if len(infos) > MAX_FILES:
                raise ValueError(f"Dosya sayısı {MAX_FILES:,} sınırını aşıyor.")
            for info in infos:
                name = safe_name(info.filename)
                yield name, info.file_size, lambda info=info: archive.read(info)
        finally:
            archive.close()
        return

    if source.suffix.lower() == ".xlsx":
        yield PurePosixPath(source.name), source.stat().st_size, source.read_bytes
        return

    if source.is_dir():
        files = [item for item in source.rglob("*") if item.is_file()]
        if len(files) > MAX_FILES:
            raise ValueError(f"Dosya sayısı {MAX_FILES:,} sınırını aşıyor.")
        for item in files:
            relative = PurePosixPath(item.relative_to(source).as_posix())
            yield safe_name(str(relative)), item.stat().st_size, item.read_bytes
        return

    raise ValueError("Kaynak ZIP, XLSX veya klasör olmalıdır.")


def optimize_catalog(source: Path, output: Path, size: int, quality: int) -> dict:
    output.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() == output.resolve():
        raise ValueError("Çıktı dosyası kaynak dosyanın üzerine yazılamaz.")

    report = {
        "source": str(source.resolve()),
        "output": str(output.resolve()),
        "image_size": size,
        "jpeg_quality": quality,
        "excel_files": [],
        "optimized_images": 0,
        "skipped_files": [],
        "failed_images": [],
        "duplicate_barcodes": [],
        "source_bytes": source.stat().st_size if source.is_file() else 0,
        "output_bytes": 0,
    }
    seen_barcodes: set[str] = set()
    excel_found = False
    temporary = output.with_suffix(output.suffix + ".partial")
    temporary.unlink(missing_ok=True)

    try:
        with zipfile.ZipFile(
            temporary,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as target:
            for index, (name, file_size, read) in enumerate(iter_source(source), 1):
                suffix = name.suffix.lower()
                if suffix == ".xlsx":
                    target.writestr("urunler.xlsx", read())
                    report["excel_files"].append(str(name))
                    excel_found = True
                    continue
                if suffix not in IMAGE_EXTENSIONS:
                    report["skipped_files"].append(str(name))
                    continue
                barcode = name.stem.strip()
                if not barcode:
                    report["skipped_files"].append(str(name))
                    continue
                if barcode in seen_barcodes:
                    report["duplicate_barcodes"].append(str(name))
                    continue
                if file_size > MAX_SINGLE_IMAGE:
                    report["failed_images"].append(
                        {"file": str(name), "error": "100 MB görsel sınırı aşıldı"}
                    )
                    continue
                try:
                    optimized = optimize_image(read(), size, quality)
                    target.writestr(f"images/{barcode}.jpg", optimized)
                    seen_barcodes.add(barcode)
                    report["optimized_images"] += 1
                except (UnidentifiedImageError, OSError, ValueError) as error:
                    report["failed_images"].append(
                        {"file": str(name), "error": str(error)}
                    )
                if index % 100 == 0:
                    print(
                        f"İşleniyor: {index:,} dosya, "
                        f"{report['optimized_images']:,} görsel",
                        flush=True,
                    )

        if not excel_found:
            raise ValueError("Kaynakta Excel (.xlsx) dosyası bulunamadı.")
        os.replace(temporary, output)
        report["output_bytes"] = output.stat().st_size
        report_path = output.with_suffix(".rapor.json")
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return report
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--size", type=int, default=320)
    parser.add_argument("--quality", type=int, default=70)
    args = parser.parse_args()

    source = args.source or choose_source()
    if source is None:
        print("İşlem iptal edildi.")
        return 1
    source = source.expanduser().resolve()
    output = args.output or source.with_name(f"{source.stem}-optimize.zip")
    output = output.expanduser().resolve()
    if not 128 <= args.size <= 1024:
        parser.error("--size 128 ile 1024 arasında olmalıdır")
    if not 40 <= args.quality <= 95:
        parser.error("--quality 40 ile 95 arasında olmalıdır")

    print(f"Kaynak : {source}")
    print(f"Çıktı  : {output}")
    report = optimize_catalog(source, output, args.size, args.quality)
    before = report["source_bytes"] / (1024 * 1024)
    after = report["output_bytes"] / (1024 * 1024)
    print(f"Tamamlandı: {report['optimized_images']:,} görsel")
    if before > 0:
        print(f"Boyut: {before:,.1f} MB -> {after:,.1f} MB")
    else:
        print(f"Çıktı boyutu: {after:,.1f} MB")
    print(f"Rapor: {output.with_suffix('.rapor.json')}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"HATA: {error}", file=sys.stderr)
        raise SystemExit(2)
