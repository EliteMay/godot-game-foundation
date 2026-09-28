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

## Next Phase 16 Work

- Recovery Screen Contract
- Diagnostics Export Hook
- Crash Marker

Recovery ScreenはError summaryと利用可能ActionをRuntime Stateから構築し、Data削除やResetを暗黙実行しません。
