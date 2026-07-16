# Retrieval Functional Test Report

**Author:** Celine Song
**Document version:** 1.0
**Status:** Week 4 draft
**Last updated:** 2026-07-16

## 1. Scope

This report supports the Week 4 vector database integration and core retrieval
logic deliverable.

## 2. Validated Flow

The committed tests cover the core pipeline:

1. Parse a local file into `ParsedContent`.
2. Generate a local embedding through `TfliteEmbeddingEngine`.
3. Convert the parsed content into an `IndexedItem`.
4. Upsert the item into `ChromaVectorStore`.
5. Embed a text query.
6. Query Chroma and return ranked `SearchResult` values.
7. Re-rank vector results with keyword overlap for hybrid retrieval.

## 3. Test Evidence

Command:

```bash
HOME="$PWD/.home" PUB_CACHE="$PWD/.pub-cache" \
  .tooling/flutter/bin/flutter test \
  test/chroma_vector_store_test.dart \
  test/retrieval_service_test.dart \
  --no-pub
```

Result on 2026-07-16: **8 tests passed**.

## 4. Notes

The Chroma tests use a local loopback HTTP server mock so the suite remains
offline and deterministic. A real Chroma process is still required for manual
end-to-end validation against a persistent local vector database.
