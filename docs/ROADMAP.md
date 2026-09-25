# Development Roadmap

## Phase 0 — Foundation / Architecture

状態: **基盤作成済み**

目的: 特定ゲームへ依存しない再利用Repositoryとして、構造・境界・検証方法を確定する。

- [x] Repository初期化
  - 担当: ChatGPT
  - READMEへFoundationの目的と対象外を明記する
- [x] Godot Project Harness
  - 担当: ChatGPT
  - Godot 4.7.2 stableで開ける最小Projectを用意する
  - Demo SceneはFoundation開発用に限定し、Game側Dependencyにしない
- [x] 再利用Code領域
  - 担当: ChatGPT
  - `addons/game_foundation/` をFoundation本体として固定する
  - Game固有Codeを入れない方針をArchitectureへ記録する
- [x] Architecture
  - 担当: ChatGPT
  - Game Dev Hub / Foundation / 各Game Repositoryの3層責務を定義する
  - Game Adapter方式でDomain StateとFoundation Systemを分離する
- [x] Project Structure
  - 担当: ChatGPT
  - Demo / Test / Docs / Addonの責務を文書化する
- [x] CI
  - 担当: ChatGPT
  - Import前のDirect Cold Startを検証する
  - Import / Main Scene / Foundation Smokeを検証する
  - `SCRIPT ERROR` / `ERROR:` をCI失敗として扱う
- [x] Foundation Smoke Test
  - 担当: ChatGPT
  - Foundation metadataと最小CapabilityをBehavior Testする

完了条件:
RepositoryがGodot 4.7.2でCold Startでき、Foundation本体とGame固有領域の境界が明文化され、CIで最小Foundationを検証できる。

## Phase 1 — Generic Save System

状態: **完了 / Headless Smoke Test済み**

目的: Game固有Stateを知らずに利用できる、安全なSave / Load基盤を作る。

- [x] Save Payload Contract
  - 担当: ChatGPT
  - Foundationが受け取るPayloadをJSON互換Dictionaryに限定する
  - Game固有FieldをFoundationへ定義しない
  - MetadataとGame Payloadを分離する
  - String以外のDictionary KeyやJSON非対応型は保存前に拒否する
- [x] Save Version
  - 担当: ChatGPT
  - Foundation Schema VersionとGame Schema Versionを別々に保持する
  - 古いFoundation Schema / 未知の新しいFoundation Schema / Game Version差を区別して返す
  - 非対応の新Versionを既存Saveへ上書きせず安全に拒否する
- [x] Atomic Save
  - 担当: ChatGPT
  - 同Directoryの一時Fileへ完全なJSONを書き、再読込Validation後に本番Pathへrenameする
  - rename失敗時は既存Saveを残し、一時Fileを削除してErrorを返す
- [x] Backup
  - 担当: ChatGPT
  - 正常な既存Saveを更新前に `.bak` へ保持する
  - 正常Load時にもPrimaryをBackupへ同期できる
  - Primary破損時は対応VersionのBackupを自動で試す
- [x] Load Validation
  - 担当: ChatGPT
  - JSON Parse失敗、必須Metadata欠落、Payload不正、非対応VersionをResult Codeで返す
  - Load失敗でGameをCrashさせない
  - 非対応の新Versionでは古いBackupへ勝手に戻らず、Data Lossを避ける
- [x] Migration Hook
  - 担当: ChatGPT
  - 保存Game Schemaが現在より古い場合、Game側CallableへPayload Migrationを委譲する
  - Migration後のPayloadもJSON互換性を再Validationする
- [x] Auto Save API
  - 担当: ChatGPT
  - `AutoSaveService.request_save()` でGame側Eventから保存要求を出せる
  - 短時間の連続要求をDebounceし、最後のStateを保存する
  - Safe Quit等から `flush_pending()` で待機中Saveを即時確定できる
- [x] Save System Smoke Test
  - 担当: ChatGPT
  - Payload Contract、Save → Load、Atomic置換、Backup Recovery、Version mismatch、Migration、Auto SaveをHeadlessで検証する

完了条件:
任意のJSON互換Game Payloadを安全に保存・読込でき、破損やVersion差で既存Saveを壊さない。

## Phase 2 — Settings System

状態: **完了 / Headless Smoke Test済み**

