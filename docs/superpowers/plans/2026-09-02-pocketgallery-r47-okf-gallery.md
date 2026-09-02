# PocketGallery R4.7 OKF Gallery — Implementation Plan

## Task 1 — RED contracts

Create R4.7 tests before implementation for canonical OKF parsing, trust/freshness classification, relative-link extraction, ordinary-Markdown compatibility, SQLite sidecar persistence, and SHADOW strategy registration/isolation. Run them in a branch-specific GitHub Actions workflow and record the expected failure because OKF implementation symbols do not exist yet.

## Task 2 — OKF domain + parser

Add `lib/okf/okf_models.dart` and `lib/okf/okf_parser.dart`. Use a YAML parser, normalize Dart/YAML collections into JSON-safe values, parse known v0.2 fields, preserve unknown frontmatter, extract relative Markdown links, and expose deterministic trust/freshness helpers. `parseMarkdown` is strict; `tryParseMarkdown` returns null for ordinary Markdown.

## Task 3 — Import and lineage persistence

Add optional OKF graph data to `LineageImportResult`. Detect OKF during Markdown import without changing section/chunk boundaries. Add `pg_okf_documents`, `pg_okf_links`, and `pg_okf_candidate_signals` tables plus read/write methods. Update `replaceImportLineage` to replace sidecar rows in the same transaction as document/section/chunk lineage.

## Task 4 — Explainable SHADOW strategy

Register `shadow.okf-v02-structured`. Build from the same body-hybrid candidates and captured query embedding as the ACTIVE control. Apply deterministic trust/freshness/link adjustments and persist `base_score`, components, `final_score`, and a human-readable reason. Preserve existing ACTIVE isolation checks.

## Task 5 — OKF Lab UI

Extend Experiment Center with a Chinese-first OKF Lab card presenting BARE / MARKDOWN / OKF arms. Show real counts and signals only; mark unavailable generation metrics as not run instead of inventing values. Expose trust/freshness/source/link summaries and links into existing microscope pages where practical.

## Task 6 — Integrated verification

Expand the R4.7 workflow to run formatting, analysis, targeted R4.7 tests, the full Flutter test suite, manifest integrity, debug APK and release APK builds. Fix failures in batches. Keep the branch stacked on `codex/r46-full-microscope`; open a draft PR after the integrated gate is green.
