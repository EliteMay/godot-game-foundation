# Project Structure

```text
godot-game-foundation/
├─ .github/
│  └─ workflows/
│     └─ godot-ci.yml
├─ addons/
│  └─ game_foundation/
│     ├─ foundation.gd
│     ├─ save/
│     │  ├─ save_system.gd
│     │  └─ auto_save_service.gd
│     ├─ settings/
│     │  ├─ settings_system.gd
│     │  └─ settings_runtime.gd
│     └─ input/
│        └─ input_system.gd
├─ demo/
│  └─ demo.tscn
├─ tests/
│  ├─ foundation_smoke.gd
│  ├─ foundation_smoke.tscn
│  ├─ save_system_smoke.gd
│  ├─ save_system_smoke.tscn
│  ├─ settings_system_smoke.gd
│  ├─ settings_system_smoke.tscn
│  ├─ input_system_smoke.gd
│  └─ input_system_smoke.tscn
├─ docs/
│  ├─ ARCHITECTURE.md
│  ├─ INTEGRATION.md
│  ├─ PROJECT_STRUCTURE.md
│  ├─ ROADMAP.md
│  ├─ SAVE_SYSTEM.md
│  ├─ SETTINGS_SYSTEM.md
│  └─ INPUT_SYSTEM.md
├─ project.godot
└─ README.md
```

## Addon本体

`addons/game_foundation/` だけを他Gameへ導入しても動作することを目標にする。

### save

- `save_system.gd` — Payload Validation / Version / Atomic Save / Load / Backup / Migration
- `auto_save_service.gd` — Game EventからのDebounce Save Request

### settings

- `settings_system.gd` — Common Schema / Normalize / Persistence / Backup / Reset
- `settings_runtime.gd` — Audio / DisplayのRuntime適用

### input

- `input_system.gd` — Action Contract / Rebind / Default / Event Codec / Binding Persistence

## Demo

Foundationの機能を目視確認するためのHarness。実GameはDemoへ依存しない。

## Tests

Foundation SystemはMain Scene LoadだけでなくBehavior Smoke Testで守る。

現在:

- Foundation metadata / capability
- Generic Save System
- Settings System
- Input System

## 今後追加する予定

```text
addons/game_foundation/
├─ flow/
└─ diagnostics/
```

Game固有CodeはこのRepositoryへ追加しない。
