#!/usr/bin/env python3
import sys

import pypdfium2 as pdfium


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: extract_pdfium.py <pdf-path>", file=sys.stderr)
        return 64

    document = pdfium.PdfDocument(sys.argv[1])
    pages = []
    for page in document:
        text_page = page.get_textpage()
        pages.append(text_page.get_text_range())
        text_page.close()
        page.close()

    print("\n".join(pages))
    document.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
