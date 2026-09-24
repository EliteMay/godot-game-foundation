# Generic Save System

## 目的

FoundationがGame固有Stateの意味を知らなくても、安全にSave / Loadできる共通基盤を提供する。

Foundationは `money`、`inventory`、`player_position` などのFieldを定義しない。Game側が必要なStateをJSON互換Dictionaryへ変換し、Foundationへ渡す。

## File Format

```json
{
  "metadata": {
    "format": "godot-game-foundation-save",
    "foundation_schema_version": 1,
    "game_schema_version": 3,
    "saved_at_unix": 1790000000
  },
  "payload": {
    "any_game_specific_field": "value"
  }
}
```

Foundation EnvelopeとGame Payloadを分離し、Foundation側VersionとGame側Versionも別々に管理する。

## Payload Contract

許可:

- null
- bool
- int
- finite float
- String
- Array
- String Keyだけを持つDictionary

拒否例:

- Vector2 / Vector3 / Transform
- Resource / Node / Object
- Callable
- StringName Key
- NaN / Infinity
- 深すぎる循環・Nest

Godot固有型を保存したいGameはAdapter側でArrayやDictionaryへ変換する。

## Save / Load

```gdscript
const SaveSystem = preload("res://addons/game_foundation/save/save_system.gd")

var save_result := SaveSystem.save_game(
    build_game_payload(),
    GAME_SAVE_VERSION,
    "user://save.json"
)

var load_result := SaveSystem.load_game(
    "user://save.json",
    GAME_SAVE_VERSION,
    Callable(self, "migrate_save")
)
```

Runtime Save Pathは `user://` に限定する。

## Atomic replacement

1. `save.json.tmp` へ完全なJSONを書き込む
2. Tempを再読込して成立することを確認
3. 既存Primaryが正常なら `save.json.bak` へ退避
4. TempをPrimaryへrenameする

不完全なTempをPrimaryとして採用しない。

## Backup recovery

PrimaryがFile破損・JSON破損・Envelope破損などの場合、Foundationは `.bak` を試す。

ただしPrimaryが「このGameより新しいSchema」の場合はBackupへ勝手に戻らない。古いBackupを開いて進行を巻き戻すData Lossを避けるため。

## Migration Hook

保存Game Schemaが現在より古い場合、Game側CallableへMigrationを委譲する。

```gdscript
func migrate_save(
    payload: Dictionary,
    from_version: int,
    to_version: int
) -> Dictionary:
    var next := payload.duplicate(true)
    # Game固有Migration
    return next
```

Migration後PayloadもFoundationが再Validationする。

## Auto Save API

`AutoSaveService` は短時間に連続するSave要求をDebounceし、最後のStateを保存する。

```gdscript
const AutoSaveService = preload(
    "res://addons/game_foundation/save/auto_save_service.gd"
)

var autosave := AutoSaveService.new()
autosave.save_path = "user://save.json"
autosave.debounce_seconds = 0.5
add_child(autosave)

autosave.request_save(build_game_payload(), GAME_SAVE_VERSION)
```

どのGameplay Eventで保存要求を出すかはGame側が決める。終了前などは `flush_pending()` で待機中Saveを即時確定できる。

## Result Contract

Save / LoadはGameをCrashさせずDictionary Resultを返す。

共通Field:

- `ok`
- `code`
- `message`（Error時）

代表Code:

- `saved`
- `loaded`
- `not_found`
- `parse_error`
- `invalid_payload`
- `foundation_schema_too_old`
- `foundation_schema_too_new`
- `game_schema_too_new`
- `migration_required`
- `migration_failed`

## 責務分担

Foundation:
- Payload Validation
- Metadata
- Version判定
- Atomic replacement
- Backup / Recovery
- Migration hook
- Debounced Auto Save

Game:
- 何を保存するか
- Godot型とJSON Payloadの変換
- Game Schema Versionの意味
- Game固有Migration
- どのEventでAuto Saveするか
- Load後にRuntimeへどう適用するか
