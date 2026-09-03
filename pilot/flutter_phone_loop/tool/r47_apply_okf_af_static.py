from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:100]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


root = Path(__file__).resolve().parents[1]
runner = root / "lib/okf/okf_af_runner.dart"
core = root / "lib/okf/okf_af_benchmark.dart"

runner_text = runner.read_text(encoding="utf-8")
if "import '../core/evidence.dart';" not in runner_text:
    replace_once(
        runner,
        "import '../core/models.dart';\n",
        "import '../core/evidence.dart';\nimport '../core/models.dart';\n",
    )

replace_once(
    core,
    """  OkfAfCorpus._({
    required this.concepts,
    required this.ordinaryChunks,
  });

  final Map<String, _AfConcept> concepts;
  final List<_AfOrdinaryChunk> ordinaryChunks;
""",
    """  OkfAfCorpus._({
    required this._concepts,
    required this._ordinaryChunks,
  });

  final Map<String, _AfConcept> _concepts;
  final List<_AfOrdinaryChunk> _ordinaryChunks;
""",
)

text = core.read_text(encoding="utf-8")
if "corpus.concepts" not in text or "corpus.ordinaryChunks" not in text:
    raise SystemExit("A-F corpus access contract changed")
text = text.replace("corpus.concepts", "corpus._concepts")
text = text.replace("corpus.ordinaryChunks", "corpus._ordinaryChunks")
core.write_text(text, encoding="utf-8")

print("A-F static fixes applied")
