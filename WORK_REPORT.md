# Work Report

## v0.10.0-dev — Integrated Foundation Runtime

### 目的

Deep Factory固有開発をいったん保留し、新しいGodot Gameで使い回す共通Foundation自体を先に強化する。

### 実装

- `addons/game_foundation/runtime/foundation_runtime.gd`
  - Diagnostics初期化
  - Settings load / runtime apply
  - Gameplay settings adapter
  - Input binding restore / save
  - Scene flow setup
  - Save load / autosave / explicit save
  - Safe Quit save
  - Runtime Test Bridge接続
- Save Adapter
  - `capture_save_state`
  - `restore_save_state`
  - optional `migrate_save_state`
- Runtime Test中は通常Save writeを停止
- Load / Restore失敗後はSave writeをblock
- 明示Saveは最新PayloadでPending Autosaveを置換してflush
- Starter mainからFoundationRuntimeを初期化
- Foundation Versionを0.10.0-devへ更新
- Deep Factory PilotをRoadmap上で保留

### Automated Validation

- PR #4 Godot CI: PASS
- Direct cold start: PASS
- Godot import: PASS
- Existing Foundation smoke tests: PASS
- Integrated Foundation Runtime smoke: PASS
- Corrupt Save preservation regression: PASS
- Generated Starter materialize / import / main / integration smoke: PASS
- PR #4 Windows Build: PASS
- main Godot CI: PASS
- main Windows Build: PASS
- main merge commit: `a804b0cbb9f2331211e0f9fe51f34d8b9a16a299`

### 未確認

- Windows実機Starterで `Foundation v0.10.0-dev / Runtime ready` 表示
- 実GameでのGame-specific Save Adapter導入
- Deep Factory PilotはFoundation優先方針により保留


---

## 2026-09-28 Public Godot Template Research

### 調査対象

- Maaack/Godot-Game-Template
- ChristianWSmith/godot4-template
- LucasMcClean/godot-game-template
- bitbrain/godot-gamejam

4 RepositoryともMIT License。READMEだけでなく、Lifecycle / Save / Settings / Input / Scene Manager / Menu / Audio等の主要CodeとDocsを確認した。

### 結論

Current Foundationの強い部分:

- Atomic / Backup / Migrationを持つGeneric Save
- Settings / Input Backend
- FoundationRuntime Lifecycle
- Diagnostics
- Runtime Test Bridge
- Windows Build / Starter Distribution

不足している共通領域:

- Main / Pause / Options Shell
- Async Scene Loading / Loading progress / Transition
- Settings Apply / CancelとInput Remap UI
- BGM / SFX / UI Audio Service
- Save Slot / Continue / New Game
- Localization / Focus baseline
- Controlled Failure / Recovery UI

### Roadmap反映

- 重複していたPhase 9番号を整理
- Runtime Test Bridge → Phase 9
- Integrated Foundation Runtime → Phase 10
- Phase 11〜16をResearch結果から追加
- Deep Factory PilotはPhase 8のまま保留
- Event Bus / Player State Machine / Steam / Obfuscation等はCoreへ採用しない

### Source

Current decision summary: `docs/REFERENCE_TEMPLATES.md`
