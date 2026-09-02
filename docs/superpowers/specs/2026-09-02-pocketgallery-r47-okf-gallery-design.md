# PocketGallery R4.7 — OKF Gallery SHADOW Lab Design

Date: 2026-09-02
Baseline: `codex/r46-full-microscope@073e921f06e5d857f810e36a580ee71ba8ce716d`
Target branch: `codex/r47-okf-gallery`
Canonical OKF reference: GoogleCloudPlatform/open-knowledge-format, OKF v0.2

## Goal

Integrate Open Knowledge Format v0.2 into PocketGallery as a structured knowledge/provenance sidecar while preserving the existing R4.6 `PgChunk -> FTS5 -> Embedding -> Hybrid -> Evidence` production path. OKF must be observable to humans and experimentally comparable without changing ACTIVE retrieval.

## Non-negotiable invariants

1. `PgChunk` stays the production retrieval unit; OKF metadata is sidecar state keyed by `document_id`.
2. Existing TXT/MD/PDF import behavior remains compatible.
3. ACTIVE strategy `active.r45-body-hybrid` is never modified by R4.7 experiments.
4. OKF retrieval is SHADOW-only until regression, benchmark, phone-golden, upgrade and signing gates pass and the user explicitly promotes it.
5. The same captured query embedding and representation model identity are reused across control and OKF SHADOW experiments.
6. UI must explain decisions with human-readable type, trust, freshness, source and link signals rather than opaque IDs.

## Import architecture

`DocumentImporter` continues parsing Markdown into sections/chunks. For Markdown only, `OkfParser.tryParseMarkdown` inspects YAML frontmatter. A document is treated as OKF only when frontmatter contains the mandatory `type` key. Ordinary Markdown, including Markdown without OKF `type`, remains ordinary Markdown.

The importer returns the existing `LineageImportResult` plus an optional `OkfParseResult`. `LineageStore.replaceImportLineage` persists both graphs transactionally:

- `pg_okf_documents`: type/title/trust/status/stale_after/superseded_by/actors/sources/frontmatter
- `pg_okf_links`: Markdown relation label and relative target

No OKF metadata is copied into `PgChunk`.

## OKF v0.2 semantics in R4.7

Supported structured signals:

- mandatory `type`
- `verified` actors
- `generated` actors
- `sources` with location/pin/role/license(s)/retrieved_at/content_sha256
- `status`, `stale_after`, `superseded_by`
- standard relative Markdown links as semantic edges
- attested-computation frontmatter is preserved in raw frontmatter for inspection even when not used in ranking

Trust tiers are deterministic: VERIFIED > GENERATED > PROVENANCE > TYPE_ONLY.
Freshness is deterministic at an explicit clock: DEPRECATED > STALE > FRESH/UNKNOWN.

## SHADOW retrieval experiment

Add strategy `shadow.okf-v02-structured`. It starts from the same body-hybrid candidate pool and query vector as control, then applies explainable OKF-only adjustments:

- verified trust boost
- generated/provenance smaller trust boost
- stale/deprecated penalty
- bounded internal-link-density boost

Every adjustment is persisted per candidate in a dedicated OKF signal table so the UI can show both the base fusion score and OKF adjustment. The strategy remains `RetrievalLane.shadow` and the existing ACTIVE-isolation assertion stays mandatory.

## Three-arm lab contract

The OKF Lab presents three fixed arms for the same trace:

- BARE MODEL: no retrieved evidence/context; establishes zero-retrieval baseline metadata.
- MARKDOWN CONTROL: existing ACTIVE body-hybrid result, read-only.
- OKF v0.2: `shadow.okf-v02-structured`, on-demand and isolated.

R4.7 first makes retrieval/context differences measurable. Generation-quality scoring can only be compared when the same local model is available; the UI must not fabricate answer quality when generation has not run.

## UI

Extend Experiment Center with an `OKF Lab` section. It must show:

- arm/lane/status
- candidate and evidence counts
- context/evidence token counts when available
- OKF document count in current scope
- trust and freshness summary
- per-candidate reasons such as `verified +0.060`, `stale -0.120`, `links +0.010`
- direct navigation to existing candidate/evidence/lineage/vector microscopes where available

All labels exposed to the user should be bilingual or Chinese-first and avoid raw machine-only payloads unless the user drills into technical detail.

## Safety and compatibility

- unknown OKF fields are preserved, not rejected
- malformed explicit OKF parsing fails closed with an actionable parse error
- normal Markdown does not become OKF merely because it has YAML frontmatter
- existing SQLite databases upgrade with CREATE TABLE IF NOT EXISTS; no destructive migration
- no network service is required for parsing or ranking
- no remote LLM is introduced

## Acceptance gates

1. RED tests fail before OKF implementation exists.
2. Parser/import/store/signal/strategy/UI tests pass.
3. Existing R4.6/R5.0 regression suite passes.
4. `flutter analyze` passes.
5. Android debug and release APK builds pass.
6. ACTIVE candidate/evidence rows are byte-for-byte/logically unchanged by OKF SHADOW execution.
7. The new branch remains stacked on R4.6 until the baseline merges.
