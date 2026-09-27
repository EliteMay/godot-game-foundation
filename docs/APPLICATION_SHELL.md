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

## Main Menu Shell

`addons/game_foundation/shell/main_menu_shell.tscn` は、Game固有Themeを固定せずNew / Continue / Options / Quitの共通Action slotを提供するOptional Main Menuです。

### 接続するContract

`configure()` でGame側Actionと既存Game Flow Serviceを渡します。

```gdscript
var main_menu := preload(
    "res://addons/game_foundation/shell/main_menu_shell.tscn"
).instantiate()

add_child(main_menu)

main_menu.configure({
    "flow_service": flow_service,
    "new_game_action": Callable(self, "start_new_game"),
    "continue_action": Callable(self, "continue_game"),
    "options_action": Callable(self, "open_options"),
    "continue_available": has_resumable_save,
    "labels": {
        "new_game": "New Game",
        "continue": "Continue",
        "options": "Options",
        "quit": "Quit",
    },
})
```

共通Action:

- `new_game` → Game側Callable
- `continue` → Game側Callable
- `options` → Game側Callable
- `quit` → Game Flow `request_quit()`

New / Continue / OptionsはGame固有FlowをFoundationへ固定しないためCallableとして差し込みます。Quitだけは既存Safe Quit Hookを通す必要があるためGame Flow Contractを再利用します。

### Continue availability

`continue_action` が設定されていても、再開可能なSaveが無い間は `continue_available: false` にできます。この場合Buttonは表示したまま無効化されます。

Saveが作成・削除・切替された後は `set_continue_available(bool)` で状態を更新できます。FoundationはSaveの存在条件やSlot選択を判断しません。Phase 14のSave Profiles / Slots等が導入されても、Main Menu Shellはその結果を受け取るConsumerに留まります。

### Focus

初期Focusは、利用可能なContinue → New Game → Options → Quitの順に最初の有効Actionへ移します。これによりReturning UserはContinueへ、初回UserはNew Gameへ入りやすくします。

`focus_initial_action()` はOptions等の別UIからMain Menuへ戻った時にも再利用できます。Controller / Keyboardの詳細なNavigation BaselineはPhase 11の次Taskで共通化します。

### Visual境界

Default Sceneは中央配置、Panel、ButtonのMinimum SizeとSpacingだけを持ちます。Game固有Logo、Background、Font、Palette、装飾、Button compositionの最終VisualはGame側Theme / Sceneで差し替えます。

未設定のNew / Continue / Options slotは非表示にできます。Quitも`show_quit: false`で外せます。

### Validation

Headless Smoke Testでは次を確認します。

- First-useでContinueが無効、New GameへFocusされる
- Continue availability更新後はContinueへFocusされる
- New / Continue / Options CallableがGame側Resultを保持する
- Safe Quit blockがMenuへ返る
- Label override
- Optional action slotの表示制御
- deactivate中のAction拒否

実Game ThemeでのVisual / Controller操作は、Controller / Keyboard Focus BaselineとPhase 11統合時にWindows実機でまとめて確認します。

## Controller / Keyboard Focus Baseline

`addons/game_foundation/shell/menu_focus_navigation.gd` は、MenuのAction availabilityからGodot標準Focus graphを再構築する小さな共通Utilityです。

Main Menu Shell / Pause Menu ShellはDefaultでこのUtilityを使い、現在表示されていてenabledなButtonだけをVisual順に `focus_neighbor_top / bottom` と `focus_previous / next` へ接続します。

### Input境界

FoundationはWASD、Arrow Key、Enter、A Button等の物理入力名をMenu ShellへHardcodeしません。Godot標準UI Focus / `ui_*` semantic actionを利用し、Keyboard / Controllerの実MappingはGodot / Game側Input設定へ残します。

これによりMouseなしでも同じAction ButtonへFocus移動・Activateでき、Game固有Input ContractとMenu navigationを二重管理しません。

### Dynamic availability

- hidden ActionはFocus graphから除外
- disabled ActionはFocus graphから除外
- Main MenuのContinue availability変更時はFocus graphを再構築
- Pause Menuを開くたびにOptions / Main Menu / Quit availabilityを反映
- Availability変更で現在Focusが無効になった場合、Main Menuは利用可能な初期Actionへ回復

Default graphは端でWrapしません。Main / Pause Shell以外のGame固有Controlを追加した場合にFocusを閉じ込めないためです。

Custom grid / horizontal layout等でGame側が完全にFocusを所有したい場合は `configure()` へ `manage_focus_navigation: false` を渡せます。

### Runtime observation

Main Menu / Pause Menuの `state_snapshot()` は `focused_action_id` と `managed_focus_navigation` を返します。Game Dev Hub等のRuntime Test ProviderはShell自体のVisualへ依存せず、現在Focus Actionを状態として公開できます。

### Validation

`menu_focus_navigation_smoke.tscn` では次を検証します。

- hidden / disabled Controlを飛ばしたFocus neighbor生成
- Focus端で不要なTrapを作らない
- availability変更後のFocus graph再構築
- `ui_down` で次ButtonへFocus移動
- `ui_accept` でMouseなしにButton Actionが発火

Main / Pause Menu各Smokeでも初期Focus、動的Focus neighbor、`focused_action_id`をRegression対象にします。

物理Controllerの機種差・実Windows上の操作感はHeadless CIでは確認済みと扱わず、実Game統合時のRuntime Validation対象として残します。

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

Phase 11ではTransition Layer / Async Scene Loader / Loading Screen Contract / Main Menu Shell / Pause Menu Shell / Controller・Keyboard Focus Baselineまで実装済みです。

次の共通実装はPhase 12 — Settings / Input UX Componentsへ進みます。
