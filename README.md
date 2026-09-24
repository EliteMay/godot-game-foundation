# Godot Game Foundation

**Godot Game Foundation** は、複数のGodotゲームで繰り返し使う基盤機能を共通化するためのRepositoryです。

特定ジャンルのゲームを作るRepositoryではありません。採掘・戦闘・敵・武器・工場・クエストなどのゲーム固有機能は各ゲーム側へ残し、Save / Settings / Input / Game Flow / Diagnostics / Testing / Windows Buildなど、ジャンルに依存しない部分をここで育てます。

## 目的

新しいゲームを作るたびに、次の機能をゼロから作り直さない状態を目指します。

- Save / Load
- Save Version / Migration / Backup
- Settings
- Input / Key Rebind
- Pause / Scene Flow
- Logging / Diagnostics
- Test基盤
- Windows Export / CI
- Game Dev Hubから使えるStarter Template

## 境界

### Foundationへ入れるもの

ゲームジャンルに依存せず、複数Projectで再利用できる仕組み。

### 各ゲームへ残すもの

- ゲーム固有のルール
- ゲーム固有データ
- ゲーム固有UI
- 敵、武器、採掘、工場などのDomain Logic
- Balance値

Foundationは「何を保存するか」「何をPauseするか」のようなゲーム固有判断を勝手に持たず、各ゲームから渡された情報を安全に扱う責務を持ちます。

## 構成方針

再利用コードは `addons/game_foundation/` 配下へ置きます。

Repository直下のGodot ProjectはFoundation自体を開発・検証するためのHarnessです。各ゲームは将来的にFoundationをStarter Templateとして生成するか、`addons/game_foundation/` を導入して利用します。

```text
godot-game-foundation/
├─ addons/game_foundation/   # 再利用する本体
├─ demo/                     # 開発・目視確認用
├─ tests/                    # FoundationのSmoke / Regression Test
├─ docs/                     # Architecture / Roadmap / Integration
├─ project.godot             # Foundation開発用Harness
└─ README.md
```

## 開発環境

- Engine: Godot 4.7.2 stable
- Language: GDScript
- Primary target: Windows
- Version control: Git / GitHub
- CI: GitHub Actions

当面はDeep Factoryと同じGodot 4.7.2 stableを基準にし、実際のゲームへ導入して問題がないことを確認しながらFoundationを更新します。

## 重要な設計ルール

- Game固有の名前やデータ構造をFoundationへ埋め込まない
- Static Game DefinitionとRuntime Save Dataを分離する
- Editorのglobal class cacheが無くてもDirect Cold Startできる依存方法にする
- Main Sceneが開くだけでなく、主要SystemはBehavior Smoke Testで検証する
- Godot logに `SCRIPT ERROR` / `ERROR:` が出た場合はCIを失敗させる
- 破壊的なSave変更にはVersion / Migration方針を持たせる
- Foundationを巨大Frameworkにせず、必要なSystemを独立して使える構造を優先する

## Roadmap

詳細は `docs/ROADMAP.md` をSource of Truthとします。

大枠:

1. Foundation / Architecture
2. Save System
3. Settings System
4. Input System
5. Game Flow
6. Diagnostics
7. Windows Build
8. Starter Template / Game Dev Hub連携
9. Deep Factoryで実利用検証

## 現在の状態

Phase 0 — Foundation / Architecture、Phase 1 — Generic Save System、Phase 2 — Settings System、Phase 3 — Input System、Phase 4 — Game Flowが完了しています。次はPhase 5 — Diagnosticsです。

Deep Factory側はPhase 5までを実機確認済みの基準Projectとして残し、Foundationが必要な機能を持った段階でPilot導入します。
