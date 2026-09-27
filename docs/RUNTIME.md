# Integrated Foundation Runtime

## 目的

`FoundationRuntime` は、既存のSave / Settings / Input / Game Flow / Diagnostics / Runtime Test BridgeをGameごとに毎回手動配線しなくてよいようにするLifecycle Coordinatorです。

各System自体は独立したまま維持します。Runtimeを使わず、必要なSystemだけ単独利用することもできます。

## 役割分担

FoundationRuntimeが担当するもの:

- Settings読込と共通Runtime適用
- Game固有Gameplay Settings Callback
- Input Binding復元
- Scene Contract / Main Menu初期化
- Save読込 / Auto Save要求 / 明示Save / Safe Quit Save
- Diagnostics Service初期化
- Runtime Test Bridgeの接続
- Load/Restore Failure時のSave write block

Game側が担当するもの:

- 何をSaveするか
- Save PayloadをどうRuntime Stateへ戻すか
- Game Schema Migration
- Game固有Settingの意味と適用
- Input Action名とDefault Binding
- Scene ID
- Runtime Testへ公開するState

## 最小利用

```gdscript
const FoundationRuntime = preload(
    "res://addons/game_foundation/runtime/foundation_runtime.gd"
)

var foundation_runtime := FoundationRuntime.new()

func _ready() -> void:
    add_child(foundation_runtime)

    var configured := foundation_runtime.configure(
        {
            "save": {
                "enabled": true,
                "game_schema_version": 1,
            },
            "settings": {
                "gameplay_defaults": {
                    "mouse_sensitivity": 0.0025,
                },
            },
            "input": {
                "contract": INPUT_CONTRACT,
            },
            "flow": {
                "scenes": SCENE_CONTRACT,
                "main_menu_id": "menu",
            },
        },
        {
            "capture_save_state": Callable(self, "build_save_payload"),
            "restore_save_state": Callable(self, "restore_save_payload"),
            "apply_gameplay_settings": Callable(self, "apply_gameplay_settings"),
            "runtime_test_state": Callable(self, "build_runtime_test_state"),
        }
    )

    if not configured.ok:
        push_error(str(configured))
        return

    var initialized := foundation_runtime.initialize()
    if not initialized.ok:
        push_error(str(initialized))
```

## Config

### app

Diagnosticsへ渡すGame名とVersion。

未指定ならProject Settingsの `application/config/name` / `application/config/version` を使います。

### save

```gdscript
{
    "enabled": true,
    "path": "user://save.json",
    "game_schema_version": 1,
    "autosave_debounce_seconds": 0.5,
}
```

Saveを有効にする場合は `capture_save_state` と `restore_save_state` が必須です。

### settings

```gdscript
{
    "enabled": true,
    "path": "user://settings.json",
    "gameplay_defaults": {},
    "audio_bus_map": {
        "master": "Master",
        "bgm": "BGM",
        "sfx": "SFX",
    },
    "apply_runtime": true,
}
```

### input

```gdscript
{
    "enabled": true,
    "path": "user://input_bindings.json",
    "contract": INPUT_CONTRACT,
}
```

### flow

```gdscript
{
    "enabled": true,
    "scenes": SCENE_CONTRACT,
    "main_menu_id": "menu",
}
```

### diagnostics

```gdscript
{
    "enabled": true,
    "log_path": "user://logs/runtime.log",
}
```

### runtime_test

```gdscript
{
    "enabled": true,
}
```

Runtime Test BridgeはGame Dev Hub等がTest用Command Line Argumentを付けた時だけ有効になります。

## Adapter Contract

### capture_save_state

引数なし。JSON互換Dictionaryを返します。

```gdscript
func build_save_payload() -> Dictionary:
    return {
        "money": money,
        "player": {
            "position": [
                player.position.x,
                player.position.y,
                player.position.z,
            ],
        },
    }
```

### restore_save_state

LoadされたPayloadを受け取り、成功可否を返します。

```gdscript
func restore_save_payload(payload: Dictionary) -> Dictionary:
    money = int(payload.get("money", 0))
    return {"ok": true}
```

### migrate_save_state

既存Save SystemのMigration Callableとしてそのまま渡します。

### apply_gameplay_settings

`settings.gameplay` のDictionaryを受け取り、Game固有SettingをRuntimeへ適用します。

### runtime_test_state

Game Dev Hubへ公開してよいJSON互換Stateだけを返します。

## Save Lifecycle

通常:

```text
Game Event
→ request_auto_save()
→ latest payloadをDebounce
→ disk commit
```

明示Save:

```text
save_now()
→ latest payloadでPending Auto Saveを置換
→ flush
→ disk commit
```

これにより、古いPending Autosaveが明示Saveの後から実行され、最新Stateを古いStateへ巻き戻すことを防ぎます。

## Load Failure Safety

Load / Migration / Game側Restoreが失敗した場合、Runtimeは `save_writes_blocked=true` にします。

そのSessionでは既存Canonical Saveを新しい不完全Stateで上書きしません。

`status_snapshot()` / Diagnosticsで状態を確認できます。

## Runtime Test Mode

Runtime Test BridgeがCommand Lineから有効になった場合:

- Game側StateはLocal JSONへSnapshotされる
- 通常Saveへのwriteは行わない
- Network Listenerは作らない
- Foundationから任意CommandをGameへ送るChannelは作らない

Test操作を通常Player Saveへ混ぜないための境界です。

## Safe Quit

Saveが有効でGame Flowも有効な場合、FoundationRuntimeはSafe Quit Hookへ最新Stateの `save_now()` を登録します。

Game側は終了時に:

```gdscript
foundation_runtime.request_quit()
```

を利用できます。

Saveに失敗した場合はGame Flowの既存Contractに従い終了をBlockできます。

## Diagnostics

`diagnostics_snapshot()` でFoundation共通Snapshotを取得できます。

既定で実Home Directory、IP Address、Account情報等は収集しません。

## Starter

v0.10.0-dev以降のStarterはFoundationRuntimeを生成して初期化します。

StarterではGame固有Save Adapterがまだ存在しないためSaveは既定OFFです。Game要件を決めてAdapterを実装した後にSaveを有効化します。
