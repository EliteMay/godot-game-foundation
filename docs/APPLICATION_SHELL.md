# Application Shell / Scene UX

Phase 11のApplication Shellは、Game固有ThemeやGame ruleをFoundationへ固定せず、複数Gameで繰り返すScene UXだけをOptional Moduleとして提供します。

## Transition Layer

`addons/game_foundation/shell/transition_layer.gd` は、Scene切替やMenu Flowから利用できる全画面Fade Layerです。

### 境界

- FoundationRuntimeの必須機能ではありません。
- Game側が必要な時だけNodeとして追加します。
- Game固有のLogo、Background、Font、Button layout等は持ちません。
- Transition color / duration / CanvasLayer / motion scaleはGame側から変更できます。
- Mouse入力を奪わない `MOUSE_FILTER_IGNORE` を使います。
- Transition中の重複Requestは自動上書きせず `transition_in_progress` として拒否します。

### 基本API

```gdscript
const TransitionLayer = preload(
    "res://addons/game_foundation/shell/transition_layer.gd"
)

var transition := TransitionLayer.new()
add_child(transition)

transition.configure({
    "duration_seconds": 0.25,
    "color": Color.BLACK,
    "motion_scale": 1.0,
    "layer": 100,
})

transition.fade_out() # Sceneを覆う
await transition.transition_completed

# Scene切替など

transition.fade_in() # Sceneを見せる
await transition.transition_completed
```

`fade_out()` はConfigured colorへ覆う方向、`fade_in()` は透明へ戻してSceneを見せる方向です。

### Reduced motion / Animation短縮

`motion_scale` は0.0〜1.0です。

- `1.0`: 通常Duration
- `0.5`: 半分のDuration
- `0.0`: Animationせず即時に最終状態へ移動

BooleanでReduced motionだけ扱いたい場合は `set_reduced_motion(true)` を使えます。

このLayerはAccessibility設定そのものを所有しません。Game側または後続のLocalization / Accessibility ShellがPreferenceを決定し、その値をTransition Layerへ渡します。

## Async Scene Loader

`addons/game_foundation/shell/async_scene_loader.gd` は、Scene切替前にPackedSceneをBackground Threadで読み込むOptional Serviceです。

Godot公式の `ResourceLoader.load_threaded_request()` / `load_threaded_get_status()` / `load_threaded_get()` を使い、通常の `load()` でMain Threadを長時間Blockingしない構造にします。

### Scene Contractとの接続

Game固有PathをAsync Loaderへ直接登録しません。既存 `GameFlowService.resolve_scene_path()` をResolver Callableとして渡し、Scene ContractをSource of Truthにします。

```gdscript
const AsyncSceneLoader = preload(
    "res://addons/game_foundation/shell/async_scene_loader.gd"
)

var loader := AsyncSceneLoader.new()
add_child(loader)

loader.configure(
    Callable(flow_service, "resolve_scene_path")
)

loader.request_scene("gameplay")
```

### 状態とSignal

- `load_started(scene_id, path)`
- `load_progress(scene_id, progress)`
- `load_completed(scene_id, path, scene)`
- `load_failed(scene_id, path, result)`
- `status_snapshot()` で現在のScene ID / Path / Progress / Loaded Scene有無を取得
- `take_loaded_scene()` で完成したPackedSceneをConsumerへ渡す

Progressは0.0〜1.0です。

同じSceneの二重Requestは `duplicate_request`、別Sceneの同時Requestは `loader_busy` として拒否します。最初のVersionではResourceLoaderのBackground Jobを途中Cancelしたように見せるAPIは提供せず、明確な1-request-at-a-time Contractにします。

### Failure境界

- Scene ID解決はGameFlowService側Contractへ委譲
- Resolverが返すPathは `res://*.tscn` に限定
- Background Loadが失敗した場合は構造化Resultと `load_failed` Signalで通知
- PackedScene以外は成功扱いしない
- Pause中でもLoadingを進められる `PROCESS_MODE_ALWAYS`

## Loading Screen Contract

`addons/game_foundation/shell/loading_screen_contract.gd` は、Async Scene LoaderのRuntime StateをLoading UI向けの共通Presentation Contractへ変換するOptional Nodeです。

