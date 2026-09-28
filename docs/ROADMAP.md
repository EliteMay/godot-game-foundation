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

状態: **完了 / CI Windows Export確認済み**

- [x] Windows Export Preset
  - 担当: ChatGPT
  - `export_presets.cfg` に `Windows Desktop` Presetを追加する
  - x86_64 Release Buildを基準にする
  - PCKをEXEへEmbedして単一Executableとして扱いやすくする
  - Product Name / File Description等のWindows Resource Metadataを有効化する
  - Code SigningはCertificate未設定のため無効のままにし、SecretをRepositoryへ持ち込まない
- [x] CI Export
  - 担当: ChatGPT
  - Godot 4.7.2 Editorと同Version Export TemplatesをCIで取得する
  - Project Import後に `--export-release "Windows Desktop"` でWindows EXEを生成する
  - Export LogのScript Error / Errorと生成File有無を検証する
  - 生成FileがPE形式であることをCIで確認する
- [x] Artifact
  - 担当: ChatGPT
  - Windows EXEと `build-info.json` をGitHub Actions ArtifactへUploadする
  - Artifact名にCommit SHAを含めてSourceを追跡できるようにする
  - 保持期間を14日に設定する
- [x] Version埋め込み
  - 担当: ChatGPT
  - Foundation Harnessの `application/config/version` をVersion Sourceとする
  - Windows ResourceのFile / Product VersionはProject VersionへFallbackさせる
  - Foundation HarnessではApp Versionと `FOUNDATION_VERSION` の一致をSmoke Testで保証する
  - ArtifactへCommit / Ref / Godot Version / Architecture / Signing状態を含むBuild Metadataを追加する
- [x] Release手順
  - 担当: ChatGPT
  - `docs/WINDOWS_BUILD.md` にVersion更新 → CI → Tag → Artifact → GitHub Releaseの手順を記録する
  - `v*` TagでもWindows Build Workflowを実行する
  - GitHub Release公開自体は誤公開防止のため明示操作に残す
  - 本番GameのCode Signing CredentialはSecret / Environment等から渡す方針を記録する
- [x] Build Config Smoke Test
  - 担当: ChatGPT
  - Project Version、Preset名、Platform、Architecture、Embed PCK、Resource Metadata、Unsigned状態をHeadlessで検証する
  - 通常のGodot CIにも追加し、Build Workflowを走らせる前に設定崩れを検出できるようにする

完了条件:
Foundation StarterをWindows向けに再現可能な方法でBuildでき、同じCommitから作られたWindows ArtifactとVersion情報を追跡できる。

## Phase 7 — Starter Template / Game Dev Hub

状態: **完了 / Windows実機確認済み**

- [x] 新規Game生成仕様
  - 担当: ChatGPT
  - `foundation-template.json` を機械可読なStarter配布Contractとして定義する
  - Starter source → target file mapping、Token、Godot baseline、Foundation versionをManifestへ持たせる
  - 生成Gameには `.game-foundation.json` を作り、導入Version / Commit / Managed Pathを追跡する
  - 既存FileがあるRepositoryへ自動上書き生成しない
- [x] Foundation導入方式決定
  - 担当: ChatGPT
  - Git submodule / subtreeをDefaultにせず、Game Dev HubによるManaged Path Copy方式を採用する
  - Foundation更新対象を `addons/game_foundation/` に限定する
  - Gameの `project.godot` / Roadmap / scenes / scripts / tests / assetsは更新時に自動上書きしない
  - Update後のCommit / PushはHub既存の明示保存Flowへ分離する
- [x] Game Dev HubへTemplate選択追加
  - 担当: ChatGPT
  - Game Dev Hub v0.1.12へ「Foundationから新しいゲームを作る」Flowを追加した
  - 空のGitHub RepositoryをClone → Starter生成 → Initial Commit → Push → Hub登録まで専用IPCで実行する
  - Rendererへ汎用Filesystem / Shell Capabilityを公開しない
- [x] Foundation Version表示
  - 担当: ChatGPT
  - Hubが `.game-foundation.json` を読み、導入Version / CommitをGame詳細へ表示する
  - 未導入Gameと不正Metadataを区別する
