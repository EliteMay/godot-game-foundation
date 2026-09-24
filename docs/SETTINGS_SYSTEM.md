# Settings System

## 目的

複数のGameで共通するAudio / Display設定をFoundation側で扱いながら、Game固有SettingはFoundationを変更せず追加できるようにする。

SettingsはSave Dataとは別Fileで管理する。

```text
user://settings.json
```

## Settings Object

```json
{
  "audio": {
    "master": 1.0,
    "bgm": 1.0,
    "sfx": 1.0
  },
  "display": {
    "window_mode": "windowed",
    "resolution": [1280, 720],
    "vsync": true
  },
  "gameplay": {}
}
```

### Audio

Volumeは0.0〜1.0。

- master
- bgm
- sfx

Runtime適用時はBus名MappingをGame側から差し替えられる。BGM / SFX Busが存在しないGameではErrorにせず、missing busとしてResultへ返す。

### Display

- `windowed`
- `fullscreen`
- `borderless`
- Resolution
- VSync

Invalidな値は起動不能にせず安全なDefaultへNormalizeする。

## Gameplay Extension

Foundationは `gameplay` のFieldを決めない。

Game側がDefault値を渡す。

```gdscript
var gameplay_defaults := {
    "mouse_sensitivity": 0.25,
    "camera": {
        "fov": 90
    }
}

var settings := SettingsSystem.default_settings(gameplay_defaults)
```

保存済みGameplay SettingとDefaultはDeep Mergeされるため、新しいSettingをGame Updateで追加しても既存Fileに不足するDefaultを補える。

Foundationが保証するのはJSON互換性まで。Mouse Sensitivityの範囲など、Game固有の意味ValidationはGame側で行う。

## Persistence

Settings Fileは次のEnvelopeで保存する。

```json
{
  "metadata": {
    "format": "godot-game-foundation-settings",
    "settings_schema_version": 1,
    "saved_at_unix": 1790000000
  },
  "settings": {}
}
```

保存は一時Fileで検証してからPrimaryへrenameする。既存Primaryが正常な場合は `.bak` を保持する。

Primaryが破損した場合はBackupを試し、どちらも使えない場合はDefault Settingsで安全に起動する。Fallbackしただけでは破損Fileを自動上書きしない。

## Runtime Apply

```gdscript
const SettingsRuntime = preload(
    "res://addons/game_foundation/settings/settings_runtime.gd"
)

SettingsRuntime.apply_settings(settings, {
    "master": "Master",
    "bgm": "Music",
    "sfx": "SFX"
})
```

Headless環境ではDisplay / Audio適用を行わず、安全にskipする。

## Reset

`reset_settings()` はPrimary / Backup / Tempを削除してDefault値を返す。

Settings UIから「初期設定へ戻す」を実装する時に利用できる。

## 責務分担

Foundation:
- 共通Audio Schema
- 共通Display Schema
- Normalize / Safe Default
- Persistence / Backup
- Runtime Apply
- Gameplay拡張用Container

Game:
- Gameplay Settingの名前・意味
- Game固有の範囲Validation
- 実際のSettings UI
- Game固有Audio Bus名
- Setting変更のApply Timing
