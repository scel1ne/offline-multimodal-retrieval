# Curated Local Dataset Repository

## Included Fixtures

- `fixtures/notes.txt`: keyword and semantic text retrieval fixture.
- `fixtures/accessibility.md`: accessibility-focused retrieval fixture.

## Required External Validation Datasets

These are listed for production validation and should be downloaded only when network access and storage are approved.

| Dataset | Use |
| --- | --- |
| Natural Questions | Text embedding validation and long-document retrieval |
| COCO | Image embedding and multimodal retrieval validation |
| RVL-CDIP | Scanned document and OCR retrieval validation |
| Wikipedia Text Corpus | Batch processing and long-form retrieval benchmarking |

## Curation Rules

- Keep raw datasets outside source control if large.
- Store only small representative fixture files in the repository.
- Record dataset license and download date.
- Separate train, validation, and benchmark subsets.
