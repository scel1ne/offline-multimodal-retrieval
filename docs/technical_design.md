# Technical Design Document

## Design Principles

- Offline by default.
- Modular parser, feature, storage, retrieval, and UI layers.
- Replaceable local feature extractors so production embeddings can be introduced without rewriting UI workflows.
- Accessible controls as first-class product requirements.

## Submitted Application Components

- `lib/src/ui/home_screen.dart`: Flutter UI shell with accessible controls, high contrast mode, font scaling, local indexing, result highlighting, and export/import.
- `lib/src/parsing/local_content_parser.dart`: local parser orchestration for text, DOCX, PDF, image metadata, and native document bridges.
- `macos/Runner/MainFlutterWindow.swift`: macOS PDFKit/PDFium/Tika platform-channel integration.

## Parser Design

The strict Flutter parser supports plain text directly, DOCX through zipped XML extraction, PDF through the `extractPdfTextWithPdfium` platform channel, and other document formats through the `extractDocumentTextWithTika` platform channel. Image files are routed to the MobileCLIP TensorFlow Lite embedding path.

## Retrieval Design

Ranking combines:

- Keyword overlap.
- Sparse vector cosine similarity.
- Filename boost.
- Image color palette boost.

## Storage Design

The strict Flutter implementation uses Chroma DB through the local HTTP API. The built macOS app also supports local JSON export/import for portable offline review.