- [x] Settings Schema
  - 担当: ChatGPT
  - Foundation共通Settingを `audio` / `display` に固定し、Game固有Settingは `gameplay` へ分離する
  - InvalidなCommon Settingは起動不能にせず安全なDefaultへNormalizeする
  - Settings FileはSave Dataと別の `user://settings.json` に保存する
- [x] Audio Settings
  - 担当: ChatGPT
  - Master / BGM / SFXを0.0〜1.0で扱う
  - Runtime適用時のAudio Bus名はGame側からMappingを差し替えられる
  - 存在しないBusはCrashさせずResultへmissingとして返す
- [x] Display Settings
  - 担当: ChatGPT
  - Windowed / Fullscreen / Borderlessを扱う
  - ResolutionとVSyncを保存・復元できる
  - 不正Resolutionは安全範囲へClampし、不正Mode / VSyncはDefaultへ戻す
  - HeadlessではDisplay適用を安全にskipする
- [x] Gameplay Settings Extension
  - 担当: ChatGPT
  - Mouse Sensitivity等のGame固有SettingをFoundation改造なしで `gameplay` へ追加できる
  - Game Defaultと保存済みSettingをDeep Mergeし、新規Setting追加時に不足Defaultを補う
  - FoundationはJSON互換性だけを保証し、Game固有の意味ValidationはGame側へ残す
- [x] Settings Persistence
  - 担当: ChatGPT
  - 一時Fileで検証してからPrimaryへrenameする
  - 正常な既存Settingsを `.bak` へ保持する
  - Primary破損時はBackupを試し、利用不能ならDefault Settingsで安全に起動する
  - Reset APIでPrimary / Backup / Tempを削除してDefaultへ戻せる
- [x] Settings Smoke Test
  - 担当: ChatGPT
  - Default / Normalize / Gameplay Extension / Save / Load / Backup Recovery / ResetをHeadlessで検証する
  - HeadlessでRuntime Applyが安全にskipされることを確認する

完了条件:
共通Settingを保存・復元でき、Game固有SettingをFoundation改造なしで追加できる。

## Phase 3 — Input System

状態: **完了 / Headless Smoke Test済み**

- [x] Input Action Contract
  - 担当: ChatGPT
  - Game固有Action名をFoundationへ固定しない
  - Game側がAction名、Deadzone、Default EventをDictionary Contractとして渡す
  - Contract外のActionをFoundationが勝手に作成・変更しない
  - 不正Action名、Deadzone、Event Descriptorを適用前に拒否する
- [x] Key Rebind
  - 担当: ChatGPT
  - Contractで宣言されたActionだけをInputMap上でRebindできる
  - Keyboard / Mouse / Gamepad Eventを共通DescriptorへSerialize / Deserializeする
  - 現在Bindingを `user://input_bindings.json` へ保存し、次回起動時に復元できる
  - 保存Fileに存在しない新ActionはGame ContractのDefaultを使う
- [x] Reset to Default
  - 担当: ChatGPT
  - Gameが定義したDefault BindingへAction単位ではなくContract全体を安全に戻せる
  - InputMapにActionが無ければ作成し、既存ActionはDeadzoneとEventをDefaultへ置換する
  - Binding Fileが無い・壊れている場合もDefaultへFallbackする
- [x] Keyboard / Mouse
  - 担当: ChatGPT
  - Keyboardはkeycode / physical_keycodeとModifierを保存できる
  - Mouse ButtonとModifierを保存できる
  - Mouse Motion自体はAction Bindingに含めず、SensitivityはSettings SystemのGame拡張Settingへ残す
- [x] Gamepad拡張点
  - 担当: ChatGPT
  - Joypad ButtonとJoypad Motion / Axisを同じDescriptor形式で保存・復元できる
  - Deviceを固定しない `-1` Bindingを扱えるData Modelにする
  - Gamepad UIは固定せず、将来のRebind UIから同じAPIを利用できる
- [x] Input Smoke Test
  - 担当: ChatGPT
  - Contract検証、Default適用、Keyboard Rebind、Save / Restore、ResetをHeadlessで検証する
  - Mouse / Joypad Button / Joypad MotionがSerialize / Deserializeされることを確認する
  - 壊れたBinding FileとFile未作成時にDefaultへ安全に戻ることを確認する

完了条件:
Game側が定義したInput Actionを、Foundationの共通APIから安全にRebind・保存・復元できる。

## Phase 4 — Game Flow

状態: **完了 / Headless Smoke Test済み**

