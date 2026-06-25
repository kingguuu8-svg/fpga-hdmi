import sys
from pathlib import Path

import pypdfium2 as pdfium


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: render_pdf_pages.py <pdf> <output-dir> <page> [<page>...]", file=sys.stderr)
        return 2

    pdf_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    pdf = pdfium.PdfDocument(str(pdf_path))
    try:
        for page_arg in sys.argv[3:]:
            page_number = int(page_arg)
            page = pdf[page_number - 1]
            bitmap = page.render(scale=2).to_pil()
            out = output_dir / f"{pdf_path.stem}-page-{page_number}.png"
            bitmap.save(out)
            print(out)
    finally:
        pdf.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
