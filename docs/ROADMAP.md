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

- [ ] Settings Schema
  - 担当: ChatGPT
  - Foundation共通SettingとGame拡張Settingを分離する
- [ ] Audio Settings
  - 担当: ChatGPT
  - Master / BGM / SFXの基本Volumeを扱えるようにする
- [ ] Display Settings
  - 担当: ChatGPT
  - Window Mode / Resolution / VSyncの基本設定を扱えるようにする
- [ ] Gameplay Settings Extension
  - 担当: ChatGPT
  - Mouse SensitivityなどGame固有Settingを追加できる拡張点を作る
- [ ] Settings Persistence
  - 担当: ChatGPT
  - Save Dataとは分離したSettings Fileへ保存する
- [ ] Settings Smoke Test
  - 担当: ChatGPT
  - Default / Save / Load / Invalid Valueを検証する

完了条件:
共通Settingを保存・復元でき、Game固有SettingをFoundation改造なしで追加できる。

## Phase 3 — Input System

- [ ] Input Action Contract
  - 担当: ChatGPT
  - Game固有Action名をFoundationへ固定しない
- [ ] Key Rebind
  - 担当: ChatGPT
  - InputMapのBindingを変更・保存・復元できるようにする
- [ ] Reset to Default
  - 担当: ChatGPT
  - Gameが定義したDefault Bindingへ戻せるようにする
- [ ] Keyboard / Mouse
  - 担当: ChatGPT
  - Prototypeで主要Keyboard / Mouse Bindingを扱う
- [ ] Gamepad拡張点
  - 担当: ChatGPT
  - 将来Gamepadへ拡張できるData Modelにする
- [ ] Input Smoke Test
  - 担当: ChatGPT
  - Rebind / Save / Restoreを検証する

完了条件:
Game側が定義したInput Actionを、Foundationの共通UI/APIから安全にRebind・保存できる。

## Phase 4 — Game Flow

- [ ] Pause Service
- [ ] Scene Transition
- [ ] Main Menu Contract
- [ ] Safe Quit Hook
- [ ] Flow Smoke Test

完了条件:
Game固有Scene名を固定せず、Pause・Scene切替・終了前処理を共通化できる。

## Phase 5 — Diagnostics

- [ ] Runtime Version Info
- [ ] Log Service
- [ ] Debug Overlay
- [ ] Save / Settings Path表示
- [ ] Error Summary
- [ ] Diagnostics Smoke Test

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