- [x] Pause Service
  - 担当: ChatGPT
  - `SceneTree.paused` を共通Serviceから変更・取得できる
  - `toggle_pause()` と `pause_changed` Signalを提供する
  - Service自身はPause中も動ける `PROCESS_MODE_ALWAYS` とする
  - Pause KeyやPause Menu UIはGame側へ残す
- [x] Scene Transition
  - 担当: ChatGPT
  - Game側がLogical Scene ID → `res://*.tscn` PathのContractを渡す
  - Contract外Sceneや不正Pathを安全に拒否する
  - SceneをPackedSceneとしてLoadできるか確認してから `change_scene_to_file()` を呼ぶ
  - Scene切替時はPause状態を解除する
- [x] Main Menu Contract
  - 担当: ChatGPT
  - Game側が任意のLogical IDをMain Menuとして登録できる
  - Foundationは `main_menu` などの固定Scene名を要求しない
  - Main Menuを持たないGameでは未設定のまま利用できる
- [x] Safe Quit Hook
  - 担当: ChatGPT
  - Save / Settings flush等を終了前Hookとして複数登録できる
  - Hookが `false` または `{ ok: false }` を返した場合は終了を中止する
  - 全Hook成功時だけ `SceneTree.quit()` を呼ぶ
  - Duplicate登録、解除、全解除を扱える
- [x] Flow Smoke Test
  - 担当: ChatGPT
  - Scene Contract検証・Scene Resolve / LoadをHeadlessで確認する
  - Pause / Resume / SignalをHeadlessで確認する
  - Safe Quit Hook成功・Block・解除を確認する
  - Smoke Test終了時にSceneTreeを必ずUnpauseへ戻す

完了条件:
Game固有Scene名を固定せず、Pause・Scene切替・Main Menu・終了前処理を共通化できる。

## Phase 5 — Diagnostics

状態: **完了 / Headless Smoke Test済み**

- [x] Runtime Version Info
  - 担当: ChatGPT
  - App / Foundation / Godot VersionをSnapshotへまとめる
  - OS / OS Version / Display Server / Headless / Debug Build / Processor Countを取得する
  - Home Directory等の実Pathは既定で収集しない
- [x] Log Service
  - 担当: ChatGPT
  - Info / Warning / Errorを共通Entry形式でMemoryとDiskへ記録する
  - Memory Entry数を上限付きにして長時間実行で増え続けないようにする
  - Disk Logは既定1 MiBで1世代Rotationする
  - Godot固有型を含むContextは安全な文字列へ変換する
- [x] Debug Overlay
  - 担当: ChatGPT
  - App / Foundation / Godot Version、OS、FPS、Path、Error件数を暗いOverlayで表示する
  - 最近のErrorをOverlay上で確認できる
  - Overlayを開くKeyはFoundationへ固定せずGame側Input Contractへ残す
- [x] Save / Settings Path表示
  - 担当: ChatGPT
  - Diagnostics ServiceへGame側が共有してよいVirtual Pathを登録できる
  - `user://save.json` / `user://settings.json` / Input / Log等をSnapshotとOverlayへ表示する
  - 実User DirectoryへGlobalizeせず共有時のPrivacyを守る
- [x] Error Summary
  - 担当: ChatGPT
  - Info / Warning / Error件数を集計する
  - 最近のError最大10件を取得できる
  - `build_snapshot()` でRuntime / Path / Error / Recent Log / FPSを1つにまとめる
- [x] Diagnostics Smoke Test
  - 担当: ChatGPT
  - Runtime Info、Log File書込、Context Sanitization、Error SummaryをHeadlessで検証する
  - Save / Settings PathがSnapshotへ含まれることを確認する
  - Debug OverlayのText生成と表示ToggleをHeadlessで確認する
  - Memory / Log File Clearを確認する

完了条件:
ユーザーから共有された診断情報だけで、Version・保存先・主要Errorを追跡しやすい。

## Phase 6 — Windows Build

- [ ] Windows Export Preset
- [ ] CI Export
- [ ] Artifact
- [ ] Version埋め込み
- [ ] Release手順

完了条件:
Foundation StarterをWindows向けに再現可能な方法でBuildできる。

## Phase 7 — Starter Template / Game Dev Hub

- [ ] 新規Game生成仕様
- [ ] Foundation導入方式決定
- [ ] Game Dev HubへTemplate選択追加
- [ ] Foundation Version表示
- [ ] Foundation更新導線
- [ ] Template生成Test

完了条件:
Game Dev HubからFoundationを使った新しいGodot Gameを迷わず作成できる。

