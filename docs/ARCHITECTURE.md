# Architecture

## 目的

Godot Game Foundationは、特定ゲームのDomain Logicから独立した再利用基盤を提供する。

Foundationを導入したゲームが、Foundation側の都合に合わせてゲーム設計を変えなくてもよい構造を優先する。

## 3層構成

```text
Game Dev Hub
  └─ 開発・Repository・実機確認・共有を管理

Godot Game Foundation
  └─ Save / Settings / Input / Flow / Diagnostics / Test / Build

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
├─ save/
├─ settings/
├─ input/
├─ flow/
└─ diagnostics/
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
