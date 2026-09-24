# Integration

## 現在

Foundation Core、Generic Save System、Settings Systemまで完成しているが、Input / Flowが揃うまでは実ゲームへの全面導入は開始しない。Save / Settingsだけを先行評価する場合もGame Adapterを介し、FoundationへGame固有Fieldを追加しない。

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
