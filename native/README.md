# Native Parser and Google Test Layer

The Flutter layer calls a platform channel named `local_parsers`.

Required native methods:

- `extractPdfTextWithPdfium(path)`: uses PDFium to extract text from PDFs.
- `extractDocumentTextWithTika(path)`: invokes Apache Tika for DOC/DOCX/PPT/XLS and other document formats.

The files in this folder define the expected native API and Google Test coverage target. Build wiring requires Flutter desktop platform folders and CMake, which are not available in the current terminal environment.

