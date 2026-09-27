# Settings / Input UX

## 目的

Phase 12では、既存のSettings / Input BackendをGameごとのOptions画面から安全に再利用できるUX layerへ接続します。

このDocumentはPhase 12のBehavior Contractを記録します。Game固有Theme、Label、Options構成は各Gameが所有します。

## Settings Edit Session

`addons/game_foundation/settings/settings_edit_session.gd` は、Options画面で扱う一時編集StateをCommitted Settingsから分離します。

### State

```text
Committed / Baseline Settings
        ↓ open session
Temporary Draft
        ↓ preview
Runtime State
```

- **Baseline**: Session開始時のCommitted Settings。Apply成功後はその値へ更新される。
- **Draft**: Userが編集中の一時Settings。
- **Runtime Preview**: 実際にPreview適用できた最後のSettings。
- **Persisted Settings**: Apply成功時だけ更新されるDisk上のSettings。

### Apply

1. DraftがまだRuntimeへPreviewされていなければ、先にRuntime適用を試す。
2. Runtime適用に成功した場合だけPersistence Callbackを呼ぶ。
3. Persistence成功後、Draftを新しいBaselineへ進める。
4. Sessionは継続可能で、その後のCancelは直近Apply時点へ戻る。

Apply前のPreviewだけではSettings Fileを書き換えません。

### Cancel

CancelはRuntime PreviewをBaselineへ戻してからDraftを破棄し、Sessionを終了します。

Runtime restoreに失敗した場合はSessionを終了せず、失敗Resultを返します。復元できていない状態を「Cancel完了」と扱いません。

### Reset

Resetは `SettingsSystem.default_settings(gameplay_defaults)` をDraftへ読み込みます。

Reset自体はSettings Fileを削除・上書きしません。Applyした時だけDefault値がPersistされます。これによりReset後でもCancelで開始時点へ戻れます。

### Preview failure rollback

Preview Callbackが失敗した場合、Sessionは直前に成功したRuntime Previewをもう一度適用してRollbackを試みます。

失敗したCandidateをDraftへ採用しません。Rollback Resultも返し、Runtime stateが不明な場合を隠しません。

## FoundationRuntime Integration

初期化済み `FoundationRuntime` では:

```gdscript
var start := foundation_runtime.begin_settings_edit_session()
if start.ok:
    var session = start.session
```

SessionはCurrent Runtimeの:

- current committed settings
- gameplay defaults
- Settings path
- audio bus map
- apply_gameplay_settings adapter

を再利用します。

Preview中は `FoundationRuntime.current_settings()` のCommitted値を変更しません。Apply成功時だけCommitted値を更新します。


## Generic Option Controls

`addons/game_foundation/settings/settings_option_control.gd` は、Settings Edit SessionのDraftへ直接BindingするTheme-neutralな共通Option Rowです。

対応Type:

- `toggle` → `CheckButton`
- `slider` → `HSlider` + 現在値Label
- `list` → `OptionButton`
- `resolution` → Resolution専用`OptionButton`

### Configuration

Game側がControlごとに設定Path、Label、候補値、Slider範囲等を渡します。

```gdscript
var row := SettingsOptionControl.new()
row.configure(session, {
    "type": "slider",
    "path": "audio.master",
    "label": "Master Volume",
    "min": 0.0,
    "max": 1.0,
    "step": 0.05,
    "display_multiplier": 100.0,
    "decimals": 0,
    "suffix": "%",
})
```

`path` は `"audio.master"` のようなDotted Stringまたは `["audio", "master"]` のString Arrayを受け取ります。存在しないPathは自動生成せずErrorにします。Typoで未使用Settingを作ることを避けるためです。

### Session integration

ControlはSettings Fileへ直接書きません。

```text
User interaction
→ SettingsOptionControl
→ SettingsEditSession.set_draft()
→ optional Runtime Preview
→ Apply時だけPersistence
```

Settings Edit SessionがReset等で`draft_changed`を出した場合、Control表示は現在Draftへ同期します。CancelでSessionが終了した後はControl入力を無効化します。

### Toggle

Boolean値専用です。LabelはGame側が指定し、Themeは親Controlから継承します。

### Slider

Game側が`min / max / step`を指定します。範囲外の値は暗黙ClampせずRejectします。

表示用に `display_multiplier / decimals / suffix / value_label_min_width` を任意指定できます。保存値`0.8`を`80%`表示するような構成が可能です。

### List

`options` はGame側が表示Labelと保存Valueを定義します。

```gdscript
"options": [
    {"label": "Windowed", "value": "windowed"},
    {"label": "Fullscreen", "value": "fullscreen"},
]
```

Game固有Labelと内部Setting値を分離できます。

### Resolution

`options` は `[width, height]` または `{"label": "...", "value": [width, height]}` を受け取ります。Label未指定時だけ `1920 × 1080` の形式を生成します。

現在DraftがGame側候補一覧にないResolutionでも、Controlはその値を一時表示して勝手に別Resolutionへ変更しません。Userが選択する新しい値はGame側候補一覧から選びます。

