# Project Structure

```text
godot-game-foundation/
├─ .github/
│  └─ workflows/
│     ├─ godot-ci.yml
│     └─ windows-build.yml
├─ addons/
│  └─ game_foundation/
│     ├─ foundation.gd
│     ├─ save/
│     │  ├─ save_system.gd
│     │  └─ auto_save_service.gd
│     ├─ settings/
│     │  ├─ settings_system.gd
│     │  └─ settings_runtime.gd
│     ├─ input/
│     │  └─ input_system.gd
│     ├─ flow/
│     │  └─ game_flow_service.gd
│     └─ diagnostics/
│        ├─ runtime_info.gd
│        ├─ diagnostics_service.gd
│        └─ diagnostics_overlay.gd
├─ starter/
│  ├─ project.godot.template
│  ├─ README.md.template
│  ├─ scenes/
│  ├─ scripts/
│  ├─ tests/
│  └─ docs/
├─ foundation-template.json
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
│  ├─ input_system_smoke.tscn
│  ├─ game_flow_smoke.gd
│  ├─ game_flow_smoke.tscn
│  ├─ diagnostics_smoke.gd
│  ├─ diagnostics_smoke.tscn
│  ├─ build_config_smoke.gd
│  ├─ build_config_smoke.tscn
│  ├─ starter_template_smoke.gd
│  └─ starter_template_smoke.tscn
├─ docs/
│  ├─ ARCHITECTURE.md
│  ├─ INTEGRATION.md
│  ├─ PROJECT_STRUCTURE.md
│  ├─ ROADMAP.md
│  ├─ SAVE_SYSTEM.md
│  ├─ SETTINGS_SYSTEM.md
│  ├─ INPUT_SYSTEM.md
│  ├─ GAME_FLOW.md
│  ├─ DIAGNOSTICS.md
│  ├─ WINDOWS_BUILD.md
│  └─ STARTER_TEMPLATE.md
├─ export_presets.cfg
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

### flow

- `game_flow_service.gd` — Pause / Scene Contract / Main Menu / Safe Quit

### diagnostics

- `runtime_info.gd` — App / Foundation / Godot / OS Runtime情報
- `diagnostics_service.gd` — Log / Error Summary / Snapshot / Path情報
- `diagnostics_overlay.gd` — 開発用Dark Debug Overlay

## Demo

Foundationの機能を目視確認するためのHarness。実GameはDemoへ依存しない。

## Tests

Foundation SystemはMain Scene LoadだけでなくBehavior Smoke Testで守る。

現在:

- Foundation metadata / capability
- Generic Save System
- Settings System
- Input System
- Game Flow
- Diagnostics
- Windows Build Config

## 今後追加する予定

Core Runtime SystemとWindows Buildは実装済み。Starter配布Contractも実装済みで、Game Dev Hub連携を進める。

Game固有CodeはこのRepositoryへ追加しない。
