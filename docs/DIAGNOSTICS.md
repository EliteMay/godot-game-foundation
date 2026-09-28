# Diagnostics

## 目的

不具合報告やGame Dev Hub共有時に、Version・保存先・主要Error・最近のLogを一か所から確認できる共通基盤を提供する。

DiagnosticsはGame固有のGameplay状態を勝手に収集しない。Game側が共有してよい情報だけをContextやPathとして渡す。

## Runtime Version Info

`runtime_info.gd` は次を取得する。

- App名 / App Version
- Foundation Version
- Godot Version
- OS名 / OS Version
- Display Server
- Headless判定
- Debug Build判定
- Processor Count

ユーザーの実Directoryを勝手にGlobal Pathへ変換せず、Save Path等は `user://...` のVirtual Pathとして扱う。

## Diagnostics Service

```gdscript
const DiagnosticsService = preload(
    "res://addons/game_foundation/diagnostics/diagnostics_service.gd"
)

var diagnostics := DiagnosticsService.new()
add_child(diagnostics)

diagnostics.configure(
    {
        "name": "My Game",
        "version": "0.1.0",
        "foundation_version": "0.6.0-dev"
    },
    {
        "save": SaveSystem.DEFAULT_SAVE_PATH,
        "settings": SettingsSystem.DEFAULT_SETTINGS_PATH,
        "input": InputSystem.DEFAULT_INPUT_PATH,
        "log": DiagnosticsService.DEFAULT_LOG_PATH
    }
)
```

## Log Service

```gdscript
diagnostics.log_info("game started")
diagnostics.log_warning("inventory nearly full", {"remaining": 1})
diagnostics.log_error("save failed", {"code": result.code})
```

各Entry:

```json
{
  "timestamp_unix": 1790000000,
  "level": "error",
  "message": "save failed",
  "context": {
    "code": "disk"
  }
}
```

Memory上のEntry数には上限を持たせる。Disk Logも既定1 MiBを超えると `.old` へ1世代Rotationする。

Godot固有型などJSONへ直接保存しづらいContextは文字列化してLog書込み失敗を避ける。

## Error Summary

`error_summary()` で取得できる。

- Info件数
- Warning件数
- Error件数
- 最近のError最大10件

`build_snapshot()` はRuntime Info、Path、Error Summary、最近のLog、FPSをまとめる。

内部OverlayやRuntime調査ではこのSnapshotを利用できる。

Game Dev Hub等へ外部共有する場合は、生のSnapshotをそのまま送らず `DiagnosticsExportHook` を通す。

## Debug Overlay

`diagnostics_overlay.gd` は開発時に表示できるDark Overlay。

表示内容:

- App / Foundation / Godot Version
- OS / Display Server
- FPS
- Save / Settings / Input / Log Path
- Info / Warning / Error件数
- 最近のError

```gdscript
const DiagnosticsOverlay = preload(
    "res://addons/game_foundation/diagnostics/diagnostics_overlay.gd"
)

var overlay := DiagnosticsOverlay.new()
add_child(overlay)
overlay.bind_service(diagnostics)
overlay.set_overlay_visible(true)
```

Overlayを開くKeyはFoundationへ固定しない。各GameのInput Contractから呼び出す。

## Privacy

Diagnostics Coreは次を既定で収集しない。

- ユーザー名
- Home Directoryの実Path
- IP Address
- Hardware ID
- Account情報

Game側がContextへ追加する場合も、共有して問題ない情報だけにする。

## 責務分担

Foundation:
- Runtime Version情報
- Bounded Memory Log
- Disk Log / Rotation
- Error Summary
- Path表示用Snapshot
- Debug Overlay

Game:
- App Version
- Game固有Context
- Overlayを開くInput
- ユーザー共有用Reportに何を含めるか


## Diagnostics Export Hook

`diagnostics_export_hook.gd` はDiagnostics Serviceの内部Snapshotを、Game Dev HubやBug Reportへ渡しやすい共有用Payloadへ変換する。

```gdscript
var export_result := runtime.diagnostics_export({
    "reason": "game_dev_hub_share",
})

if export_result.ok:
    var payload: Dictionary = export_result.payload
    var json_text: String = export_result.json
```

共有用Payloadは次を含む。

- App / Foundation / Godot Version
- OS / Display Server / Headless / Debug Build
- Foundation Runtimeの安全な状態Field
- Runtime Failure Stateの共有可能Field
- `user://` / `res://` のVirtual Path
- Error件数
- Sanitized Recent Error / Log
- FPS
- Sanitization / Payload size metadata

### 共有しないもの

共有用PayloadはDiagnostics SnapshotやRuntime Statusの単純コピーではない。

次はホワイトリスト外にする。

- Save Payload
- `last_load.payload`
- Settings本体
- Input Binding本体
- Game固有Domain State
- Binary Data
- 絶対File Path
- password / token / API key / authorization / cookie / credential等の既知Sensitive Field

Log ContextはGame側が任意Dataを渡せるため、Export時に再Sanitizeする。

### Bounded export

共有Payloadは次を上限化する。

- Recent Entry件数
- Recent Error件数
- String長
- ContextのNest深さ
- Collection item数
- JSON全体: 128 KiB

上限を超えた場合はRecent Entry / Recent Error detailを落として再構築する。それでも上限を超える場合はExport失敗として返し、巨大Payloadをそのまま送らない。

### Path privacy

`user://` と `res://` は共有可能なVirtual Pathとして保持する。

Absolute Pathは `<redacted-path>` へ置換する。Free text内でも検出可能なHome Path / Absolute Path / known token patternはRedaction対象とする。

### Boundary

Foundationは共有可能Payloadを生成するだけで、Network送信、Clipboard、File Picker、Upload先を所有しない。

Game Dev Hub側は `FoundationRuntime.diagnostics_export()` のResultを既存共有パックへ取り込める。
