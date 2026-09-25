# Integration

## 現在

Foundation Core、Generic Save System、Settings System、Input System、Game Flow、Diagnostics、Windows Buildまで完成している。次はStarter Template / Game Dev Hub連携を行い、その後Deep FactoryへのPilot導入へ進む。Game Adapterと各SystemのContractを介し、Game固有仕様をFoundationへ混ぜない。

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

Phase 7で **Game Dev HubによるManaged Path Copy** に決定した。

- 新規Game生成時は `foundation-template.json` に従ってStarter Fileと `addons/game_foundation/` をCopyする
- 生成Gameへ `.game-foundation.json` を置き、Foundation Version / Commit / Managed Pathを記録する
- Foundation更新では `addons/game_foundation/` だけを更新する
- Game固有のProject設定、Roadmap、Scene、Script、Assetは自動上書きしない
- 更新後のCommit / PushはGame Dev Hub既存の明示「GitHubに保存」Flowへ任せる

Git submodule / subtreeはDefaultにしない。初心者向けHubのPrimary Flowへ追加のGit概念を持ち込まず、管理領域をManifestで明示できることを優先した。

詳細は `docs/STARTER_TEMPLATE.md` を参照する。

## Deep Factory Pilot

Foundation側でSave / Settings / Input / Flowの主要基盤が揃った後、Deep FactoryへPilot導入する。

その際、Deep Factoryで既に確認済みのGameplay Loopを壊していないことをRegression TestとWindows実機で確認する。
