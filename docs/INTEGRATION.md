# Integration

## 現在

Foundation Core、Generic Save System、Settings System、Input System、Game Flow、Diagnostics、Runtime Test Bridge、Windows Build、Starter Template / Game Dev Hub連携まで実装済み。v0.10.0-devでは、それらをGameごとに毎回手配線しなくてよいようFoundationRuntimeを追加した。Game Adapterと各SystemのContractを介し、Game固有仕様をFoundationへ混ぜない。

Deep FactoryはPilot Gameとして後から使用する。現在はFoundation自体の完成度を優先し、Deep Factory固有開発は保留する。

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


## FoundationRuntimeを使う新規Game

新規GameではFoundationRuntimeをLifecycle Coordinatorとして使い、必要なSystemだけ有効化する。

```gdscript
const FoundationRuntime = preload(
    "res://addons/game_foundation/runtime/foundation_runtime.gd"
)

var foundation_runtime := FoundationRuntime.new()
add_child(foundation_runtime)

foundation_runtime.configure(
    {
        "save": {
            "enabled": true,
            "game_schema_version": 1,
        },
        "settings": {
            "gameplay_defaults": {
                "mouse_sensitivity": 0.0025,
            },
        },
        "input": {
            "contract": INPUT_CONTRACT,
        },
        "flow": {
            "scenes": SCENE_CONTRACT,
            "main_menu_id": "menu",
        },
    },
    {
        "capture_save_state": Callable(self, "build_save_payload"),
        "restore_save_state": Callable(self, "restore_save_payload"),
        "apply_gameplay_settings": Callable(self, "apply_gameplay_settings"),
        "runtime_test_state": Callable(self, "build_runtime_test_state"),
    }
)

var result := foundation_runtime.initialize()
```

Save PayloadのField、Gameplay Settingの意味、Input Action名、Scene ID、Runtime Testへ公開するStateはGame側が所有する。