- [x] Foundation更新導線
  - 担当: ChatGPT
  - Hubの明示「基盤を更新」から最新版を取得する
  - expected origin / branch、clean worktree、未Push Commitなしを確認してから更新する
  - ManifestとInstallation MetadataのManaged Path一致を検証し、`addons/game_foundation/` だけ更新する
  - 更新後は既存「GitHubに保存」でDiff確認・Commit / Pushする
- [x] Template生成Test
  - 担当: ChatGPT
  - Foundation側Manifest / Starter SourceをHeadless Smoke Testで検証する
  - 実際にStarterを一時ProjectへMaterializeし、Godot Import / Main Scene / Foundation Integration SmokeをCIで検証する
  - Game Dev Hub側でToken展開 / Metadata生成 / Managed Path限定更新 / 既存File保護をNode Testで検証する
  - Foundation mainとGame Dev Hub mainのCI / Windows build成功を確認した
- [x] Windows実機でStarter Create / Update確認
  - 担当: あなた
  - Game Dev Hub v0.1.12以降へ更新する
  - GitHubでFileのない空Repositoryを1つ用意する
  - Hubの「Foundationから新しいゲームを作る」でゲーム名とRepository URLを入力して作成する
  - 作成したGameが一覧へ追加され、Game Foundationに `v0.8.0-dev` と導入Commitが表示されることを確認する
  - 「ゲームを起動」でStarter画面が開くことを確認する
  - 「基盤を更新」を押し、最新版なら安全に「すでに最新版」と扱われることを確認する
  - 確認結果はGame Dev Hubの共有パックまたはこの会話へまとめて返す

完了条件:
Game Dev HubからFoundation付きGameを作成・起動でき、導入Versionを確認しながらFoundation管理領域だけ安全に更新できることをWindows実機で確認する。

## Phase 8 — Deep Factory Pilot

状態: **完了 / Windows実機回帰確認済み**

- [x] Pilot導入前Regression確認
  - 担当: ChatGPT
  - Deep Factory Phase 1〜5の既存Windows実機Evidenceを保持し、説明変更だけを理由に再確認させない
  - Pilot統合後も既存Input / Upgrade / Core Loop / First Automation Smoke TestをCIで実行する
  - Deep Factory main commit `4b1060cc` のGodot CI成功を確認する
- [x] Save System導入
  - 担当: ChatGPT
  - Deep Factory固有PayloadはGame側へ残し、Save envelope / Atomic write / Backup / Version guardをFoundationへ委譲する
  - 起動時Load、主要進行変更時Auto Save、15秒Periodic Save、Safe Quit Saveを接続する
  - Money / Inventory / Upgrade / Player位置 / Small Miner位置・Storageを復元する
  - Primary破損時のBackup RecoveryをCIで確認する
- [x] Settings導入
  - 担当: ChatGPT
  - Foundation Settings SystemへAudio / Display / Mouse Sensitivity defaultを接続する
  - Game固有SettingはGameplay extensionとして保持する
- [x] Input System導入
  - 担当: ChatGPT
  - Deep FactoryのInput Action定義をFoundation Input Contractへ接続する
  - Game固有Action名をFoundation本体へ固定しない
- [x] Game Flow導入
  - 担当: ChatGPT
  - Foundation Game Flow ServiceをRuntimeへ追加する
  - Safe Quit Hookから最新Saveを確定して終了する
  - Prototype 0.1に不要なMain Menu / Pause UIは無理に追加しない
- [x] Windows実機回帰確認
  - 担当: あなた
  - Game Dev HubでDeep Factoryを最新版へ同期し、Game Foundation欄に `v0.8.0-dev` が表示されることを確認する
  - 所持金・鉱石・Upgrade・小型採掘機がある状態まで進めてゲームを終了する
  - Game Dev Hubからもう一度起動し、Player位置と主要進行が復元されることを確認する
  - 小型採掘機の設置位置と内部Storage数が再起動前と一致することを確認する
  - 復元後も採掘・回収・売却・Upgrade・自動生成が通常通り続けられることを確認する
  - 結果はGame Dev Hubの確認結果へまとめて記録する
  - 2026-09-28のGame Dev Hub v0.1.24共有パックで6項目すべてPassを確認した