## Phase 8 — Deep Factory Pilot

- [ ] Pilot導入前Regression確認
- [ ] Save System導入
- [ ] Settings導入
- [ ] Input System導入
- [ ] Game Flow導入
- [ ] Windows実機回帰確認
- [ ] FoundationへLearnings還元

完了条件:
Deep Factoryの既存Gameplayを壊さずFoundationを実利用でき、汎用化の問題点がFoundationへ反映される。

### 2026-09-25 Generic Save System

Phase 1を特定GameのState構造へ依存しない形で実装した。

- Save FileはFoundation MetadataとGame Payloadを分離
- Foundation Schema / Game Schemaを別Versionとして保持
- JSON互換性を保存前とLoad時にValidation
- 一時FileからのrenameでPrimary Saveを置換
- 既存の正常SaveをBackupとして保持
- Primary破損時のみBackup Recovery
- Game Schemaが古い場合はGame側Migration Callableへ委譲
- Debounce可能なAutoSaveServiceを追加
- Headless Smoke TestでSave / Load / Backup / Version / Migration / Auto Saveを検証

FoundationはGame固有のField名を一切解釈しない。何を保存するか、どのGameplay EventでAuto Saveを要求するかはGame側の責務とする。

### 2026-09-25 Settings System

Phase 2をGame固有UIやGameplayへ依存しない形で実装した。

- Audio / DisplayをFoundation共通Schemaとして定義
- Game固有Settingは `gameplay` Containerへ分離
- Invalid値を安全なDefaultへNormalize
- Settings専用FileへAtomic Save
- Backup RecoveryとResetを追加
- Audio Bus MappingをGame側から差し替え可能
- Headless環境ではRuntime Applyを安全にskip
- Headless Smoke TestでDefault / Invalid Value / Persistence / Recovery / Resetを検証

Settings UI自体は各Gameの見た目・操作へ依存するためFoundationへ固定せず、Phase 7のStarter Templateで再利用UIを追加するか判断する。

### 2026-09-25 Input System

Phase 3をGame固有Action名へ依存しないContract方式で実装した。

- Game側がAction名 / Deadzone / Default Bindingを定義
- Contract外ActionをFoundationが変更しない
- Keyboard / Mouse Button / Joypad Button / Joypad Motionを共通Descriptor化
- InputMapへのDefault適用、Rebind、現在Binding取得を追加
- `user://input_bindings.json` へAtomic Save
- Game Updateで新Actionが増えた場合は保存済みBindingとDefaultをMerge
- File欠落・JSON破損・Schema不一致時はDefault Bindingへ安全にFallback
- Headless Smoke TestでKeyboard / Mouse / Gamepad Data ModelとSave / Restoreを検証

Key Conflictの扱いと実際のRebind UIはGameのUXに依存するためFoundation Coreへ固定せず、Phase 7のStarter Templateで共通UI候補を検討する。

### 2026-09-25 Game Flow

Phase 4をGame固有Scene名やUIへ依存しないServiceとして実装した。

- Logical Scene ID → Scene PathのContract方式
- Scene Resolve / Load / Change API
- 任意のLogical IDをMain Menuとして登録
- SceneTree Pause / Resume / ToggleとSignal
- Pause中もService自身は動作
- Save等を終了前にflushするSafe Quit Hook
- Hook失敗時は終了を中止してData Lossを避ける
- Headless Smoke TestでContract / Pause / Quit Hookを検証

Pause Menu、Transition Animation、Loading Screen、Quit確認DialogはGameごとのUXに依存するためFoundation Coreへ固定しない。

### 2026-09-25 Diagnostics

Phase 5をGame固有Stateを勝手に収集しない共通診断基盤として実装した。

- App / Foundation / Godot / OS Runtime Info
- Bounded Memory Logと `user://logs/runtime.log` Disk Log
- 1 MiBを既定とする1世代Log Rotation
- Info / Warning / Error件数とRecent Error Summary
- Save / Settings / Input / Log等のVirtual Path表示
- FPSと主要情報をまとめるDiagnostics Snapshot
- 開発用Dark Debug Overlay
- Home Directory / IP / Hardware ID等を既定で収集しないPrivacy方針
- Headless Smoke TestでLog / Summary / Overlay / Path表示を検証

Game Dev Hubの共有Reportへ接続する際は、Foundation Snapshotをそのまま全送信するのではなく、Game側が共有対象を選べる形を維持する。
