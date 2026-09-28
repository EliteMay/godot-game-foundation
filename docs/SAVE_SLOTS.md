# Save Profiles / Slots

## 目的

`SaveSlotManager` は、既存のGeneric Save Systemを置き換えず、複数Save Slot、Continue、New Gameが必要なGameだけが追加利用するOptional layerです。

Single Save Gameは従来どおり `SaveSystem` / `FoundationRuntime` を利用できます。

## Authority

各SlotのCanonical Local Artifactは1つのSave Fileです。

```text
user://save_slots/
├─ alpha.json
├─ alpha.json.bak
└─ beta.json
```

Slot MetadataとGame Payloadは同じAtomic Save Envelope内で論理的に分離します。

```json
{
  "metadata": {
    "format": "godot-game-foundation-save",
    "foundation_schema_version": 1,
    "game_schema_version": 2,
    "saved_at_unix": 1790000000,
    "slot": {
      "format": "godot-game-foundation-save-slot",
      "metadata_schema_version": 1,
      "slot_id": "alpha",
      "display_name": "Alpha",
      "created_at_unix": 1790000000,
      "updated_at_unix": 1790000123,
      "game_schema_version": 2,
      "summary": {
        "chapter": 3
      }
    }
  },
  "payload": {
    "game_specific_state": "..."
  }
}
```

Slot表示用DataをGame Payloadへ混ぜない一方、別Metadata Fileとの2 File transactionも作らない設計です。

## Slot ID

許可:

- lowercase `a-z`
- `0-9`
- `_`
- `-`
- 1〜64文字
- 先頭は英数字

Path separator、`..`、大文字等は拒否します。

Display NameはIDとは別で、User-facing Nameを自由に持てます。

## Configure

```gdscript
const SaveSlotManager = preload(
    "res://addons/game_foundation/save/save_slot_manager.gd"
)

var slots := SaveSlotManager.new()

func _ready() -> void:
    slots.configure({
        "slots_root": "user://save_slots",
        "current_game_schema_version": GAME_SAVE_VERSION,
        "migrator": Callable(self, "migrate_save"),
    })
```

## Lifecycle

### Create

`create_slot(slot_id, payload, options)`

Existing primary / backup / temp artifactがあるIDを暗黙上書きしません。

Options:

- `display_name`
- `summary` — JSON互換Dictionary

### Save

`save_slot(slot_id, payload, options)`

HealthyなPrimaryが確認できる既存Slotだけ更新します。

Corrupt Primary + valid Backupでも、新しいRuntime StateでPrimaryを暗黙上書きしません。まずLoad / Recovery判断をGame側で行います。

### Load

`load_slot(slot_id)`

既存SaveSystemのBackup RecoveryとGame Schema Migrationを再利用します。

Resultには次を含みます。

- Slot Metadata
- Game Payload
- Primary / Backup source
- Backup recovery flag
- Migration flag

### List

`list_slots()`

Slot Metadataの `updated_at_unix` 降順で返します。

正常Slotと `invalid_slots` を分離し、1 Slot破損だけで他のSlot一覧を失敗させません。

### Continue Latest

`continue_latest()`

Metadata上の最新候補から実際にLoadを試し、最初のLoad可能Slotを返します。

Latest timestampだけを見てFuture Schemaや壊れたSaveを成功扱いしません。

### New Game

`create_new_game(payload, options)`

`slot_id` を渡せばそのIDで明示Createします。省略時は衝突しないGenerated IDを使います。

どちらも `create_slot()` と同じExisting Artifact Guardを通るため、New Gameで既存Slotを暗黙上書きしません。

## Delete

`delete_slot(slot_id)` はPrimaryを直接消す前にActive namespace外の一時名へrenameします。

その後Backup / Tempも削除します。

これによりDelete成功後、古いRuntime Stateが `save_slot()` を呼んでもPrimary不在のため同じSlotを自動復活させません。

UI上の確認DialogやTrash UXはGame側の責務です。

## Existing Single Save Compatibility

Phase 14は次を変更しません。

- `SaveSystem.DEFAULT_SAVE_PATH = user://save.json`
- 既存 `save_game(payload, version, path)`
- `FoundationRuntime` のSingle Save lifecycle

複数Slotが不要なGameはSaveSlotManagerを導入する必要がありません。

## Cloud Extension Boundary

Foundation CoreはLocal Slot Authorityだけを担当します。

`cloud_slot_descriptor(slot_id)` は外部Adapterへ次を渡すためのProvider-neutral descriptorです。

- stable slot_id
- local primary path
- local backup path
- Slot Metadata format/version
- local authority / external provider boundary

Foundation CoreへSteam SDKや特定Cloud Provider dependencyは入れません。

将来のCloud Adapterが担当するもの:

- Remote authentication
- Remote revision / ETag
- Upload / Download
- Offline queue
- Conflict resolution
- Delete tombstone
- Retry / Backoff
- Multi-device reconciliation

Local Save成功とCloud Sync成功は別Stateとして扱います。

## Game側の責務

- Game Payload
- Game Schemaの意味
- Migration
- Slot Display Name / Summary内容
- New Game初期State
- Continue後のRuntime復元
- Delete確認UX
- Cloud Providerを使う場合のAdapter / Conflict UX
