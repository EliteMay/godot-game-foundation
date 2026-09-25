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

Game Dev Hubや将来の共有ReportはこのSnapshotを利用できる。

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
