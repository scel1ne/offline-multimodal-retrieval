# Retrieval Accuracy Benchmark Report

**Author:** Celine Song
**Document version:** 1.0
**Status:** Week 4 draft
**Last updated:** 2026-07-16

## 1. Scope

This report documents the Week 4 benchmark baseline for the local retrieval
pipeline. The current benchmark is a functional baseline, not a production
quality claim, because large model binaries are excluded from Git.

## 2. Benchmark Method

| Area | Method |
|---|---|
| Vector storage | Mock Chroma HTTP API validates request/response contracts |
| Ranking | Search results are sorted by blended vector score and keyword overlap |
| Snippets | Long extracted text is truncated to a stable 120-character preview |
| Failure handling | Chroma lookup and query failures produce controlled errors or empty search results |

## 3. Current Baseline

| Metric | Current result |
|---|---|
| Chroma upsert/query contract | Passing |
| Retrieval service ingest pipeline | Passing |
| Query embedding delegation | Passing |
| Hybrid keyword reranking | Passing |
| Missing collection / failed lookup handling | Passing |

## 4. Follow-Up Benchmark

After the production BERT and MobileCLIP assets are placed locally, the next
benchmark should run Natural Questions and COCO validation samples through the
real embedding engine and record top-k recall, mean latency, and qualitative
failure cases.