- [x] FoundationへLearnings還元
  - 担当: ChatGPT
  - Windows実機回帰結果とDeep Factory Pilotで判明したFoundation側の改善点を整理する
  - Game固有問題とFoundation共通問題を分け、共通問題だけFoundationへ反映する
  - 今回の実機回帰では新しいFoundation共通不具合は検出されず、既存Save / Restore / Flow Contractが実Gameでも成立するEvidenceとして記録した
  - 追加のRuntime Code変更は不要と判断し、Evidenceと再利用上のLearningだけを文書へ反映した

完了条件:
Deep Factoryの既存Gameplayを壊さずFoundationを実利用でき、汎用化の問題点がFoundationへ反映される。

## Phase 9 — Runtime Test Bridge

状態: **完了 / CI・Windows実機E2E確認済み**

目的: 固定テストをVision AIのScreenshot判定から分離し、Game内部StateをPrimary Evidenceとして高速・安定に検証できる共通Bridgeを提供する。

- [x] Local State Bridge
  - 担当: ChatGPT
  - Hubが指定したAbsolute JSON PathへRuntime State Snapshotを書き出す
  - Network Listenerや任意Command Channelは追加しない
- [x] Game Provider Contract
  - 担当: ChatGPT
  - Game固有FieldをFoundationへ固定せず、Callableが返すJSON互換Dictionaryを受け取る
  - Secretや個人Pathを自動収集しない
- [x] Explicit Test Activation
  - 担当: ChatGPT
  - `--foundation-test-state` / `--foundation-test-session` があるRunだけ有効にする
  - 通常起動ではFile出力しない
- [x] Snapshot Envelope
  - 担当: ChatGPT
  - Schema / Session / Sequence / Timestamp / Process / Game Versionを付加する
  - Hubが別Runの古いSnapshotを誤採用しないようSession IDを照合可能にする
- [x] Smoke Test
  - 担当: ChatGPT
  - Provider State保存、Envelope、JSON Contract、不正Provider拒否をHeadlessで検証する
- [x] Windows実機E2E
  - 担当: ChatGPT / あなた
  - Game Dev Hub v0.1.24からDeep Factoryを固定テストし、Game起動 / WASD / Mouseを3/3 PASS
  - Session一致、Player position差分、Camera yaw差分をRuntime Stateから直接確認する

完了条件:
Foundation単体CIでRuntime Test BridgeのState出力Contractが通り、通常RunへNetwork/Command capabilityを追加せずGame Dev HubからDeterministic Testへ利用でき、Windows実機でState-based fixed testが成立する。

## Phase 10 — Integrated Foundation Runtime

状態: **完了 / CI・Windows Starter実機確認済み**

目的: Save / Settings / Input / Flow / Diagnostics / Runtime Test BridgeをGameごとに毎回手動配線せず、Game固有Contractだけ渡して安全に初期化できる共通Lifecycleを作る。

- [x] FoundationRuntime
  - 担当: ChatGPT
  - 独立Systemを置き換えずLifecycle Coordinatorとして追加する
  - System単位のenable / disableを許可する
  - Game固有StateやAction名をFoundationへ固定しない
- [x] Save Adapter Contract
  - 担当: ChatGPT
  - `capture_save_state` / `restore_save_state` CallableをGame側から受け取る
  - Game Schema Migrationは既存Save SystemのCallableへ委譲する
  - Load / Restore失敗時は既存Save保護のため以後のwriteをblockする
  - Pending Autosave後の明示Saveが古いStateに巻き戻らないよう最新Payloadへ置換してflushする
- [x] Settings / Input / Flow Bootstrap
  - 担当: ChatGPT
  - Settings load / Common runtime apply / Gameplay adapterを統合する
  - Input ContractからBindingを復元する
  - Scene Contract / Main MenuをGame Flowへ設定する
- [x] Diagnostics / Safe Quit
  - 担当: ChatGPT
  - App / Foundation / Path情報をDiagnosticsへ接続する
  - Save enabled時はSafe Quit hookへ最新Snapshot保存を登録する
- [x] Runtime Test Bridge
  - 担当: ChatGPT
  - Game提供State Providerを既存Bridgeへ接続する
  - Test Bridge有効中は通常Save writeを行わない
- [x] Starter Integration
  - 担当: ChatGPT
  - Starter生成直後からFoundationRuntime自体を利用できる状態にする
  - SaveはGame Adapter未定義のためStarter DefaultではOFFにする
  - Materialized Starter CIでRuntime初期化を検証する
