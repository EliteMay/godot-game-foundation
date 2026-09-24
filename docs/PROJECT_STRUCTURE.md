# Project Structure

```text
godot-game-foundation/
├─ .github/
│  └─ workflows/
│     └─ godot-ci.yml
├─ addons/
│  └─ game_foundation/
│     └─ foundation.gd
├─ demo/
│  └─ demo.tscn
├─ tests/
│  ├─ foundation_smoke.gd
│  └─ foundation_smoke.tscn
├─ docs/
│  ├─ ARCHITECTURE.md
│  ├─ INTEGRATION.md
│  ├─ PROJECT_STRUCTURE.md
│  └─ ROADMAP.md
├─ project.godot
└─ README.md
```

## 今後追加する予定

```text
addons/game_foundation/
├─ save/
├─ settings/
├─ input/
├─ flow/
└─ diagnostics/
```

Game固有CodeはこのRepositoryへ追加しない。
