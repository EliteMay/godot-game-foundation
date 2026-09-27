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

Generic Option ControlsとInput Remap UIはPhase 12の後続Taskです。
