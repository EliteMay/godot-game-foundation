# Controlled Failure / Recovery

Phase 16 — Controlled Failure / Recovery UXの共通Contractです。

## Runtime Failure State

FoundationRuntimeのFatal initialization failureは、単なるError Resultだけでなく `runtime_failure_state()` から取得できる構造化Stateとして保持します。

Current fields:

- `active`
- `kind`
- `stage`
- `code`
- `message`
- `retry_supported`
- `save_writes_blocked`
- `diagnostics_available`

`status_snapshot()` にも同じStateが含まれます。

### Initialization stages

- `configure`
- `scene_tree`
- `diagnostics`
- `settings`
- `input`
- `flow`
- `runtime_test`

Save initializationは既存設計どおり非Fatalです。Load / Restore failure時はSave writeをblockして既存Dataを保護し、Runtime全体のinitialization fatalへ自動変換しません。

## Signals

`FoundationRuntime`:

- `initialization_failed(result, state)`
- `runtime_failure_changed(state)`

後続のRecovery ScreenはこのStateを表示用Dataとして利用できますが、Game StateやSave Fileを直接変更するAuthorityにはしません。

## Retry Safety

Current `retry_supported=true`:

- `configure`
- `scene_tree`

これらはsubsystem初期化前で、同じRuntime instanceを再試行してもpartial service duplicationが発生しないstageです。

Diagnostics / Settings / Input / Flow / Runtime Test途中のFailureは、現時点では `retry_supported=false` とします。

これは「復旧不能」という意味ではありません。安全なcleanup / rebuild Contractがまだ保証されていないため、Recovery UIが無条件Retryを提示してはいけないという意味です。

## Success Clear

Failure後に安全な再試行が成功した場合:

- Failure Stateをinactiveへ戻す
- `runtime_failure_changed` を再発火する
- `status_snapshot().has_runtime_failure=false` になる

Recovery ScreenはError summaryと利用可能ActionをRuntime Stateから構築し、Data削除やResetを暗黙実行しません。


## Recovery Screen Contract

`RecoveryScreenContract` はRuntime Failure StateをUser-facing recovery actionへ変換する非Visual Contractです。

Supported semantic actions:

- `retry`
- `main_menu`
- `safe_quit`

### Action availability

`retry` はRuntime Failure Stateの `retry_supported=true` の場合だけ利用可能です。

ScreenやGame側がError codeだけを見て独自にRetry可否を推測しません。

`main_menu` は次のどちらかがある場合だけ利用可能です。

- Game側 `main_menu_action`
- RuntimeのGame Flow Serviceに有効なMain Menu IDと `go_to_main_menu()`

`safe_quit` は次のどちらかを使います。

- Game側 `safe_quit_action`
- FoundationRuntime `request_quit(1)`

Recovery ContractはSave file削除、Settings reset、Slot delete等の破壊的Actionを暗黙提供しません。

### Optional Recovery Screen

`recovery/recovery_screen.tscn` は共通Fallback UIです。

表示対象:

- User-facing failure message
- stage / code
- Save write protection state
- Diagnostics availability
- 現在利用可能なRecovery Action

Main Menu / Pause Menuと同じ `TranslationContract` と `FocusNavigationBaseline` を利用します。

Game側は `translation_entries` または `labels` で表示文言を差し替えられます。

Retry成功後にRuntime Failure Stateがinactiveになった場合、Screenは自動で閉じて `recovery_succeeded` を通知します。

### Safety boundary

Recovery ScreenはActionの入口であり、Project DataのAuthorityではありません。

- Save / Slot / Settingsの削除を行わない
- unsupported Retryを表示しない
- Main Menu未設定時に存在すると見せない
- Safe Quit failureを成功扱いしない
- Diagnostics exportは専用 `DiagnosticsExportHook` へ分離する

Headless SmokeではAction availability、focus、translation override、Retry close、Save protection表示を確認します。

実Game Themeでのcontrast、狭いViewport、長いLocalized message、物理Controller Focus視認性はRuntime / Visual Validation対象です。


## Diagnostics Export Hook

Recovery ScreenやGame Dev Hubから診断情報を共有する場合は、内部 `diagnostics_snapshot()` を直接送信せず `FoundationRuntime.diagnostics_export()` を使います。

Export Hookは内部Snapshotを共有用Schemaへ再構築し、RuntimeのDomain-bearing fieldsをホワイトリスト外にします。

主なSafety:

- Save Payload / Settings / Input Dataを含めない
- Absolute PathをRedaction
- Known sensitive key / token patternをRedaction
- Recent Log / Error / String / Collectionをbounded化
- JSON全体を128 KiB以下へ制限
- Network送信やUploadはFoundation外

このHookは「既知のSecret Patternを除去する共有境界」です。Game側がSecretをLogへ記録してよいという意味ではありません。Secretは最初からDiagnostics Contextへ入れないことを基本とします。


## Crash Marker

`recovery/crash_marker.gd` は、前回Foundation Runtime Sessionが正常Cleanupされなかった**可能性**を次回起動時に知らせるOptionalなLightweight Markerです。

### Config

```gdscript
{
    "crash_marker": {
        "enabled": true,
        "path": "user://foundation_session_marker.json",
    }
}
```

既定は `enabled=false` です。既存Gameへ新しいFile writeを自動追加しません。

Marker pathは `user://` のみ許可します。

### Lifecycle

Session開始時:

1. 既存Markerを読む
2. 既存Markerが残っていれば `possible_unclean_exit=true`
3. 現在Session用Markerへ置き換える
4. Runtime Status / Diagnostics Exportから前回Session evidenceを確認できる

Clean shutdown時:

- Game Flow Safe QuitではSave hookの後にMarker cleanupを実行
- Save hookが失敗してQuitがBlockされた場合、Marker cleanupまで進まない
- Window close requestではbest-effort cleanup
- RuntimeがSceneTreeから正常に外れる時もbest-effort cleanup
- Marker cleanup失敗だけでGame終了はBlockしない

### Ownership

Markerには内部Session IDを持たせます。

Cleanup時に現在FileのSession IDが自分と一致する場合だけ削除します。

これにより、古いRuntime instanceが後から終了しても、新しいSessionのMarkerを削除しません。

Session ID自体はDiagnostics Exportへ含めません。

### Interpretation

Marker残存はCrash確定を意味しません。

返す情報は `possible_unclean_exit` であり、考えられる理由には次があります。

- hard crash
- process kill
- power loss
- shutdown中断
- cleanup failure
- concurrent / multiple instance
- Marker file corruption

OSやPlatformがProcessを停止する全経路をGodot scriptだけで完全捕捉できるわけではありません。

GodotのWindow close requestはdesktopでNode notificationとして取得できますが、`SceneTree.quit()` はその通知を自動送信しないため、FoundationRuntimeの明示Safe Quit pathとRuntime teardownでもCleanupを行います。

### Diagnostics

`status_snapshot().crash_marker` から内部状態を取得できます。

`diagnostics_export()` は共有用に次だけをWhitelistします。

- Crash Marker enabled
- current marker active
- previous marker found / valid
- `possible_unclean_exit`
- reason
- previous start timestamp
- previous App / Foundation Version

Current Session IDやMarker Pathは共有しません。
