# Project Structure

```text
godot-game-foundation/
├─ .github/
│  └─ workflows/
│     └─ godot-ci.yml
├─ addons/
│  └─ game_foundation/
│     ├─ foundation.gd
│     └─ save/
│        ├─ save_system.gd
│        └─ auto_save_service.gd
├─ demo/
│  └─ demo.tscn
├─ tests/
│  ├─ foundation_smoke.gd
│  ├─ foundation_smoke.tscn
│  ├─ save_system_smoke.gd
│  └─ save_system_smoke.tscn
├─ docs/
│  ├─ ARCHITECTURE.md
│  ├─ INTEGRATION.md
│  ├─ PROJECT_STRUCTURE.md
│  ├─ ROADMAP.md
│  └─ SAVE_SYSTEM.md
├─ project.godot
└─ README.md
```

## Addon本体

`addons/game_foundation/` だけを他Gameへ導入しても動作することを目標にする。

### save

- `save_system.gd` — Payload Validation / Version / Atomic Save / Load / Backup / Migration
- `auto_save_service.gd` — Game EventからのDebounce Save Request

## Demo

Foundationの機能を目視確認するためのHarness。実GameはDemoへ依存しない。

## Tests

Foundation SystemはMain Scene LoadだけでなくBehavior Smoke Testで守る。

現在:

- Foundation metadata / capability
- Generic Save System

## 今後追加する予定

```text
addons/game_foundation/
├─ settings/
├─ input/
├─ flow/
└─ diagnostics/
```

Game固有CodeはこのRepositoryへ追加しない。
