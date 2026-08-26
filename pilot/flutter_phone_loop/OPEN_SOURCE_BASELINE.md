# Open-source assembly baseline

Frozen for PocketGallery Phone Pilot R1 (2026-08-26):

- Google AI Edge Gallery upstream concept/base:
  - `google-ai-edge/gallery`
  - PocketGallery pinned baseline commit:
    `ec7fee19e3b7aad9991105e549d544233ea0b97f`
- Flutter Gemma source inspected:
  - `DenisovAV/flutter_gemma`
  - commit:
    `e45cf737f0c78ba700275cc55e10240cc81c1ab5`
  - core 1.6.5
  - flutter_gemma_litertlm 1.5.2
  - flutter_gemma_rag_sqlite 1.2.0
- pdfrx source inspected:
  - `espresso3389/pdfrx`
  - commit:
    `762662347aba9f26345cc81fba182d5ccf09a318`
- SQLite FTS5:
  - `sqlite3` package, FTS5 virtual table with trigram tokenizer.
- PocketGallery native mainline remains:
  - `QuJindai/PocketGallery`
  - main observed at:
    `ea3d8c4496183137744c1c573fa17bb95a302682`

No third-party source code is vendored in this pilot. Dependencies are consumed as packages.
