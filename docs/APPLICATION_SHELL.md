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

## 今後の接続

Phase 11では後続で次を追加し、このTransition LayerをOptionalに利用します。

- Async Scene Loader
- Loading Screen Contract
- Main Menu Shell
- Pause Menu Shell
- Controller / Keyboard Focus Baseline
