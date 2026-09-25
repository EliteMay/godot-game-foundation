#!/usr/bin/env python3
import json
import shutil
import sys
from pathlib import Path


def safe_relative(value: str) -> Path:
    candidate = Path(value)
    if not value or candidate.is_absolute() or ".." in candidate.parts or "\\" in value:
        raise ValueError(f"unsafe relative path: {value}")
    return candidate


def godot_string(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: materialize_starter_fixture.py <empty-output-directory>", file=sys.stderr)
        return 2

    source_root = Path(__file__).resolve().parents[1]
    output_root = Path(sys.argv[1]).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    if any(output_root.iterdir()):
        raise RuntimeError("output directory must be empty")

    manifest = json.loads(
        (source_root / "foundation-template.json").read_text(encoding="utf-8")
    )

    game_name = "Foundation Starter CI"
    replacements = {
        "{{GAME_NAME}}": game_name,
        "{{GAME_NAME_GODOT}}": godot_string(game_name),
        "{{GAME_SLUG}}": "ci/foundation-starter",
        "{{FOUNDATION_VERSION}}": manifest["foundationVersion"],
    }

    for item in manifest["starterFiles"]:
        source_relative = safe_relative(item["source"])
        target_relative = safe_relative(item["target"])
        source = source_root / source_relative
        target = output_root / target_relative
        target.parent.mkdir(parents=True, exist_ok=True)

        if item.get("tokens") is True:
            text = source.read_text(encoding="utf-8")
            for token, replacement in replacements.items():
                text = text.replace(token, replacement)
            target.write_text(text, encoding="utf-8")
        else:
            shutil.copyfile(source, target)

    for value in manifest["managedPaths"]:
        relative = safe_relative(value)
        source = source_root / relative
        target = output_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, target)

    metadata = {
        "schemaVersion": 1,
        "sourceRepository": manifest["sourceRepository"],
        "foundationVersion": manifest["foundationVersion"],
        "foundationCommit": "0" * 40,
        "managedPaths": manifest["managedPaths"],
        "installedAt": "2026-01-01T00:00:00.000Z",
    }
    (output_root / ".game-foundation.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )

    print(output_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
