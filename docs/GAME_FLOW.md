# Game Flow

## 目的

Pause、Scene切替、Main Menuへの移動、安全な終了前処理を、Game固有Scene名へ依存せず共通化する。

Foundationは「どのSceneがMenuか」「どのSceneがGameplayか」を固定しない。Game側がLogical IDとScene PathのContractを渡す。

## Service

`GameFlowService` はNodeとしてSceneTreeへ追加して利用する。

```gdscript
const GameFlowService = preload(
    "res://addons/game_foundation/flow/game_flow_service.gd"
)

var flow := GameFlowService.new()
add_child(flow)
```

Service自身は `PROCESS_MODE_ALWAYS` で動作するため、GameをPauseした後もResumeやSafe Quit処理を呼べる。

## Scene Contract

```gdscript
flow.configure_scene_contract(
    {
        "menu": "res://scenes/menu.tscn",
        "game": "res://scenes/game.tscn",
        "credits": "res://scenes/credits.tscn"
    },
    "menu"
)
```

Logical IDはGameが自由に決める。

Foundationは `main_menu` や `gameplay` という固定名を要求しない。

Scene Pathは `res://...tscn` に限定する。

## Scene Transition

```gdscript
flow.change_scene("game")
```

処理:

1. ContractにScene IDがあるか確認
2. PackedSceneとしてLoadできるか確認
3. Pause中なら解除
4. `SceneTree.change_scene_to_file()` を呼ぶ

実際のFade AnimationやLoading ScreenはGameの見た目に依存するためCoreへ固定しない。将来必要になった場合はTransition Presentationを別Layerとして追加する。

## Main Menu Contract

Gameが `configure_scene_contract()` の第2引数へMenuのLogical IDを渡した場合:

```gdscript
flow.go_to_main_menu()
```

が使える。

Main Menuを持たないGameでは空文字のままでよい。その場合 `go_to_main_menu()` は安全にError Resultを返す。

## Pause

```gdscript
flow.set_paused(true)
flow.set_paused(false)
flow.toggle_pause()
```

内部では `SceneTree.paused` を管理する。

`pause_changed(is_paused)` Signalを利用して、Game側のPause UI、Mouse Cursor、Audio処理などを同期できる。

FoundationはPause Menuの見た目やPause Keyを固定しない。Pause KeyはInput SystemのGame Contractで定義する。

## Safe Quit Hook

終了前にSaveやSettings flushを実行したいSystemはHookを登録できる。

```gdscript
flow.register_quit_hook(
    Callable(auto_save_service, "flush_pending")
)
```

Hookは次のいずれかを返せる。

- `Dictionary` — `ok: false` なら終了を中止
- `bool` — `false` なら終了を中止
- その他 / 戻り値なし — 成功扱い

実際に終了する場合:

```gdscript
flow.request_quit()
```

内部で全Hookを順番に実行し、成功した場合だけ `SceneTree.quit()` を呼ぶ。

Saveに失敗した時に無条件でGameを閉じて進行を失うことを避ける。

## Foundationが固定しないもの

- Pause Key
- Main MenuのScene名
- Gameplay Scene名
- Pause Menu UI
- Scene Transition Animation
- Loading Screen
- Quit確認Dialog

これらはGameのUXやGenreに依存するため、Game側またはStarter UI Layerで扱う。
