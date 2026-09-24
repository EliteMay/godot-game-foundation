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

目的: Game固有Stateを知らずに利用できる、安全なSave / Load基盤を作る。

- [ ] Save Payload Contract
  - 担当: ChatGPT
  - Foundationが受け取るPayloadをJSON互換Dictionaryに限定する
  - Game固有FieldをFoundationへ定義しない
  - MetadataとGame Payloadを分離する
- [ ] Save Version
  - 担当: ChatGPT
  - Foundation Schema Versionを持たせる
  - Game側Schema Versionを別Fieldとして保持できるようにする
  - 古いVersion / 未知の新Versionを区別する
- [ ] Atomic Save
  - 担当: ChatGPT
  - 一時Fileへ書いてから本番Saveへ置換する
  - 書込み失敗で既存Saveを壊さない
- [ ] Backup
  - 担当: ChatGPT
  - 最後に読み込めた正常SaveをBackupとして維持する
- [ ] Load Validation
  - 担当: ChatGPT
  - JSON Parse失敗、必須Metadata欠落、非対応Versionを安全に返す
  - Load失敗でGameをCrashさせない
- [ ] Migration Hook
  - 担当: ChatGPT
  - Game側が古いPayloadをMigrationできる入口を用意する
- [ ] Auto Save API
  - 担当: ChatGPT
  - Foundationは保存要求APIを提供し、どのGameplay Eventで呼ぶかはGame側へ残す
- [ ] Save System Smoke Test
  - 担当: ChatGPT
  - Save → Load、破損JSON、Backup、Version mismatchをHeadlessで検証する

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