- [x] Runtime Smoke Test
  - 担当: ChatGPT
  - New Game、Settings、Input、Flow、DiagnosticsをHeadless確認する
  - Pending Autosave後の明示Saveが古いStateへ戻らないことを確認する
  - Save → LoadでGame AdapterへPayloadが復元されることを確認する
- [x] CI / Windows Build確認
  - 担当: ChatGPT
  - Godot CI / Generated Starter / Windows Exportを通す
  - PR #4でGodot CI / Windows Build成功を確認
- [x] Windows Starter実機確認
  - 担当: あなた
  - この `godot-game-foundation` Repository本体ではなく、Game Dev Hub左側の「Foundationから新しいゲームを作る」からFileのない空Repositoryへ新規Starterを生成する
  - 生成されたGameのGame Foundation表示が `v0.10.0-dev` になっていることを確認する
  - そのGameで「ゲームを起動」を押し、Starter画面に `Godot Game Foundation 0.10.0-dev / Runtime ready` が表示されることを確認する
  - v0.8等の旧Starterは「基盤を更新」だけでは `scripts/main.gd` が更新されないため、この確認には新規v0.10 Starterを使う
  - 2026-09-28にGame Dev Hub v0.1.25から新規 `foundation-runtime-test` Starterを生成し、2項目ともPassを確認した

完了条件:
新規GameがFoundationRuntimeを入口として共通Lifecycleを利用でき、Game固有StateをFoundationへ混ぜず、Headless CIとWindows Starter実機の両方で初期化を確認できる。

## Phase 11 — Application Shell / Scene UX

状態: **実装完了 / Headless Smoke・Windows Build済み / 実Gameでの物理Controller操作は未確認**

参考: `docs/REFERENCE_TEMPLATES.md`

目的: Foundation Starterを「Runtimeが起動するだけ」から、Game固有Visualを固定せずMain / Pause / Options / Loadingの共通外枠を選択利用できる状態へ進める。

- [x] Async Scene Loader
  - 担当: ChatGPT
  - `ResourceLoader.load_threaded_request()` / `load_threaded_get_status()` / `load_threaded_get()` を使い、Background Load / Progress / Failureを扱う
  - 現在のScene ContractをSource of Truthにし、`GameFlowService.resolve_scene_path()` をResolver Callableとして利用する
  - 同一Sceneの二重Requestを `duplicate_request`、別Sceneの同時Requestを `loader_busy` として拒否する
  - Loaded PackedSceneをSignal / `take_loaded_scene()` からConsumerへ渡せる
  - Headless Smoke TestでScene Contract解決、Background Load、Progress、Duplicate / Busy Guard、Invalid Pathを検証する
- [x] Transition Layer
  - 担当: ChatGPT
  - Fade in / outをOptional共通Layerとして提供する
  - Transition duration / color / CanvasLayerをGame側で差し替え可能にする
  - `motion_scale` と `set_reduced_motion()` でAnimationを短縮・無効化できるExtension Pointを持つ
  - Transition中の重複Requestを拒否し、Mouse入力を奪わない
  - Headless Smoke TestでFade out / in、重複拒否、Reduced motion、Motion scaleを検証する
- [x] Loading Screen Contract
  - 担当: ChatGPT
  - Async Scene LoaderのProgress / Loaded / Failureを `state_changed` / `progress_changed` とSnapshotへ正規化して公開する
  - 即時Request失敗もPresentation Stateへ反映し、active load中のduplicate / busy拒否では現在Loading Stateを壊さない
  - Contract自身はVisual Sceneを所有せず、Game側の任意Control / SceneがSignalを購読できる構造にしてFoundation Themeを強制しない
  - Headless Smoke TestでIdle → Failure → Reset → Loading → Loaded、Progress、busy rejection時のState保持を検証する
- [x] Main Menu Shell
  - 担当: ChatGPT
  - New / Continue / OptionsをGame側Callable、Quitを既存Game Flow Safe Quitへ接続するAction slotとして提供する
  - ContinueはAction slotの有無と現在利用可能かを分離し、Save存在判定自体はGame側へ残す
  - 未設定Actionは隠し、設定済みだが利用不能なContinueは無効表示にできる
  - Returning Userでは利用可能なContinue、First-useではNew Gameを初期Focus候補にする
  - Default SceneはLayout / Minimum Sizeのみを提供し、Game固有Logo / Background / Palette / Fontを固定しない
  - Headless Smoke TestでAction routing、Continue availability、Safe Quit block、Label override、Focus初期化、Optional slotを検証する
