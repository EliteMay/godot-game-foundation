# Integration

## 現在

Foundation Core、Generic Save System、Settings System、Input System、Game Flow、Diagnosticsまで完成している。次にWindows Buildを整え、その後Starter Template / Game Dev Hub連携を行ってからDeep FactoryへのPilot導入へ進む。Game Adapterと各SystemのContractを介し、Game固有仕様をFoundationへ混ぜない。

Deep FactoryはPilot Gameとして後から使用する。

## 将来の導入形

最終的にはGame Dev Hubから次の流れを目標にする。

```text
新しいゲームを作成
  ↓
Godot Game FoundationをStarterとして選択
  ↓
Repository生成
  ↓
Foundation Core + Test + CIを準備
  ↓
ゲーム固有実装を開始
```

既存Gameへ導入する場合も、FoundationとGame固有Codeの境界を保つ。

## 更新方式

Foundationを各Gameへどう配布・更新するかは、以下を比較してStarter Template Phaseで決定する。

- Repository Templateとしてコピー
- `addons/game_foundation/` の同期
- Git subtree
- Git submodule
- Game Dev HubによるFoundation Update

更新の簡単さ、初心者でも扱えること、Gameごとの改変混入を防げることを優先する。

## Deep Factory Pilot

Foundation側でSave / Settings / Input / Flowの主要基盤が揃った後、Deep FactoryへPilot導入する。

その際、Deep Factoryで既に確認済みのGameplay Loopを壊していないことをRegression TestとWindows実機で確認する。