### State / Signal

- `state_changed(state)`
- `progress_changed(scene_id, progress, state)`
- `status_snapshot()`
- Phase: `idle / loading / loaded / failed`
- Progress: 0.0〜1.0
- Failure時は `last_code / last_message` を保持

`request_scene(scene_id)` は既存Async Scene LoaderへRequestを委譲します。Resolver / Scene PathのSource of Truthは引き続きGame Flow Scene Contract側です。

```gdscript
const LoadingScreenContract = preload(
    "res://addons/game_foundation/shell/loading_screen_contract.gd"
)

var loading_contract := LoadingScreenContract.new()
add_child(loading_contract)
loading_contract.configure(async_loader)

loading_contract.state_changed.connect(
    Callable(loading_view, "apply_loading_state")
)
loading_contract.progress_changed.connect(
    Callable(loading_view, "apply_loading_progress")
)

loading_contract.request_scene("gameplay")
```

### Visual境界

Loading Screen Contract自身は`Control`、ProgressBar、Logo、Background、Font、Paletteを生成しません。

Visual SceneはGame側の任意Sceneを利用でき、`state_changed` / `progress_changed` を購読するだけで差し替えられます。これによりFoundation Themeを作らず、Game固有VisualとLoading Stateの正本を分離します。

### Failure / State integrity

- Async Loaderを未設定のRequestは`loader_not_configured`
- Scene Resolver等がRequest開始前に拒否した場合も`failed` Stateへ反映
- Load中の`duplicate_request` / `loader_busy`は、進行中の`loading` Stateを`failed`へ上書きしない
- Loader切替はCurrent LoaderがLoading中なら拒否
- `reset_state()` はLoaderがIdleの時だけ許可

Visual Sceneは表示だけを担当し、Scene Path、PackedScene、ResourceLoader JobのOwnerにはしません。

## Pause Menu Shell

`addons/game_foundation/shell/pause_menu_shell.tscn` は、Game固有Themeを固定しないPause MenuのFunctional Baselineです。

### 接続するContract

`configure()` で既存Game Flow ServiceとGame側Options Actionを渡します。

```gdscript
var pause_menu := preload(
    "res://addons/game_foundation/shell/pause_menu_shell.tscn"
).instantiate()

add_child(pause_menu)

pause_menu.configure({
    "flow_service": flow_service,
    "options_action": Callable(self, "open_options"),
    "labels": {
        "resume": "Resume",
        "options": "Options",
        "main_menu": "Main Menu",
        "quit": "Quit",
    },
})
```

共通Action:

- `resume` → Game Flowの `set_paused(false)`
- `options` → Game側Callable
- `main_menu` → Game Flowの `go_to_main_menu()`
- `quit` → Game Flowの `request_quit()`

Pause入力Action名そのものはFoundationへ固定しません。Game側Input Contractから `open_menu()` / `toggle_menu()` を呼びます。

### Focus

`open_menu()` の直前に現在のGUI Focus Ownerを保存し、Resumeで閉じた後に有効なControlならFocusを戻します。

Main MenuへのScene遷移では古いSceneのFocusを復元しません。

### Visual境界

Default SceneはButtonの配置とMinimum Sizeだけを提供し、Palette / Font / Background image / Game Logo等は持ちません。Project ThemeやGame側SceneでVisualを差し替えられます。

Options / Main Menuが未設定の場合は該当Actionを表示しません。QuitもGame側Configで非表示にできます。

### Validation

Headless Smoke Testでは次を確認します。

- Open時にPauseされる
- ResumeでUnpauseする
- Pause前Focusが復元される
- Options Callableが呼ばれる
- Safe Quit blockをMenuが保持する
- Main Menu ActionがGame Flow Contractへ接続される
- Label差し替え

実際のGame ThemeでのVisual / Controller操作は、Phase 11のShell統合時にWindows実機でまとめて確認します。

## 今後の接続

Phase 11ではTransition LayerとAsync Scene Loaderを土台に、次を追加します。

- Loading Screen Contract
- Main Menu Shell
- Controller / Keyboard Focus Baseline