- [x] Pause Menu Shell
  - 担当: ChatGPT
  - Resume / Options / Main Menu / Quitを既存Game Flow + Game側Options Callableへ接続する
  - Pause入力Action名はGame側Input Contractへ残し、Foundationへ固定しない
  - Pause前のGUI Focus Ownerを保存し、Resume後に有効ならFocusを戻す
  - Main Menu遷移では古いSceneのFocusを復元しない
  - Options / Main Menu / Quitの利用可否をContractから表示状態へ反映できる
  - Default SceneはLayoutだけを提供し、Palette / Font / Logo等のGame Themeを固定しない
  - Headless Smoke TestでPause / Resume / Options / Safe Quit block / Main Menu / Focus restore / Label overrideを検証する
- [x] Controller / Keyboard Focus Baseline
  - 担当: ChatGPT
  - Main / Pause Menuの表示中かつenabledなActionだけをVisual順にFocus graphへ組み込み、hidden / disabled Actionを自動で飛ばす
  - Godot標準UI Focusを使い、物理Key / Gamepad Button名をFoundationへHardcodeしない
  - `manage_focus_navigation=false` でGame固有Focus構成へ完全に委譲できる
  - Main / PauseのSnapshotへ`focused_action_id`を公開し、Runtime Test / Diagnosticsから現在Focusを確認できるようにする
  - 非Modal拡張を閉じ込めないようDefaultは端でWrapせず、Game側追加ControlへのFocus拡張を妨げない
  - Smoke Testでhidden / disabled skip、availability変更後の再構築、`ui_down` / `ui_accept`によるMouseなし操作を検証する

完了条件:
新規StarterがGame固有Themeを固定せず、Optional Shellを有効化するだけでMain Menu → Loading → Game → Pause → Menuの共通Flowを構築できる。

## Phase 12 — Settings / Input UX Components

状態: **実装完了 / Headless Smoke・Windows Build済み / 実Game統合でVisual・Controller確認待ち**

目的: 既存Settings / Input Backendを、各GameでゼロからUIを作らず利用できる再利用Controlへ接続する。

- [x] Settings Edit Session
  - 担当: ChatGPT
  - Persisted Settingsと一時Draftを分離し、Preview中はDiskへ書き込まない
  - Applyは現在DraftをRuntimeへ適用できることを確認してからPersistし、その値を新しいCancel baselineへ進める
  - CancelはSession開始時または直近Apply時点の値をRuntimeへ戻し、未保存Draftを破棄する
  - ResetはGameのGameplay defaultsを含むDefaultをDraftへ読み込み、ApplyするまではSettings Fileを削除・上書きしない
  - Preview apply失敗時は直前Runtime previewへRollbackを試み、失敗Draftを採用しない
  - FoundationRuntimeから現在のSettings / Adapter / Pathを使ってSessionを開始できる
- [x] Generic Option Controls
  - 担当: ChatGPT
  - Toggle / Slider / List / Resolutionを1つのTheme-neutralな共通Row Componentから構築できる
  - Dotted path / String ArrayでSettings Edit SessionのDraftへ安全にBindingする
  - UI変更はSession Draftへだけ書き込み、Preview可否はControlごとに指定できる
  - SessionのReset / Cancel等でDraftが変わった場合はControl表示を自動同期する
  - Sliderのmin / max / step /表示倍率 / suffix、List / ResolutionのLabel / Option構成はGame側から指定する
  - Game Themeを上書きせず親Themeを継承し、物理Inputや最終Options画面構成を固定しない
  - Headless SmokeでToggle / Slider / List / Resolution、nested path、Reset同期、Cancel後disable、範囲外Rejectを検証する
- [x] Input Remap UI
  - 担当: ChatGPT
  - Current Binding / Action表示、Rebind / Cancel、入力待機Stateを持つTheme-neutralなRow Controlを提供する
  - Keyboard / Mouse Button / Joypad Button / Joypad Motionを既存Input SystemのDescriptor / rebind APIへ接続する
  - Joypad Motionは設定可能Threshold未満をdriftとして無視し、採用時は方向を±1へ正規化する
  - Gamepad deviceは既定で-1へ正規化し、特定Controller固定を避ける。必要Gameはpreserve optionで変更できる
  - Internal Action名とGame-facing display nameを別引数として扱う
  - Optional Persistence Callback失敗時はRebind前BindingsへRuntime rollbackを試みる
  - Capture Cancel用の物理KeyをFoundationへHardcodeせず、Button / public APIから停止できる
  - Conflict policyはこのTaskで暗黙実装せず次Taskへ分離する
