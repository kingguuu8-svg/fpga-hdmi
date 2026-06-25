import re
import sys
from pathlib import Path

import pdfplumber


PATTERN = re.compile(
    r"LED|P20|PL_LED|GPIO|USER|XC7Z020|CLK|OSC|CRYSTAL|KEY|BUTTON|D\d+|灯|按键",
    re.IGNORECASE,
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: extract_schematic_hits.py <schematic.pdf>", file=sys.stderr)
        return 2

    pdf_path = Path(sys.argv[1])
    with pdfplumber.open(str(pdf_path)) as pdf:
        print(f"pages {len(pdf.pages)}")
        for page_number, page in enumerate(pdf.pages, 1):
            text = page.extract_text() or ""
            lines = [
                line.strip()
                for line in text.splitlines()
                if PATTERN.search(line)
            ]
            if not lines:
                continue
            print(f"--- page {page_number}")
            for line in lines:
                print(line[:260])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