### Visual / Input boundary

FoundationはRowの最低限LayoutとGodot標準Controlだけを提供します。

Foundationが固定しないもの:

- Theme / Palette / Font
- Label文言
- Option順序
- Options画面全体のSection / Tabs / Scroll構成
- 物理Keyboard / Gamepad Button
- Game固有Settingの意味

標準Godot Controlを使うためKeyboard / Gamepad Focusを利用できますが、最終Focus順とVisual qualityはGame側Options画面へ組み込んだ状態で確認します。


## Input Remap UI

`addons/game_foundation/input/input_remap_control.gd` は、既存Input Systemへ接続するTheme-neutralなAction Rowです。

1 Rowは次を持ちます。

- Game-facing Action Label
- Current Binding Label
- Rebind Button
- Capture中だけ表示するCancel Button
- 入力待機State

### Action IDと表示名

内部Action名とUser-facing表示名を分離します。

```gdscript
var row := InputRemapControl.new()
row.configure(
    input_contract,
    "move_forward",
    "Move Forward",
    {
        "persist": Callable(foundation_runtime, "save_input_bindings"),
    }
)
```

Foundationは `move_forward` を画面Labelとして強制しません。LocalizationやGame独自文言はGame側が表示名を渡します。

### Capture

`start_listening()` 後、次のInputEventを受け取れます。

- Keyboard
- Mouse Button
- Joypad Button
- Joypad Motion / Axis

Key / Mouse / Joypad Buttonはpress eventだけ採用し、release / key echoは無視します。

Joypad Motionは`axis_threshold`未満をdriftとして無視します。採用したAxisは方向だけを`-1.0 / 1.0`へ正規化します。

Gamepad deviceは既定で`-1`へ正規化し、Controllerの接続順が変わってもBindingを特定deviceへ固定しません。特定deviceを必要とするGameだけ`preserve_gamepad_device=true`を指定できます。

### Cancel

FoundationはEscape等の物理KeyをCapture CancelへHardcodeしません。

- Cancel Button
- `cancel_listening()`

のどちらかから終了します。これによりEscape自体をGame Actionへ割り当てる余地を残します。

### Persistence / rollback

Rebind自体は既存 `InputSystem.rebind_action()` を使います。

`persist` Callableを設定した場合は、Runtime Rebind成功後にPersistenceを呼びます。Persistenceが失敗した場合、ControlはRebind前にCaptureしたBindingsを `InputSystem.apply_bindings()` でRuntimeへ戻すことを試み、失敗ResultとRollback Resultの両方を返します。

Persistenceを指定しない場合はRuntimeだけを変更できます。

### Current Binding text

既定表示はGodot InputEventのtext representationを使います。

Gameが独自表示を必要とする場合は`binding_formatter` Callableを渡せます。Current deviceやIcon keyを解決する正式なInput Prompt ResolverはPhase 12の後続Taskです。

### Conflict boundary

このControlは同じBindingが別Actionですでに使われているかを独自判断しません。

Conflict Detection / Reject / Replace / Allow PolicyはPhase 12の次TaskとしてInput System上へ追加します。UIが先に暗黙Policyを持たないよう責務を分離します。

### Visual / Focus boundary

FoundationはGodot標準のLabel / Buttonと最小Row構造だけを生成し、Theme / Palette / Font / Options画面全体の構成はGame側へ残します。

Rebind / Cancel Buttonは標準Focus対象です。最終Focus順、長い翻訳文言、Game ThemeでのSpacing / Contrast、物理Controller操作感は実Game Options画面へ組み込んだ状態で確認します。


## Conflict Detection

`addons/game_foundation/input/input_conflict_resolver.gd` は、Candidate BindingがCurrent InputMap上の別Actionと重なるかを検出し、Game側がPolicyを選べる共通層です。

対応Policy:

- `reject` — 競合があればRuntimeを変更せず `binding_conflict`
- `replace` — 競合Actionから一致Eventだけを外し、Target Actionへ割り当て
- `allow` — 競合情報を返しつつ既存Actionを残してTargetへも割り当て

```gdscript
var result := InputConflictResolver.rebind_with_policy(
    input_contract,
    "jump",
    {"type": "key", "physical_keycode": KEY_SPACE},
    InputConflictResolver.POLICY_REJECT
)
```

### Conflict semantics

同じ物理入力として扱う範囲をDescriptor種別ごとに明示します。

- Keyboard: keycode / physical_keycode / unicode / Modifierが同一
- Mouse Button: button index / Modifierが同一
- Joypad Button: button indexが同一でdevice scopeが重なる
- Joypad Motion: axisと方向が同一でdevice scopeが重なる
- Joypadの`device=-1`はwildcardなのでspecific deviceと重なる
- 同じAction自身の現在BindingはConflict対象にしない

異なるspecific gamepad device同士は競合とみなしません。Axisは同じ軸でも正方向と負方向を別Bindingとして扱います。

### Replace semantics