- [x] Conflict Detection
  - 担当: ChatGPT
  - Current InputMap上の別ActionとCandidate Descriptorを比較し、競合Action / Event index / Descriptorを返す
  - Keyboard / Mouseは同一Descriptor + Modifier、Gamepad ButtonはButton + device overlap、AxisはAxis + direction + device overlapで判定する
  - Gamepad device=-1はwildcardとしてspecific deviceと競合する
  - RejectはRuntimeを変更せずbinding_conflictを返し、Input Remap UIはListeningを継続できる
  - Replaceは競合Actionから一致Eventだけを外し、他のBindingを保持したままTarget Actionへ割り当てる
  - Allowは競合をResultへ残しつつ既存Actionを変更しない
  - Input Remap UIはconflict_policyをGame側Optionとして受け、既定Allowで既存Behaviorを維持する
  - Replace後のPersistence失敗時もInput Remap UIの既存Rollbackで全Actionを変更前へ戻す
- [x] Input Prompt Resolver
  - 担当: ChatGPT
  - Keyboard / Mouseを1つのdevice family、Gamepadを別familyとしてCurrent deviceを追跡する
  - Key release / echo、Mouse release、Gamepad release、Threshold未満のStick drift / Mouse jitterはdevice切替に使わない
  - Current deviceに一致するAction Bindingを優先し、必要なら別device Bindingへ明示Fallbackできる
  - Keyboard / Mouse / Gamepad Button / Gamepad Axisを表示用Textとstableなsemantic Icon keyへ解決する
  - ModifierはTextとIcon keyを分割して返し、複数Glyphを組み合わせられる
  - Gamepad face buttonは特定Controller製品名へ固定せずSouth / East / West / Northのsemantic keyを返す
  - Game側がText / Icon key overrideを渡せるためLocalizationやThird-party Icon Packへ接続できる
  - Third-party Icon Pack本体やController固有AssetはFoundation必須Dependencyにしない

完了条件:
Game側はSettings / Input ContractとThemeだけを渡し、Options / Rebind UIのCommon Behaviorを再利用できる。

## Phase 13 — Audio Service

状態: **実装中 / Global Music・One-shot Audio・Bus Contract・Audio Resource Lifecycle完了**

目的: Settingsの音量適用だけでなく、複数Gameで共通するAudio再生Lifecycleを提供する。

- [x] Global Music
  - 担当: ChatGPT
  - SceneTree.root直下へ移動できるOptional ServiceとしてScene切替を跨ぐLifetimeを提供する
  - Game側AudioStreamを受け取り、Track Asset自体はFoundationへ含めない
  - Play / Stop / Fade in / Fade out / Crossfadeを扱う
  - Crossfadeは2つのAudioStreamPlayerを再利用し、Transition中の重複Requestを拒否する
  - Game側がbus_nameを指定できるが、Busの存在やSettings mappingとの整合は後続Bus Contractへ分離する
  - Game側Autoload等でLifetimeを所有する場合はpersist_across_scenes=falseでRoot昇格を無効化できる
- [x] One-shot Audio
  - 担当: ChatGPT
  - Global SFX / UI / Voice helperを提供する
  - Node2D / Node3DのScene-owned Parentを明示する2D / 3D One-shot helperを提供する
  - Stream / Volume / Pitch / Start position / Tag / Bus overrideを共通Optionとして扱う
  - Finished playerを自動解放し、Spatial ParentがSceneから外れた場合もactive trackingを残さない
  - max_active_playersで同時One-shot生成数を上限化する
  - token単位Stopとstop_allを提供する
  - 特殊なAttenuation / Area / Emission等はGame固有Playerへ残す
