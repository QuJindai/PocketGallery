# PocketGallery OKF Mobile Lab

## Purpose

This branch adds an isolated on-device experiment for measuring how much a fixed local model benefits from progressively richer knowledge organization. It does **not** change the ACTIVE PocketGallery retrieval path.

The six lanes are:

- A: bare local model, no external evidence.
- B: ordinary lexical chunks containing the same facts.
- C: OKF concept retrieval.
- D: OKF passage retrieval.
- E: passage retrieval plus bounded one-hop graph expansion.
- F: graph retrieval plus OKF lifecycle/freshness filtering and derived trust-tier reranking.

The built-in `FR-Test-20260901` corpus is intentionally fictional so benchmark improvement cannot be explained by public pre-training data.

## OKF semantics implemented in the first Android slice

Read-only support covers the v0.2 fields required for the experiment: `type`, `title`, `description`, `tags`, `sources`, `generated`, `verified`, `status`, `stale_after`, standard Markdown links, concept IDs, trust-tier derivation, lifecycle filtering, passage projection and bounded graph traversal.

This first APK deliberately uses a small Dart implementation behind an isolated lab surface. It does not add a Rust/Go/Ruby/Node runtime to the Android application. If the experiment validates the value, the same interface can be backed by a native Rust `okf-core` implementation later.

## Open-source references

Architecture and behavior were checked against these upstream projects; no source code was copied into the Dart implementation.

- GoogleCloudPlatform/open-knowledge-format — canonical OKF v0.2 specification, Apache-2.0; reviewed around commit `ad30107c31c06aec8a7d5636e0d1058118604e6f`.
- W4G1/okf — pure-Rust OKF core/validator/studio, Apache-2.0; reviewed at `1866b191993504b5da4ce9424d7c2b7f88aad9e5`.
- cwest/okfctl — Go authoring/search/graph and offline semantic-search design, Apache-2.0; reviewed at `9b5e6ecf6efdc7939ef2734b047c8b715d3031e5`.
- serradura/okf — local search/graph/MCP/TUI reference implementation, Apache-2.0; reviewed at `7b23571f0a3d5f5021d2e981bb4699f59b8de008`.
- langchain-ai/openwiki — OKF v0.2 knowledge producer and Grounded Claims reference, MIT; reviewed at `17c61220672a05811406fe5961929a4adb2568f5`.

## Interpretation rules

- Retrieval time shown by the app is measured locally for that lane.
- Generation time is total local generation duration, **not TTFT**.
- `PASS/FAIL` for answer content uses deterministic expected fragments for the synthetic benchmark.
- Source PASS requires the model to cite evidence whose OKF `sources[].id` covers the expected source set.
- Graph expansion is auxiliary; it is capped to one hop and cannot recursively flood the model context.
- Deprecated or stale concepts are only filtered in lane F, so B–E remain useful controls for isolating the value of lifecycle metadata.