Replaceは競合Action全体をResetしません。一致したEventだけを除去し、同じActionに別のKeyboard / Mouse / Gamepad Bindingが残っていれば保持します。

### Input Remap UI integration

`InputRemapControl.configure()` のoptionsへ`conflict_policy`を渡せます。

```gdscript
{
    "conflict_policy": "reject"
}
```

既定値は`allow`です。Phase 12 Input Remap UI実装前と同じBehaviorを維持しつつ、Game側が明示的にReject / Replaceへ切り替えられます。

RejectされたConflictではCaptureを終了せず、別のInputをそのまま待てます。`conflict_detected` SignalとResultの`conflicts`からGame側が説明UIを出せます。

Replaceは複数Actionを変更し得ますが、Persistence Callbackが失敗した場合はInput Remap UIがCapture前の全BindingsへRuntime rollbackを試みます。

### Boundary

FoundationはどのPolicyがそのGameに正しいかを決めません。Competitive game、Local multiplayer、Accessibility shortcut等で要求が異なるため、Policy選択はGame側です。


## Input Prompt Resolver

`addons/game_foundation/input/input_prompt_resolver.gd` は、現在使っているInput deviceとAction Bindingから、表示用TextとAsset非依存のIcon keyを解決します。

```gdscript
var prompts := InputPromptResolver.new()
prompts.configure(input_contract)

# Gameの_input等から渡す
prompts.observe_event(event)

var prompt := prompts.resolve_action("interact")
# prompt.text
# prompt.icon_key
# prompt.icon_keys
```

### Current device

Foundationでは次の2 familyを共通化します。

- `keyboard_mouse`
- `gamepad`

Key press / Mouse Button / 有意なMouse Motionはkeyboard/mouse、Joypad Button / 有意なAxis Motionはgamepadへ切り替えます。

誤切替を避けるため、Key echo / release、Button release、設定Threshold未満のStick driftとMouse jitterは無視します。

Gamepadでは最後に操作した`device_id`も保持します。Actionにspecific-device Bindingがある場合は現在deviceとの一致を優先し、次にdevice=-1のwildcardを選びます。

### Action resolution

`resolve_action()` はCurrent deviceに合うBindingを優先します。

現在device向けBindingが無い場合は既定で他deviceのBindingへFallbackし、`fallback_used=true`を返します。GameがCurrent deviceだけを表示したい場合は`allow_fallback=false`を指定できます。

未割当ActionはErrorではなく`action_unbound` + `available=false`として扱います。

### Text / Icon keys

Resolverは次のようなPresentation dataを返します。

- `text`: `W`, `Ctrl + Mouse Left`, `Left Stick Right` 等
- `icon_key`: 単一文字列として組み合わせたkey
- `icon_keys`: Modifierを含む複数Glyph用key配列
- `canonical_icon_key(s)`: Game override前のFoundation semantic key

代表例:

- `key_w`
- `key_space`
- `mouse_left`
- `gamepad_south`
- `gamepad_dpad_up`
- `gamepad_left_stick_right`

Face ButtonはXbox / PlayStation / Nintendo等の製品固有GlyphをFoundationが推測せず、South / East / West / Northの位置semanticを使います。

### Icon pack / Localization adapter

FoundationはIcon画像を同梱しません。

Game側はconfigure時にoverrideできます。

```gdscript
prompts.configure(
    input_contract,
    {
        "text_overrides": {
            "gamepad_south": "決定",
        },
        "icon_key_overrides": {
            "gamepad_south": "xbox_a",
        },
    }
)
```

これによりThird-party Icon Pack、Game独自Sprite Atlas、Localizationへ接続できます。Canonical keyはResultへ残るため、override後も元semanticを追跡できます。

### Input Remap UI integration

`InputRemapControl` の`binding_formatter`へResolverのFormatterをそのまま渡せます。

```gdscript
{
    "binding_formatter": Callable(prompts, "format_descriptor_text")
}
```

Input Remap UI自体は特定Icon PackやController familyへ依存しません。

### Boundary

- Controller製品名からXbox / PlayStation / Nintendo Glyphを自動断定しない
- Third-party Icon Pack AssetをFoundationへ必須同梱しない
- Game固有LocalizationをFoundationへ固定しない
- Current device追跡はPrompt presentation用であり、Input SystemのBinding source of truthを置き換えない

## Boundary

Foundationが所有するもの:

- Draft / Baseline / Preview lifecycle
- Apply / Cancel / Reset behavior
- Normalize
- Runtime rollback attempt
- FoundationRuntimeとのSettings contract接続

Game側が所有するもの:

- Options画面のVisual Theme
- Label / 説明文
- どのSettingを画面へ出すか
- Gameplay settingの意味
- Input remap UIのTheme / 画面全体構成

Generic Option Controls、Input Remap UI、Conflict Detection、Input Prompt Resolverまで実装済みです。Phase 12の共通Behaviorは完了し、実Game Theme / Focus / 物理Controller操作感は統合時のRuntime Validationへ残します。