- [x] Bus Contract
  - 担当: ChatGPT
  - Settings / Global Music / One-shot Audioが同じGame-defined audio_bus_mapを共有する
  - master / bgm / sfxを共通必須Logical keyとして扱い、ui / voice未指定時はsfxへFallbackする
  - Game固有の追加Logical keyも保持し、Foundationが未知keyを削除しない
  - FoundationRuntimeのsettings.audio_bus_mapをNormalizeし、既存3-key Mappingとの互換性を維持する
  - Global Musicはaudio_bus_mapのbgm、One-shotはsfx / ui / voiceを利用する
  - Legacy bus_name / bus_names APIは互換用に残すが、Shared Contractと同時指定は曖昧Configurationとして拒否する
  - FoundationはAudioServer Busを勝手に作成・Renameせず、存在確認はinspection Resultとして扱う
- [x] Audio Resource Lifecycle
  - 担当: ChatGPT
  - Global Musicはdispose_audio()でFade / Crossfade Tweenを停止し、2 Playerを停止してAudioStream参照を解放する
  - Dispose前のTransition callbackが再configure後のStateを書き換えないようLifecycle Generationで無効化する
  - One-shotはdispose_audio()でGlobal / Spatial Playerをまとめて停止・解放し、再configure可能にする
  - One-shot Service自身がSceneTreeから外れる時も外部Node2D / Node3D配下のSpatial PlayerをCleanupする
  - Finished / explicit Stop / Spatial Parent exit時の既存Cleanupも維持し、Scene切替でOrphanを残さない
- [ ] Audio Smoke Test
  - 担当: ChatGPT
  - Headlessで可能なContractと、Runtimeで必要なPlayback確認を分ける

完了条件:
Game固有Audio AssetをFoundationへ入れず、BGM / SFX / UI / Voiceの共通再生処理を再利用できる。

## Phase 14 — Save Profiles / Slots

状態: **調査完了 / 未実装**

目的: Current Generic Save Systemの安全性を維持したまま、複数SlotやContinue/New Gameに必要な共通管理層を追加する。

- [ ] Slot Metadata
  - 担当: ChatGPT
  - Slot ID / display name / updated time / Game schema / optional summaryをGame Payloadと分離する
- [ ] Slot Lifecycle
  - 担当: ChatGPT
  - list / create / load / save / deleteを安全なID検証付きで提供する
- [ ] Continue Latest
  - 担当: ChatGPT
  - 最新の正常Slotを決定するHelperを提供する
- [ ] New Game Helper
  - 担当: ChatGPT
  - 既存Slotを暗黙破壊せず、新規Slot作成を明示する
- [ ] Existing Save Compatibility
  - 担当: ChatGPT
  - 既存Single Save利用Gameを壊さずOptional layerとして追加する
- [ ] Cloud Extension Boundary
  - 担当: ChatGPT
  - Steam / Cloud providerはCoreへ依存させず将来Adapterを追加できる境界だけ定義する

完了条件:
Single Save Gameを維持したまま、必要Gameでは複数Slot / Continue / New Gameを共通機能として利用できる。

## Phase 15 — Localization / Accessibility Shell

状態: **調査完了 / 未実装**

目的: Menu Shellで繰り返すLocale適用と基本操作Accessibilityを共通化する。

- [ ] Locale Setting Adapter
  - 担当: ChatGPT
  - SettingsからLocaleを読み、`TranslationServer`へ適用する
- [ ] Translation Contract
  - 担当: ChatGPT
  - Foundation ShellのText keyをGame側Translationへ差し替え可能にする
- [ ] Focus / Navigation Baseline
  - 担当: ChatGPT
  - Keyboard / Gamepadで主要Menuを操作できることを共通Contractにする
- [ ] Motion / Feedback Hooks
  - 担当: ChatGPT
  - Reduced motion、UI sound等をGame要件に応じて無効化できるHookを用意する

完了条件:
Foundation ShellがLocaleと基本Focus Navigationへ対応し、特定LanguageやInput Deviceを固定しない。

## Phase 16 — Controlled Failure / Recovery UX

状態: **調査完了 / 未実装**

目的: Foundation initializationやRecoverable fatal conditionが失敗した時に、黒画面・無反応ではなく安全に診断情報へ到達できる共通Flowを作る。

- [ ] Runtime Failure State
  - 担当: ChatGPT
  - FoundationRuntime initialize failureを構造化Stateとして公開する
- [ ] Recovery Screen Contract
  - 担当: ChatGPT
  - Error summary / retry / safe quit / main menu return等をOptional Sceneから実行できる
