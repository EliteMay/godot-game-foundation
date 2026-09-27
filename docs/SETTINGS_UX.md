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
- Input remap UI

Generic Option Controlsは実装済みです。Input Remap UI / Conflict Detection / Input Prompt ResolverはPhase 12の後続Taskです。
