# Architecture

## 目的

Godot Game Foundationは、特定ゲームのDomain Logicから独立した再利用基盤を提供する。

Foundationを導入したゲームが、Foundation側の都合に合わせてゲーム設計を変えなくてもよい構造を優先する。

## 3層構成

```text
Game Dev Hub
  └─ 開発・Repository・実機確認・共有を管理

Godot Game Foundation
  └─ Save / Settings / Input / Flow / Diagnostics / Runtime Test Bridge / Optional Shell / Build

Game Repository
  └─ Gameplay / Content / Balance / Game-specific UI
```

## Repository内の責務

### addons/game_foundation

他Projectへ持ち込める再利用コードだけを置く。

禁止:
- Deep Factoryなど特定ゲーム名への依存
- 鉱石、武器、敵など固有Domainの型
- 特定Scene Tree構成の強制
- Balance値の直書き

### demo

Foundationの機能を目視確認するためのHarness。

実際のゲームがdemo Sceneへ依存してはいけない。

### tests

Foundation単体で再現できるSmoke / Regression Test。

実ゲームに導入する前に、少なくとも次を守る。

- Direct Cold Start
- Import
- Main Scene Load
- System Behavior Smoke Test
- Godot log error detection

## 依存方針

Godot Editorのglobal class cacheへ起動可否を依存させない。

Runtime EntryからFoundation Scriptを参照する場合は、必要に応じて明示Pathの `preload()` / `load()` を使う。

## System設計

各Systemは可能な限り独立させる。

予定:

```text
addons/game_foundation/
├─ foundation.gd
├─ runtime/
├─ save/
├─ settings/
├─ input/
├─ flow/
├─ diagnostics/
├─ testing/
└─ shell/
```

System同士を強く結合させず、ゲーム側が必要なSystemだけ利用できる形を目指す。

## Game Adapter

Foundationがゲーム固有状態を直接探索する方式は避ける。

例えばSave Systemは「money」「inventory」の存在を知るのではなく、ゲーム側がJSON互換Payloadを渡す。

```text
Game Runtime State
      ↓ serialize
Game Adapter / Provider
      ↓ Dictionary
Foundation Save System
      ↓
Validation / Version / Backup / Disk
```

Load時は逆方向にPayloadをゲーム側へ返す。

これによりFactory Game、Action Game、RPGなどで同じSave基盤を利用できる。

## 互換性

最初はGodot 4.7.2 stableをBaselineとする。

Godot Versionを上げる場合は、Foundation CIとPilot Gameの両方で確認してからBaselineを変更する。


## Runtime Test Bridge

固定テストでScreenshot VisionをPrimary verifierにせず、Game内部StateをDeterministicに比較するための開発用Adapterです。

```text
Game Runtime State
      ↓ JSON-compatible provider
Runtime Test Bridge
      ↓ local state.json
Game Dev Hub
      ↓ deterministic input + before/after compare
PASS / FAIL / UNKNOWN
```

BridgeはNetwork Listenerや任意Command実行を提供しません。Hubが明示的なTest起動Argumentを付けた時だけ有効になり、通常Playでは無効です。

Game固有のPosition / Inventory / Camera / Machine State等を何まで公開するかは各Game Repositoryが決めます。FoundationはField名を固定しません。


## Integrated Foundation Runtime

`runtime/foundation_runtime.gd` は各Systemを置き換える巨大Frameworkではなく、既存の独立Serviceを安全な順序で初期化するLifecycle Coordinatorです。

```text
Game Adapter / Contract
        ↓
FoundationRuntime
        ├─ Diagnostics
        ├─ Settings load / runtime apply
        ├─ Input binding restore
        ├─ Game Flow setup
        ├─ Save load / autosave / safe quit
        └─ Runtime Test Bridge
```

Game固有DataはRuntimeへ埋め込みません。Saveでは `capture_save_state` / `restore_save_state`、Game固有Settingでは `apply_gameplay_settings`、Runtime Testでは `runtime_test_state` のCallableをGame側が渡します。

Save Load/Restore失敗時は既存Canonical Saveを守るため、Runtimeは以後のSave writeをblockします。明示Test RunでRuntime Test Bridgeが有効な間も通常Saveへのwriteを行いません。

各Systemは従来どおり単独利用可能です。FoundationRuntimeは「全部使うこと」を強制せず、ConfigでSystem単位に有効/無効を選べます。


## Optional Application Shell

`shell/` はMain / Pause / Loading等のGame-ready UXを構成するためのOptional Moduleを置く領域です。

Core RuntimeへGame固有Visual Themeを埋め込まず、必要なGameだけが明示的にNode / Sceneを利用します。

最初のModuleである `shell/transition_layer.gd` は全画面Fadeを提供し、duration / color / motion scale / CanvasLayerをGame側から設定できます。Reduced motion preferenceそのものはFoundationで固定せず、Game側または後続Accessibility Shellから値を渡します。