- [ ] Diagnostics Export Hook
  - 担当: ChatGPT
  - Game Dev Hub共有へ接続しやすいSanitized snapshotを生成する
- [ ] Crash Marker
  - 担当: ChatGPT
  - 前回Sessionが正常終了しなかった可能性を次回起動時に判定できるLightweight markerを検討する
  - OS-level hard crashを完全捕捉できると誤認しない

完了条件:
RecoverableなFoundation failureでGame Stateを壊さず、UserがReasonと次Actionを確認できる。

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

### 2026-09-25 Windows Build

Phase 6としてWindows x86_64の再現可能なBuild経路を追加した。

- Windows Desktop Export Preset
- Project VersionをWindows Resource Version Sourceとして利用
- Build Config Smoke TestでVersion / Preset Driftを検出
- Godot 4.7.2 Export TemplatesをCIでInstall
- Linux RunnerからWindows Release EXEをCross Export
- PE形式とExport Errorを検証
- EXE + build-info.jsonをCommit SHA付きArtifactとしてUpload
- main / PR / v* Tag / 手動実行に対応
- Release手順とUnsigned / Code Signing方針を文書化

Foundation HarnessはUnsignedの検証Artifactまでを共通化する。本番Gameの署名Certificateは各Gameの配布要件に応じてSecret管理する。

### 2026-09-25 Starter Distribution Contract

Phase 7のFoundation側として、Game Dev Hubが直接利用できるStarter配布Contractを追加した。

- `foundation-template.json` を配布Manifestとして追加
- Starter Fileは `.template` Sourceとして保持し、Foundation HarnessのGodot Import対象と混同しない
- FoundationのManaged Pathを `addons/game_foundation/` に限定
- 生成Game側の `.game-foundation.json` 仕様を定義
- SubmoduleではなくManaged Path Copyを採用
- Foundation Update時はGame固有Fileを上書きせず、Commit / PushをHub既存の明示保存Flowへ分離
- Starter Template Smoke Testを追加

Game Dev Hub側の生成・Version表示・更新導線がCIまで通った時点でPhase 7を完了へ更新する。

### 2026-09-25 Game Dev Hub v0.1.12 Integration

Phase 7のGame Dev Hub側実装を `EliteMay/game-dev-hub` へ統合した。

- Hub main merge commit: `4b5f2649`
- Game Dev Hub v0.1.12 Release作成済み
- Node Test成功
- Windows Installer Build成功
- Foundation Version / Commit表示を追加
- Empty RepositoryからのStarter Create Flowを追加
- Managed Path限定Foundation Updateを追加
- 更新後のCommit / Pushは既存User確認Flowへ分離

自動検証は完了している。最終完了判定にはWindows実機でCreate / Start / Update UI Flowを確認する。

### 2026-09-25 Phase 7 Windows実機確認完了

Game Dev Hub共有パックで、Foundation main commit `12a018a2` / Game Dev Hub `0.1.12` / Godot `4.7.2.stable.official.ed1daf0bf` のWindows実機確認7項目がすべてPassし、結果はstaleではなかった。

確認済み:

- Game Dev Hub v0.1.12以降へ更新できる
- Fileのない空GitHub Repositoryを用意できる
- 「Foundationから新しいゲームを作る」でStarter生成できる
- 作成GameがHubへ追加され、Foundation `v0.8.0-dev` と導入Commitが表示される
- 「ゲームを起動」でStarter画面が開く
- 「基盤を更新」で最新版を安全に処理できる
- 共有パックへ確認結果をまとめて返せる

このEvidenceによりPhase 7を完了とし、次のUser実機確認はPhase 8 — Deep Factory PilotのWindows回帰確認とする。

### 2026-09-25 Deep Factory Pilot自動検証

Deep Factory main commit `4b1060cc` へFoundation 0.8.0-dev Pilotを統合済み。

Godot CI run `36095428200` が成功し、既存Gameplay RegressionとFoundation統合の自動検証を通過した。

自動確認済み:

- Direct Cold Start
- Godot Import / Main Scene
- Gameplay Input Smoke
- Upgrade Smoke
- Core Loop Regression
- First Automation Smoke
- Save Model Smoke
- Foundation Pilot Smoke
- Foundation Save / Load / Backup Recovery Smoke

Phase 8の残りはWindows実機での再起動復元確認と、その結果からFoundationへ必要なLearningsを還元する作業。
