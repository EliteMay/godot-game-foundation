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

## 今後の接続

Phase 11ではTransition LayerとAsync Scene Loaderを土台に、次を追加します。

- Loading Screen Contract
- Main Menu Shell
- Pause Menu Shell
- Controller / Keyboard Focus Baseline
