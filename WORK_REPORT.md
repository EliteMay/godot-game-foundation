# Work Report

## v0.10.0-dev — Integrated Foundation Runtime

### 目的

Deep Factory固有開発をいったん保留し、新しいGodot Gameで使い回す共通Foundation自体を先に強化する。

### 実装

- `addons/game_foundation/runtime/foundation_runtime.gd`
  - Diagnostics初期化
  - Settings load / runtime apply
  - Gameplay settings adapter
  - Input binding restore / save
  - Scene flow setup
  - Save load / autosave / explicit save
  - Safe Quit save
  - Runtime Test Bridge接続
- Save Adapter
  - `capture_save_state`
  - `restore_save_state`
  - optional `migrate_save_state`
- Runtime Test中は通常Save writeを停止
- Load / Restore失敗後はSave writeをblock
- 明示Saveは最新PayloadでPending Autosaveを置換してflush
- Starter mainからFoundationRuntimeを初期化
- Foundation Versionを0.10.0-devへ更新
- Deep Factory PilotをRoadmap上で保留

### Automated Validation

- PR #4 Godot CI: PASS
- Direct cold start: PASS
- Godot import: PASS
- Existing Foundation smoke tests: PASS
- Integrated Foundation Runtime smoke: PASS
- Corrupt Save preservation regression: PASS
- Generated Starter materialize / import / main / integration smoke: PASS
- PR #4 Windows Build: PASS
- main Godot CI: PASS
- main Windows Build: PASS
- main merge commit: `a804b0cbb9f2331211e0f9fe51f34d8b9a16a299`

### 未確認

- Windows実機Starterで `Foundation v0.10.0-dev / Runtime ready` 表示
- 実GameでのGame-specific Save Adapter導入
- Deep Factory PilotはFoundation優先方針により保留


---

## 2026-09-28 Public Godot Template Research

### 調査対象

- Maaack/Godot-Game-Template
- ChristianWSmith/godot4-template
- LucasMcClean/godot-game-template
- bitbrain/godot-gamejam

4 RepositoryともMIT License。READMEだけでなく、Lifecycle / Save / Settings / Input / Scene Manager / Menu / Audio等の主要CodeとDocsを確認した。

### 結論

Current Foundationの強い部分:

- Atomic / Backup / Migrationを持つGeneric Save
- Settings / Input Backend
- FoundationRuntime Lifecycle
- Diagnostics
- Runtime Test Bridge
- Windows Build / Starter Distribution

不足している共通領域:

- Main / Pause / Options Shell
- Async Scene Loading / Loading progress / Transition
- Settings Apply / CancelとInput Remap UI
- BGM / SFX / UI Audio Service
- Save Slot / Continue / New Game
- Localization / Focus baseline
- Controlled Failure / Recovery UI

### Roadmap反映

- 重複していたPhase 9番号を整理
- Runtime Test Bridge → Phase 9
- Integrated Foundation Runtime → Phase 10
- Phase 11〜16をResearch結果から追加
- Deep Factory PilotはPhase 8のまま保留
- Event Bus / Player State Machine / Steam / Obfuscation等はCoreへ採用しない

### Source

Current decision summary: `docs/REFERENCE_TEMPLATES.md`


### Validation

- PR #5 Godot CI: PASS
- PR #5 Windows Build: PASS
- main merge commit: `71bbdc43cdb7e2a8029530302ae04e6cc522ca51`
- main Godot CI: PASS
- main Windows Build: PASS
- Deep Factory Repositoryは変更していない


---

## 2026-09-28 Phase 8 Windows Evidence / Phase 10確認手順修正

### Phase 8 — Deep Factory Pilot

Game Dev Hub v0.1.24のUser実機確認共有パックで、Windows実機回帰6項目がすべてPassした。

確認された内容:

- Foundation v0.8.0-dev導入状態
- 進行済み状態で終了
- 再起動後のPlayer位置と主要進行復元
- Small Minerの設置位置と内部Storage復元
- 復元後の採掘 / 回収 / 売却 / Upgrade / 自動生成継続
- Hubへの結果記録

既存の自動RegressionとUser実機Evidenceを合わせ、Phase 8を完了とした。今回のEvidenceから新しいFoundation共通不具合は見つからず、追加Runtime修正は不要。

### Phase 10 — Windows Starter確認の修正

UserがFoundation Repository本体を開いた状態で「v0.10 Starterを作成または基盤更新する」と表示され、操作対象が不明瞭だった。

調査結果:

- Current Templateは `starter/scripts/main.gd.template` で `FoundationRuntime` を初期化する
- Managed Pathは `addons/game_foundation` のみ
- したがって旧Starterを「基盤を更新」してもStarter側の `scripts/main.gd` は自動更新されない

Roadmapを修正し、Windows実機確認は **Current v0.10 Templateから新規Starterを生成して行う** と明記した。Foundation Repository本体の「Game Foundation 未導入」はこの確認では異常扱いしない。


---

## v0.11.0-dev — Phase 10完了 / Transition Layer

### Phase 10 Windows Evidence

Game Dev Hub v0.1.25で新規 `foundation-runtime-test` StarterをCurrent v0.10 Templateから生成し、User実機確認2項目がPassした。

- v0.10.0-dev Starter生成: PASS
- Starter画面 `Godot Game Foundation 0.10.0-dev / Runtime ready`: PASS

これによりPhase 10 — Integrated Foundation RuntimeのHeadless CI / Windows Build / Windows Starter実機確認がすべて揃った。

### Phase 11 Transition Layer

`addons/game_foundation/shell/transition_layer.gd` をOptional Moduleとして追加した。

- Fade out: Configured colorでSceneを覆う
- Fade in: Overlayを透明に戻してSceneを見せる
- duration / color / CanvasLayerをGame側で設定
- `motion_scale` 0.0〜1.0でAnimation時間を短縮
- `set_reduced_motion(true)` で即時Transition
- Mouse入力を奪わない
- Transition中の重複Requestを `transition_in_progress` で拒否
- FoundationRuntimeへ必須統合せず、必要Gameだけ利用する
- v0.11.0-devへFoundation Versionを更新

### Validation

- Transition Layer Headless Smoke TestをCIへ追加
- PR #7 Godot CI: PASS（Transition Layer Smokeを含む）
- PR #7 Windows Build: PASS
- Windows上のVisual Fade確認: 未確認（BehaviorはHeadless Test対象）


---

## v0.11.0-dev — Async Scene Loader

### 目的

Phase 11のLoading / Scene UXで、Scene切替前のResource loadがMain ThreadをBlockingしない共通経路を追加する。

### 実装

- `addons/game_foundation/shell/async_scene_loader.gd`
  - `ResourceLoader.load_threaded_request()` でBackground Loadを開始
  - `load_threaded_get_status()` でProgress / Failureを監視
  - `load_threaded_get()` はLoaded確認後だけ呼ぶ
  - `GameFlowService.resolve_scene_path()` をResolverとして利用
  - `load_started / load_progress / load_completed / load_failed` Signal
  - 同一Scene二重Requestと別Scene同時Requestを区別して拒否
  - `status_snapshot()` / `take_loaded_scene()`
  - Pause中も進行する `PROCESS_MODE_ALWAYS`
- Foundation capabilityへ `async_scene_loader` を追加
- Application Shell Docs / Roadmap / READMEを更新

### 設計境界

- Game固有Scene Path mappingをAsync Loaderへ複製しない
- FoundationRuntime必須機能にしない
- Cancellationを実装したように見せるFake APIは追加せず、1 request at a timeを明示
- Loading ScreenのVisualは次Taskへ分離

### Validation

- Async Scene Loader Headless Smoke Testを追加
- PR #8 Godot CI: PASS（Async Scene Loader Smokeを含む）
- PR #8 Windows Build: PASS
- Loading Screen / 実Windows Visual Flow: 未実装のため未確認


---

## v0.11.0-dev — Pause Menu Shell

### 目的

Phase 11のPause UIで、各GameがResume / Options / Main Menu / Quitの配線とFocus復元を毎回作り直さなくてよい共通Shellを追加する。

### 実装

- `addons/game_foundation/shell/pause_menu_shell.gd`
- `addons/game_foundation/shell/pause_menu_shell.tscn`
  - Resume → Game Flow `set_paused(false)`
  - Options → Game側Callable
  - Main Menu → Game Flow `go_to_main_menu()`
  - Quit → Game Flow `request_quit()`
  - Open時に現在Focusを保存
  - Resume後に有効なPrevious Focusへ復元
  - Main Menu遷移時は旧Scene Focusを復元しない
  - Options / Main Menu / Quit availabilityをButton表示へ反映
  - Label override
  - Pause中も動作する `PROCESS_MODE_ALWAYS`
- Default SceneはPanel / Button Layoutのみ持ち、Game固有Palette / Font / Logoを固定しない
- Foundation capabilityへ `pause_menu_shell` を追加

### 設計境界

- Pause入力Action名をFoundationへ固定しない
- Options内部UIはGame側またはPhase 12 Settings UIへ委譲する
- Main Menu / Quitは既存Game Flow Contractを再利用する
- Visual ThemeはGame側で差し替える

### Validation

- Pause Menu Shell Headless Smoke Testを追加
- Pause / Resume / Options / Safe Quit block / Main Menu / Focus restore / Label overrideを検証
- PR #9 Godot CI: PASS（Pause Menu Shell Smokeを含む）
- PR #9 Windows Build: PASS
- main merge commit: `5ff2e0bce51eb0f614348256f03af6d22d546803`
- main Godot CI: PASS
- main Windows Build: PASS
- Game ThemeでのVisual / Controller実機確認: Phase 11統合時に実施

---

## v0.11.0-dev — Loading Screen Contract

### 目的

Phase 11のAsync Scene Loaderが持つProgress / FailureをGame固有Visualから分離し、任意のLoading Sceneへ接続できる共通Presentation Stateを追加する。

### 実装

- `addons/game_foundation/shell/loading_screen_contract.gd`
  - `idle / loading / loaded / failed` State
  - `state_changed` / `progress_changed` Signal
  - `status_snapshot()` / `last_result()`
  - Async Scene Loaderへの`request_scene()`委譲
  - Request開始前のFailureもPresentation Stateへ反映
  - active load中のduplicate / busy拒否で現在Stateを壊さない
  - Loader実行中の差し替えとState resetを拒否
- Foundation capabilityへ `loading_screen_contract` を追加
- Visual Sceneは一切生成せず、Game側Control / SceneをSignal Consumerとして差し替え可能にした
- Application Shell Docs / Roadmap / READMEを更新

### 設計境界

- Game Flow Scene Contract / Async Scene LoaderをLoading FactのSource of Truthとして維持
- ProgressBar / Logo / Background / Font / PaletteをFoundationへ固定しない
- PackedSceneやResourceLoader JobのOwnershipをVisual Sceneへ移さない
- FoundationRuntime必須機能にはしない

### Validation

- Loading Screen Contract Headless Smoke TestをCIへ追加
- Idle → immediate Failure → Reset → Loading → Loadedを検証
- Progress Signal / final progress 1.0を検証
- load中のbusy rejectionがactive Loading Stateを壊さないことを検証
- PR #10 Godot CI: PASS（Loading Screen Contract Smokeを含む）
- PR #10 Windows Build: PASS
- main merge commit: `1e697a8badaeb5b4e5d79767100e8d24089fb382`
- main Godot CI: PASS
- main Windows Build: PASS
- Visual Scene自体はGame側差し替え前提のため、このTaskではFoundation固有Visualの実機確認対象なし

---

## v0.11.0-dev — Main Menu Shell

### 目的

Phase 11のMain Menuで、各GameがNew / Continue / Options / Quitの基本配線、Action availability、初期Focusを毎回作り直さなくてよいOptional Shellを追加する。

### 実装

- `addons/game_foundation/shell/main_menu_shell.gd`
- `addons/game_foundation/shell/main_menu_shell.tscn`
  - New Game → Game側Callable
  - Continue → Game側Callable
  - Options → Game側Callable
  - Quit → Game Flow `request_quit()`
  - `continue_action`の設定有無と`continue_available`を分離
  - `set_continue_available()`でRuntime更新
  - 未設定Action slotは非表示
  - 設定済みContinueが利用不能な場合は表示したままdisabled
  - Returning UserはContinue、First-useはNew Gameを初期Focus候補にする
  - `activate_menu()` / `deactivate_menu()` / `focus_initial_action()`
  - Label override
- Default SceneはLayout / Minimum Size / Spacingだけを持ち、Game固有Visualを固定しない
- Foundation capabilityへ `main_menu_shell` を追加
- Application Shell Docs / Roadmap / READMEを更新

### 設計境界

- Save存在・Slot構造・New Game初期StateはGame側または後続Save Profiles層へ残す
- Main Menu ShellはGame固有Scene IDやResource Pathを所有しない
- Quitは既存Safe Quit Hookを迂回せずGame Flowへ委譲する
- Logo / Background / Palette / Font / final Button compositionはGame側へ残す
- FoundationRuntime必須機能にはしない

### Validation

- Main Menu Shell Headless Smoke TestをCIへ追加
- First-use / Returning UserのContinue availabilityと初期Focusを検証
- New / Continue / Options Action routingとLabel overrideを検証
- Safe Quit block / successを検証
- Optional slot表示とinactive action guardを検証
- PR #11 Godot CI: PASS（Main Menu Shell Smokeを含む）
- PR #11 Windows Build: PASS
- main merge commit: `91625503205c7dca5130065c24d0ed2feea32263`
- main Godot CI: PASS
- main Windows Build: PASS
- 実Game ThemeでのVisual / Controller操作はPhase 11 Focus Baseline統合時に確認する

---

## v0.11.0-dev — Controller / Keyboard Focus Baseline

### 目的

Phase 11のMain / Pause MenuをMouse前提にせず、Optional Actionの表示状態が変わってもKeyboard / ControllerのFocusが利用不能Buttonへ残らない共通Baselineを追加する。

### 実装

- `addons/game_foundation/shell/menu_focus_navigation.gd`
  - visible / enabled / focusable Controlだけを抽出
  - Visual順に`focus_neighbor_top / bottom`と`focus_previous / next`を再構築
  - disabled / hidden Actionを自動skip
  - Defaultは端でWrapせず、Game固有ControlへのFocus拡張を閉じ込めない
  - `focus_first()`で最初の利用可能ControlへFocus可能
- Main Menu Shell
  - Continue availability等の変更時にFocus graphを再構築
  - 現在Focusが無効化された場合は初期Actionへ回復
  - `focused_action_id` / `managed_focus_navigation`をSnapshotへ追加
- Pause Menu Shell
  - Open時のAction availabilityに合わせてFocus graphを再構築
  - Scene固定のFocus neighborを削除
  - `focused_action_id` / `managed_focus_navigation`をSnapshotへ追加
- 両Shellとも`manage_focus_navigation=false`でGame固有Focus設計へ委譲可能
- Foundation capabilityへ `menu_focus_navigation` を追加

### Input境界

- Foundationは物理Keyboard Key / Controller ButtonをHardcodeしない
- Godot標準UI Focus / semantic `ui_*` Actionを利用する
- Pauseを開くInput Action名は従来通りGame側Input Contractの責務
- Physical Controllerの機種差や実Windows操作感をHeadless Testだけで確認済み扱いしない

### Validation

- `menu_focus_navigation_smoke.tscn` をCIへ追加
- hidden / disabled skip、neighbor再構築、Focus端、availability更新を検証
- `ui_down` / `ui_accept`をInputEventActionとして流し、MouseなしFocus移動とButton activationを検証
- Main Menu Smokeでdisabled Continue skip / Focus snapshotを検証
- Pause Menu SmokeでRuntime-generated neighbor / Focus snapshotを検証
- PR #12 Godot CI: PASS（Menu Focus Navigation / Main Menu / Pause Menu Smokeを含む）
- PR #12 Windows Build: PASS
- main merge commit: `470051cb73146e3536b830a08b90c51317d3f568`
- main Godot CI: PASS
- main Windows Build: PASS
- 実Windows Physical Controller操作: 未確認（実Game統合時のRuntime Validation対象）

---

## v0.12.0-dev — Settings Edit Session

### 目的

Phase 12 — Settings / Input UX Componentsを開始し、Options画面で毎回実装していた一時Settings編集、Preview、Apply、Cancel、Resetを共通化する。

### 実装

- `addons/game_foundation/settings/settings_edit_session.gd`
  - Committed Baseline / Draft / Runtime Previewを分離
  - `set_draft()` でNormalize後に任意Runtime Preview
  - `apply()` はRuntime Preview成功を確認してからPersistence Callbackを実行
  - Apply成功時はその値を新Baselineへ更新
  - `cancel()` はBaselineへRuntimeを戻してSession終了
  - `reset_to_defaults()` はGameのGameplay defaults込みDefaultをDraftへ設定
  - Reset / PreviewだけではDiskを変更しない
  - Preview失敗時は直前Runtime PreviewへRollbackを試行
  - Persist失敗時はSessionを維持し、CancelでBaselineへ戻せる
- `FoundationRuntime.begin_settings_edit_session()`
  - 現在のCommitted SettingsからSessionを開始
  - 既存Settings Runtime / Gameplay AdapterをPreviewに再利用
  - Apply成功時だけSettings Fileと `current_settings()` を更新
- Foundation capabilityへ `settings_edit_session` を追加
- Foundation Versionを `0.12.0-dev` へ更新
- `docs/SETTINGS_UX.md` を追加

### Validation

- Settings Edit Session SmokeでPreview / Cancel / Reset / Apply / post-Apply Cancelを検証
- Preview failure時のRuntime rollbackを検証
- Persistence failure時にBaselineが進まずCancel可能なことを検証
- Foundation Runtime SmokeでPreview中はCommitted Settingsが変わらず、CancelでGameplay Adapterが元値へ戻ることを検証
- Foundation Runtime SmokeでApply後のCommitted Settings更新と、後続Cancelが直近Apply値へ戻ることを検証
- PR #13 Godot CI: PASS（Settings Edit Session / Foundation Runtime Smokeを含む）
- PR #13 Windows Build: PASS
- main merge commit: `131fa76dcf2990416559840288703c3bf46d22e9`
- main Godot CI: PASS
- main Windows Build: PASS

---

## v0.12.0-dev — Generic Option Controls

### 目的

Phase 12のOptions UIで、各GameがToggle / Slider / List / Resolutionの基本Bindingを毎回作り直さず、Settings Edit Sessionの安全なApply / Cancel contractをそのまま再利用できる共通Controlを追加する。

### 実装

- `addons/game_foundation/settings/settings_option_control.gd`
  - `toggle` → CheckButton
  - `slider` → HSlider + Value Label
  - `list` → OptionButton
  - `resolution` → Resolution OptionButton
  - Dotted String / String ArrayのSetting path
  - Session Draftへのnested write
  - ControlごとのRuntime Preview on/off
  - Session `draft_changed` からReset / 外部変更を自動同期
  - Cancel後は入力をdisable
  - Slider range / step / display multiplier / decimals / suffix
  - Game-defined List / Resolution labels and values
  - Path typoやrange外 / option外の値を明示Reject
- Foundation capabilityへ `generic_option_controls` を追加
- `docs/SETTINGS_UX.md` / Roadmap / README / Learningを更新

### 設計境界

- ControlはSettings Fileへ直接書かずSettings Edit Sessionへ委譲
- FoundationはGame固有Option構成・Label・Themeを持たない
- Godot標準Controlを使い、物理Keyboard / Controller ButtonをHardcodeしない
- Options画面全体のTabs / Section / Scroll構成はGame側へ残す
- 現在Resolutionが候補一覧外でも勝手に別値へ変更しない

### Validation

- Settings Option Control Headless SmokeをCIへ追加
- Toggle / Slider / List / Resolution生成を検証
- Nested path write / Runtime Previewを検証
- Slider display formattingを検証
- List option外 / Slider range外Rejectを検証
- Session ResetによるControl同期を検証
- Cancel後disableとRuntime baseline復元を検証
- PR #14 Godot CI: PASS（Settings Option Control Smokeを含む）
- PR #14 Windows Build: PASS
- main merge commit: `ca04a2ca810859bc2fca9234e9e73f5a4eedd636`
- main Godot CI: PASS
- main Windows Build: PASS
- 最終Game ThemeでのVisual quality / Focus順は実Game統合時のRuntime Validation対象

---

## v0.12.0-dev — Input Remap UI

### 目的

Phase 12で、各GameがCurrent Binding表示・入力待機・Keyboard / Mouse / GamepadのCapture / Rebindを毎回作り直さず、既存Input Systemへ安全に接続できる共通Rowを追加する。

### 実装

- `addons/game_foundation/input/input_remap_control.gd`
  - Internal Action IDとGame-facing display nameを分離
  - Current Binding表示
  - Rebind / Cancel Button
  - Listening state
  - Keyboard press / Mouse Button / Joypad Button / Joypad Motion Capture
  - Key release / echo、Button release、Axis threshold未満を無視
  - Joypad Motion方向を±1へ正規化
  - Gamepad deviceは既定-1、必要Gameだけpreserve可能
  - Optional `binding_formatter`
  - Optional Persistence Callback
  - Persistence failure時にRebind前BindingsへRuntime rollback
  - Pause中も操作できるPROCESS_MODE_ALWAYS
- Foundation capabilityへ `input_remap_ui` を追加
- Input / Settings UX Docs、Roadmap、README、Learningを更新

### 設計境界

- Capture CancelへEscape等の物理KeyをHardcodeしない
- Game Action内部名をUser-facing Labelへ流用しない
- Theme / Font / Palette / final Options compositionはGame側
- 同一Binding Conflict policyは先取りせず次Taskへ分離
- Input Prompt icon / current-device解決は後続Input Prompt Resolverへ分離

### Validation

- Input Remap Control Headless SmokeをCIへ追加
- Keyboard / Mouse / Joypad Button / Joypad Motion Captureを検証
- Current Binding表示とInternal ID / display name分離を検証
- release / axis drift無視を検証
- default gamepad device=-1とAxis方向正規化を検証
- Cancelで既存Bindingを保持することを検証
- Persistence成功とPersistence失敗時Runtime rollbackを検証
- PR #15 Godot CI: PASS（Input Remap Control Smokeを含む）
- PR #15 Windows Build: PASS
- main merge commit: `35dfa3595a73e1905ef9be29167316a4f63d57ca`
- main Godot CI: PASS
- main Windows Build: PASS
- Game ThemeでのVisual quality / Focus順 / 物理Controller操作感は実Game統合時のRuntime Validation対象

---

## v0.12.0-dev — Conflict Detection

### 目的

Phase 12のInput Remapで同一Bindingを割り当てた時、各Gameが独自比較とInputMap mutationを作り直さず、Reject / Replace / Allowを明示的に選べる共通Policy層を追加する。

### 実装

- `addons/game_foundation/input/input_conflict_resolver.gd`
  - `find_conflicts()`
  - `descriptors_conflict()`
  - `rebind_with_policy()`
  - `reject / replace / allow`
  - Keyboard / Mouse Modifier込み比較
  - Joypad device wildcard overlap
  - Joypad Axis direction-aware conflict
  - Replace時は一致Eventだけ除去し、他Bindingを保持
- `input_remap_control.gd`
  - `conflict_policy` optionを追加
  - 既定はallowで既存Behaviorを維持
  - Reject時はListeningを継続
  - `conflict_detected` Signal
  - Replaceで複数Actionが変わってもPersistence failure時はCapture前snapshotへrollback
- Foundation capabilityへ `input_conflict_detection` を追加
- Input / Settings UX Docs、Roadmap、README、Learningを更新

### 設計境界

- FoundationはGameごとの正しいPolicyを決めない
- Reserved Key listを持たない
- Same-action current bindingはConflict扱いしない
- specific gamepad deviceが異なる場合はConflict扱いしない
- Input Prompt表示は次Taskへ分離

### Validation

- Input Conflict Resolver Headless SmokeをCIへ追加
- RejectがInputMapを変更しないことを検証
- Allowが競合を残してTargetへ割り当てることを検証
- Replaceが一致Eventだけを外して他Bindingを保持することを検証
- device=-1 wildcard / specific device分離を検証
- Axis正負方向の分離を検証
- Input Remap SmokeでReject時Listening継続を検証
- Input Remap SmokeでReplace + Persistence failure時に複数Actionがrollbackされることを検証
- PR #16 Godot CI: PASS（Input Conflict Resolver / Input Remap Smokeを含む）
- PR #16 Windows Build: PASS
- main merge commit: `d155dd40ef1a1779bf9c3bb208f0b919048533cc`
- main Godot CI: PASS
- main Windows Build: PASS

---

## v0.12.0-dev — Input Prompt Resolver

### 目的

Phase 12の最後として、HUD / Tutorial / OptionsがCurrent deviceとCurrent Bindingから毎回Prompt表示ロジックを作り直さず、TextまたはIcon keyを再利用できる共通Resolverを追加する。

### 実装

- `addons/game_foundation/input/input_prompt_resolver.gd`
  - Current device family: keyboard_mouse / gamepad
  - Current gamepad device id
  - Key press / Mouse Button / meaningful Mouse Motion / Joypad Button / meaningful Axis Motionからdevice更新
  - release / echo / Stick drift / Mouse jitterを無視
  - Current device向けAction Binding選択
  - optional cross-device fallback
  - unbound / no-binding-for-deviceを非Crash Result化
  - Keyboard / Mouse / Joypad Button / Joypad AxisのText生成
  - Modifierを複数Icon keyへ分離
  - stable canonical semantic Icon key
  - Game-defined text / icon key override
  - Input Remap UIのbinding_formatterへ渡せるFormatter helper
- Foundation capabilityへ `input_prompt_resolver` を追加
- Phase 12 Roadmapを実装完了へ更新

### 設計境界

- Gamepad face buttonはXbox等へ固定せずSouth / East / West / North semantic
- Controller model名からLayoutを自動断定しない
- Third-party Icon Pack / Glyph AssetをFoundationへ同梱しない
- LocalizationとIcon key mappingはGame側override
- Prompt device stateはPresentation用で、InputMap / Saved BindingのSource of Truthではない

### Validation

- Input Prompt Resolver Headless SmokeをCIへ追加
- Keyboard prompt / stable icon keyを検証
- Gamepad inputでCurrent device / device id切替を検証
- Stick drift / Mouse jitter無視を検証
- Current device向けBinding選択とcross-device fallbackを検証
- unbound / device-specific missing Bindingを検証
- Modifier Text / multi-icon keysを検証
- Gamepad Axis direction semanticを検証
- Text / external Icon Pack key overrideを検証
- Input Remap formatter helperを検証
- PR #17 Godot CI: PASS（Input Prompt Resolver Smokeを含む）
- PR #17 Windows Build: PASS
- main merge commit: `f2c94cb184ea7497fa681a2e590c5ee6d511369b`
- main Godot CI: PASS
- main Windows Build: PASS
- Game Theme / real icon asset / physical controller glyph feelは実Game統合時のRuntime Validation対象

---

## v0.13.0-dev — Global Music Service

### 目的

Phase 13 — Audio Serviceを開始し、Scene切替ごとにBGM Player / Fade / Crossfade処理を作り直さず再利用できるOptional Global Music Serviceを追加する。

### 実装

- `addons/game_foundation/audio/global_music_service.gd`
  - SceneTree.root直下へ昇格するscene-persistent lifetime
  - `persist_across_scenes=false`でGame側Lifetimeへ委譲可能
  - Game-defined AudioStream
  - Play / Stop
  - Fade in / Fade out
  - 2 Player Crossfade
  - Transition中の重複Request guard
  - Game-defined `bus_name`
  - Track ID / Transition / Player state snapshot
  - Pause中もFadeが進むPROCESS_MODE_ALWAYS
- `docs/AUDIO_SERVICE.md`
  - Global Music API / Scene lifetime / Fade / Asset boundaryを記録
- Foundation Versionを `0.13.0-dev` へ更新
- Foundation capabilityへ `global_music_service` を追加

### 設計境界

- FoundationはBGM Assetを同梱しない
- AudioStreamのLoop / Import / Codec設定を変更しない
- BGM Busを勝手に作成しない
- Settingsのaudio_bus_mapとの正式接続は後続Bus Contract
- One-shot SFX / UI / Voice / 2D / 3Dは次Task
- 実Audio出力品質やLoop seamをHeadless成功だけで確認済み扱いしない

### Validation

- Global Music Service Headless SmokeをCIへ追加
- Scene-owned Parent解放後もRoot昇格Serviceが生存することを検証
- immediate Play / duplicate Play guardを検証
- Crossfade開始 / Transition guard / 完了後Track切替を検証
- Fade out / Fade in / immediate Stopを検証
- Invalid fade durationを検証
- persist_across_scenes=falseでParent ownershipを維持することを検証
- 初回PR CIはFoundation Version更新に対してfoundation-template.jsonが0.12.0-devのままでStarter Template Smokeが失敗したため、Manifestを0.13.0-devへ同期して修正
- PR #18 Godot CI: PASS（Global Music Service Smoke / Starter Materializationを含む）
- PR #18 Windows Build: PASS
- main merge commit: `0bf6f5ef341d22b809c220d64a56a838a36774d5`
- main Godot CI: PASS
- main Windows Build: PASS
- 実Audio device上の音質 / Loop seam / Crossfade聴感は実Game統合時のRuntime Validation対象

---

## v0.13.0-dev — One-shot Audio Service

### 目的

Phase 13の次Taskとして、Global SFX / UI / Voiceと2D / 3Dの短いAudio再生をGameごとに作り直さず、共通Lifecycle APIから利用できるようにする。

### 実装

- `addons/game_foundation/audio/one_shot_audio_service.gd`
  - Global SFX helper
  - UI one-shot helper
  - Voice one-shot helper
  - Node2D parent + global positionによる2D helper
  - Node3D parent + global positionによる3D helper
  - `volume_db` / `pitch_scale` / `start_position` / `tag` / `bus_name`
  - finished playerの自動解放
  - Spatial Parent tree exit時のactive tracking cleanup
  - token単位stop
  - stop_all
  - max_active_players上限
  - active count / kind / busのstatus snapshot
  - Global helper用Serviceのoptional scene-persistent lifetime
- Foundation capabilityへ `one_shot_audio_service` を追加
- `docs/AUDIO_SERVICE.md` に利用Contract / Lifecycle / Boundaryを追記
- RoadmapのOne-shot Audioを完了へ更新

### 設計境界

- Audio AssetはGame側から渡す
- Global SFX / UI / VoiceはService-owned
- 2D / 3DはScene-owned Parentを必須にしてWorld lifetimeへ従う
- 特殊Attenuation / Area Mask / Emission等はGame側専用Playerへ残す
- Current bus_namesは局所設定で、Settings audio_bus_mapとの正式統合は後続Bus Contract
- FoundationはAudio Busを勝手に作成しない

### Validation

- One-shot Audio Service Headless SmokeをCIへ追加
- Global SFX / UI / Voice開始を検証
- 短いAudioStreamWAV終了後の自動cleanupを検証
- 2D / 3D helperとScene-owned Parent contractを検証
- Spatial Parent解放時のtracking cleanupを検証
- token stop / stop_allを検証
- max_active_players上限を検証
- invalid volume / pitch / null streamを検証
- PR #19 Godot CI: PASS（One-shot Audio Service Smokeを含む）
- PR #19 Windows Build: PASS
- main merge commit: `2337885c30ee6c3a75224567c2aa51d1189d4bff`
- main Godot CI: PASS
- main Windows Build: PASS
- 実Audio deviceでの定位 / 距離減衰 / Voice / Mix聴感は実Game統合時のRuntime Validation対象

---

## v0.13.0-dev — Audio Bus Contract

### 目的

Phase 13のBus Contractとして、Settings・Global Music・One-shot Audioが別々のBus名設定を持たず、同じGame-defined Logical Bus Mappingを共有できるようにする。

### 実装

- `addons/game_foundation/audio/audio_bus_contract.gd`
  - `master / bgm / sfx / ui / voice` のLogical Bus Contract
  - 旧3-key Mappingの `ui / voice -> sfx` Fallback
  - Game固有追加Logical keyの保持
  - Settings向け `master / bgm / sfx` view
  - One-shot向け `sfx / ui / voice` view
  - Logical key → Bus名 resolve
  - Current AudioServerのexisting / missing Bus inspection
- `FoundationRuntime.settings.audio_bus_map`
  - configure時にAudioBusContractでNormalize
  - public_configにもNormalized Mappingを公開
- `SettingsRuntime`
  - Shared Contractを通してMaster / BGM / SFX適用先を解決
  - HeadlessでもBus Contract自体はValidationする
- `GlobalMusicService`
  - `audio_bus_map`から `bgm` を解決
  - 旧 `bus_name` は互換用に維持
  - Shared Contractと旧bus_name同時指定は拒否
- `OneShotAudioService`
  - `audio_bus_map`から `sfx / ui / voice` を解決
  - 旧 `bus_names` は互換用に維持
  - Shared Contractと旧bus_names同時指定は拒否
- Foundation capabilityへ `audio_bus_contract` を追加
- Roadmap / README / Audio Service Docs / Learningを更新

### 設計境界

- FoundationはAudioServer Busを作成・Renameしない
- Bus LayoutそのものはGame側が所有する
- Audio AssetやMix設計をFoundationへ固定しない
- Game固有Logical keyは削除せず保持する
- Legacy APIは壊さないが、新規統合ではShared Contractを推奨する

### Validation

- Audio Bus Contract Headless SmokeをCIへ追加
- 旧 master / bgm / sfx Mappingの互換性を検証
- ui / voice -> sfx Fallbackを検証
- Game固有追加Logical key保持を検証
- Empty / invalid key / unknown logical keyを検証
- FoundationRuntime public_configのNormalized Mappingを検証
- Global Musicがshared `bgm` Busを使うことを検証
- One-shotがshared `sfx / ui / voice` Busを使うことを検証
- Shared Contract + Legacy Bus設定の二重指定拒否を検証
- AudioServer inspectionがexisting / missingを安全に分類することを検証
- PR #20 Godot CI: PASS（Audio Bus Contract Smokeを含む）
- PR #20 Windows Build: PASS
- main merge commit: `059eeb3d25edfaca192d0c94f5fc9eb713571f22`
- main Godot CI: PASS
- main Windows Build: PASS

---

## v0.13.0-dev — Audio Resource Lifecycle

### 目的

Phase 13のLifetime / Cleanupを最終化し、Scene-persistent Audio Serviceが再生途中・Transition途中・Service破棄時にもPlayer / Tween / AudioStream参照を残さないContractにする。

### 実装

- `GlobalMusicService.dispose_audio()`
  - Active Fade / Crossfade Tween停止
  - 2 reusable AudioStreamPlayer停止
  - AudioStream参照解放
  - Current / Pending Track / Transition State reset
  - Dispose後は未configured状態
  - 再configure後のService reuse
  - Lifecycle Generationによるstale Transition callback無効化
  - Service Node predelete時も同じResource cleanup（Reparentは除外）
- `OneShotAudioService.dispose_audio()`
  - Global SFX / UI / Voiceをまとめて停止・解放
  - 外部Node2D / Node3D配下のSpatial Playerもまとめて停止・解放
  - active tracking即時clear
  - Dispose後の再configure / reuse
  - Service Node predelete時にexternal Spatial Playerをcleanup（Reparentは除外）
- Existing Cleanup
  - finished callback
  - token stop
  - stop_all
  - Spatial Parent tree exit
- Dedicated `audio_lifetime_cleanup_smoke` を追加

### 設計境界

- dispose_audioはService Node自体をqueue_freeしない
- Spatial Player ownershipはGame側World Parentのまま
- FoundationはGame Scene Tree ownershipを変更しない
- 実Audio device上の停止感や残響・MixはHeadless Contract Testでは保証しない

### Validation

- Global Music dispose中のactive fade cancellationを検証
- Dispose時にMusic Player停止・stream=nullを検証
- Dispose後reconfigure / reuseを検証
- stale transition callbackがreused stateを上書きしないことを検証
- One-shot disposeでGlobal + Spatial active trackingを0へ戻すことを検証
- One-shot disposeでexternal Spatial PlayerがWorld Parentから消えることを検証
- One-shot Service queue_free / predelete時にもexternal Spatial Playerを残さないことを検証
- Existing Global Music / One-shot Smoke regressionを継続
- 初回追加CIでは `_exit_tree()` CleanupがScene-persistent化のReparentでも発火し、既存One-shot Smokeを壊すRegressionを検出
- Cleanup triggerを `NOTIFICATION_PREDELETE` へ変更し、ReparentはLifecycle終了として扱わないよう修正
- PR #21 Godot CI: PASS（Audio Lifetime Cleanup / Global Music / One-shot regressionを含む）
- PR #21 Windows Build: PASS
- main merge commit: `56e2f99a01035677143640e442b15a45beaf5611`
- main Godot CI: PASS
- main Windows Build: PASS
- 実Audio device上の停止感 / 残響 / Mixは次のAudio Smoke / Runtime Validation対象



---

## v0.13.0-dev — Audio Service Integration Smoke

### 目的

Phase 13最後のAudio Smokeとして、個別Service Testだけでなく、SettingsのAudio Bus ContractからGlobal Music / One-shot / Spatial Audioまでを1つの構成で通すHeadless Integration Testを追加する。

### 実装

- `tests/audio_service_integration_smoke.gd/.tscn`
  - Test専用Temporary AudioServer Busを作成
  - Shared `audio_bus_map` をSettings / Global Music / One-shotへ共通適用
  - Master / BGM / SFX volume applyを確認
  - BGM / SFX / UI / Voice / 2D / 3D routingを確認
  - Music playbackとOne-shot active trackingを確認
  - `dispose_audio()` 後のPlayback / Tracking / external Spatial Player cleanupを確認
  - 終了時にTemporary Busを削除
- Godot CIへIntegrated Audio Service Smokeを追加
- Roadmap / README / Audio Service DocsをPhase 13完了状態へ更新

### Validation Boundary

Headless Integration SmokeはLifecycle / State / Bus Routing / Cleanupを検証する。

次はHeadless成功だけでは確認済み扱いにしない。

- 実Audio出力
- Codec / Import設定
- Loop seam
- 2D / 3D定位・距離減衰
- 残響
- 実際の音量感・Mix

これらはGame固有Audio Assetと実Audio deviceを使うRuntime Validationへ残す。

### Validation

- PR #22 Godot CI: PASS（Audio Service Integration Smokeを含む）
- PR #22 Windows Build: PASS
- 実Audio device聴感: Game統合時のRuntime Validation対象


---

## v0.14.0-dev — Save Profiles / Slots

### 目的

既存Generic Save SystemのAtomic Save / Backup / Migration安全性を維持したまま、必要なGameだけ複数Slot / Continue / New Gameを利用できるOptional管理層を追加する。

### 実装

- `SaveSystem.save_game(..., extra_metadata)`
  - 既存3引数API互換を維持
  - Foundation reserved metadata keyの上書きを拒否
  - Slot等のJSON互換追加MetadataをGame Payload外へ保存
- `SaveSystem.inspect_game()`
  - Runtime Load / MigrationなしでEnvelope / Payload / Metadataを検証
  - Primary破損時のBackup inspectionを任意で利用可能
- `SaveSlotManager`
  - safe lowercase Slot ID
  - Slot Metadata
  - list / create / load / save / delete
  - Continue Latest
  - New Game Helper
  - Generic Save Migration再利用
  - Cloud Provider非依存descriptor
- Delete safety
  - PrimaryをActive namespace外へrename
  - Backup / Temp cleanup
  - delete後のstale save_slot()はPrimary不在として拒否
- Corrupt Primary safety
  - BackupからLoad可能でもsave_slot()はPrimary上書きを拒否
- Foundation Version
  - `0.14.0-dev`
  - Starter manifestと同期

### Compatibility

- `SaveSystem.DEFAULT_SAVE_PATH = user://save.json` を維持
- FoundationRuntimeの既存Single Save lifecycleは変更しない
- Save Slotsは `user://save_slots` を既定とするOptional layer
- Game Payload schemaへSlot Metadataを混在させない
- Cloud SDK / Steam APIはFoundation Coreへ追加しない

### Validation

- Save Slot Manager Headless SmokeをCIへ追加
- Existing Single Save API互換を検証
- Slot ID path traversal拒否を検証
- Slot Metadata / Game Payload分離を検証
- Duplicate create拒否を検証
- list / save / Continue Latestを検証
- Corrupt Primary + Backup Recoveryを検証
- Corrupt Primaryへのsave_slot上書き拒否を検証
- Delete後のstale save_slot復活防止を検証
- New Gameが既存Slotを破壊しないことを検証
- Game Schema Migration再利用を検証
- Cloud Extensionがexternal adapter境界のままであることを検証
- PR #23 Godot CI: PASS（Save Slot Manager Smoke / 全Regression / Starter生成を含む）
- PR #23 Windows Build: PASS


---

## v0.15.0-dev — Locale Setting Adapter

### 目的

Phase 15の最初のTaskとして、Gameごとに重複していた「保存済み言語設定をGodotのTranslationServerへ適用する処理」をFoundationのSettings Runtimeへ接続する。

### 実装

- `SettingsSystem`
  - 共通Settingへ `locale` を追加
  - 既定値は `automatic`
  - 既存Settings FileにLocaleが無い場合もautomaticへ安全にFallback
  - Invalid type / empty /過長値はwarning付きでautomaticへFallback
- `LocaleSettingAdapter`
  - explicit Localeの標準化
  - `automatic` のOS言語解決
  - `TranslationServer.set_locale()` 適用
  - loaded locale / translation availability snapshot
- `SettingsRuntime`
  - LocaleをDisplayServer headless skipより前に適用
  - HeadlessでもLocale Contractを検証可能
- Foundation capabilityへ `locale_setting_adapter` を追加
- Foundation Versionを `0.15.0-dev` へ更新
- Dedicated Locale Setting Adapter SmokeをCIへ追加

### Compatibility

- Settings schema versionは1のまま維持する
- 旧Settingsには `locale` が無くてもautomaticが補われるためMigration不要
- Translation Resource / Font / supported language listはGame側が所有する
- loaded translationが存在しなくてもLocale preference自体は拒否しない

### Validation

- PR #24 Godot CI: PASS（Locale Setting Adapter Smoke / 既存Regressionを含む）
- PR #24 Windows Build: PASS


---

## v0.15.0-dev — Translation Contract

### 目的

Phase 15のTranslation Contractとして、Foundation Shellの表示文字列を英語固定やGameごとの生文字列配線へ依存させず、Game側Translation Resourceへ接続できる共通Text Contractを追加する。

### 実装

- `localization/translation_contract.gd`
  - Main Menu / Pause Menuのsemantic action → default translation key / fallback / context
  - Game側 `translation_entries` override
  - String key shorthandとDictionary entryを両対応
  - `TranslationServer.translate()` でCurrent Localeを解決
  - Translation未登録時はfallback textへ安全に戻す
  - unknown action / empty key / invalid fieldを構造化Errorで拒否
- `MainMenuShell` / `PauseMenuShell`
  - Translation Contractをconfigure時に適用
  - Locale変更時の `NOTIFICATION_TRANSLATION_CHANGED` で自動refresh
  - public `refresh_translations()` / `set_translation_entries()`
  - 既存 `labels` は最終明示overrideとして維持
- Dedicated Translation Contract Smoke
  - Test Translation ResourceをRuntime登録
  - Japanese / English locale切替
  - Translation context
  - fallback
  - legacy label precedence
  - locale change auto refresh
- Foundation capabilityへ `translation_contract` を追加

### Compatibility

- 既存Main / Pause Menuの `labels` APIを維持
- Translation Resource未導入Gameでもfallback textで従来同等の表示
- FoundationはGameのTranslation Asset / Font / Locale menuを所有しない
- Versionは同一Phaseの `0.15.0-dev` を維持

### Validation

- PR #25 Godot CI: PASS（Translation Contract Smoke / Main Menu / Pause Menu regressionを含む）
- PR #25 Windows Build: PASS


---

## v0.15.0-dev — Focus / Navigation Baseline

### 目的

Phase 15のFocus / Navigation Baselineとして、Main Menu / Pause MenuがMouseなしでも安定して操作できる最低限のNavigation Contractを共通化する。

### 実装

- `shell/focus_navigation_baseline.gd`
  - Required semantic UI action: `ui_up / ui_down / ui_accept`
  - InputMapのKeyboard / Gamepad binding coverage監査
  - 既存 `MenuFocusNavigation` を使ったvertical graph構成
  - Initial focus
  - Focus lost / disabled focus ownerのrepair
  - Valid external focusのpreserve
  - Focusable controls / current focus / input readiness snapshot
- `MainMenuShell` / `PauseMenuShell`
  - Focus graphとinitial focusをBaseline経由へ統合
  - Main Menu availability変更後のfocus repairをBaselineへ統合
  - Runtime SnapshotへNavigation readinessを追加
- Dedicated Focus Navigation Baseline Smoke
  - Keyboard / Gamepad semantic binding coverage
  - hidden / disabled skip
  - `ui_down / ui_up / ui_accept`
  - focus repair
  - external focus preserve
  - diagnostics snapshot

### Boundary

- Foundationは物理Key / Controller Buttonを固定しない
- `ui_cancel` はMenu close policyがGameごとに異なるためRequired Baselineへ含めない
- Custom layoutは既存 `manage_focus_navigation=false` でGame側へ委譲できる
- 物理Controllerでの操作感は実Game / 実機Runtime Validation対象

### Validation

- PR #26 初回Godot CI: FAIL
  - 原因: `PackedStringArray(...)` をconst expressionとして使用してGodot 4.7 parse error
  - 修正: Required UI action listをruntime生成へ変更
- PR #26 2回目Godot CI: FAIL
  - 原因: Harness built-in `ui_accept` のGamepad coverage不足をFocus graph構成自体のhard gateにしていた
  - 修正: Focus behaviorとDevice coverage auditを分離。Device不足はSnapshot / validation resultへ残し、Focus graphはsemantic action存在時に成立させる
- PR #26 最終Godot CI: PASS（Focus Navigation Baseline Smoke / Main Menu / Pause Menu regressionを含む）
- PR #26 最終Windows Build: PASS


---

## v0.15.0-dev — Motion / Feedback Hooks

### 目的

Phase 15最後のTaskとして、Reduced MotionとUI FeedbackをGame Theme / Assetへ依存せず共通Hookとして扱い、Main Menu / Pause MenuのFeedbackをGame側から安全に無効化・差し替えできるようにする。

### 実装

- `shell/ui_feedback_hooks.gd`
  - `motion_scale` / `set_reduced_motion()`
  - 複数Motion target登録 / 解除
  - Motion targetへのScale配布
  - 複数target適用中のFailure時rollback
  - `feedback_enabled`
  - Game側 `feedback_action(event_id, context)`
  - semantic event: `focus / activate / open / close`
  - handler未設定 / disabled時のnon-blocking skip
  - handler result normalization / state snapshot
- `MainMenuShell` / `PauseMenuShell`
  - optional `feedback_hooks` をconfigure可能
  - Button focus / activate、Menu open / closeをsemantic feedback eventへ変換
  - Feedback failureはPrimary Menu Actionをblockしない
  - Runtime SnapshotへFeedback wiring / state / last resultを追加
- Existing Transition Layer integration
  - 既存 `set_motion_scale()` をMotion target Contractとして再利用
  - Reduced Motion preferenceの第二実装を追加しない
- Dedicated Smoke
  - Motion scale / Reduced Motion
  - target rollback
  - Feedback enable / disable
  - actual Transition Layer integration
  - Main/Pause focus / activate / open / close integration
  - Feedback failure時もMenu action継続

### Boundary

- FoundationはAudioStream / UI sound asset / volume / haptic / Theme / visual effectを所有しない
- Game側はfeedback_action内でOneShotAudioServiceや独自Haptics等へ接続できる
- Motion preferenceの保存場所 / Settings UI名はGame側要件に残す
- Headlessではevent / state / lifecycleを検証し、実音・Focus visual・Animation感覚は実Game Runtime Validation対象

### Validation

- PR #27 Godot CI: PASS（UI Feedback Hooks Smoke / Menu Feedback Integration Smoke / 既存Regressionを含む）
- PR #27 Windows Build: PASS


---

## v0.16.0-dev — Runtime Failure State

### 目的

Phase 16 — Controlled Failure / Recovery UXの最初のTaskとして、FoundationRuntimeのFatal initialization failureを単なる戻り値で終わらせず、後続Recovery UI / Diagnostics Exportから安全に参照できる構造化Stateへする。

### 実装

- `recovery/runtime_failure_state.gd`
  - inactive state
  - initialization failure normalization
  - `kind / stage / code / message`
  - `retry_supported`
  - `save_writes_blocked`
  - `diagnostics_available`
- `FoundationRuntime`
  - `initialization_failed(result, state)` Signal
  - `runtime_failure_changed(state)` Signal
  - `has_runtime_failure()`
  - `runtime_failure_state()`
  - status snapshotへFailure Stateを公開
  - initialize failure stageを `configure / scene_tree / diagnostics / settings / input / flow / runtime_test` で記録
  - successful initialization後にFailure Stateをclear
- Retry safety
  - `configure / scene_tree` の副作用前Failureのみ `retry_supported=true`
  - subsystem初期化途中のFailureを自動Retry可能とは扱わない
- Existing Save safety
  - Save initialize/load failureは既存のsave-write blockingを維持
  - 非Fatal Save recovery failureをRuntime initialization fatalへ格上げしない
- Dedicated smoke
  - SceneTree外initialize failure
  - structured state / Signal / status snapshot
  - SceneTree追加後のsafe retry
  - successful retry後のstate clear

### Boundary

- Recovery UI自体は次TaskのRecovery Screen Contract
- Diagnostics exportは後続Task
- Crash markerは後続Task
- `retry_supported=false` は「永遠に復旧不能」ではなく、Foundation Coreがその場で安全な再初期化を保証していないという意味

### Validation

- PR #28 Godot CI: PASS（Runtime Failure State Smoke / Foundation Runtime regressionを含む）
- PR #28 Windows Build: PASS


---

## v0.16.0-dev — Recovery Screen Contract

### 目的

Phase 16のRuntime Failure Stateを、UserがReasonと安全なNext Actionを確認できるOptional Recovery Screenへ接続する。Recovery UIがData削除やRetry可否を独自推測しないよう、Action availabilityを共通Contractへ集約する。

### 実装

- `recovery/recovery_screen_contract.gd`
  - Runtime Failure Stateを観測
  - semantic action: `retry / main_menu / safe_quit`
  - Retryは `retry_supported` をAuthorityとして利用
  - Main MenuはGame Flow main menu contractまたはGame callbackへ委譲
  - Safe QuitはFoundationRuntime `request_quit(1)` またはGame callbackへ委譲
  - action in-progress guard
  - structured action result / Signals / Snapshot
  - reset / delete等の破壊的Actionは提供しない
- `recovery/recovery_screen.gd/.tscn`
  - Error summary / stage / code
  - Save write protection hint
  - Diagnostics availability hint
  - available actionだけ表示
  - semantic focus navigation
  - Translation Contract / label override
  - successful retry後に自動Close
- `TranslationContract`
  - Recovery Screen用fallback keyを追加
- Dedicated Smoke
  - unsafe retry rejection
  - main menu action
  - safe quit action
  - action setに破壊的Actionが無いこと
  - Save protection / diagnostics hint
  - translation/label override
  - Retry成功後のauto close

### Boundary

- Diagnostics Exportは次Task
- Crash Markerは後続Task
- Recovery ScreenはSave / Settings / Slotを削除・Resetしない
- Game ThemeでのVisual polish / long localized text / physical controller focus feelはHeadless CIでは未確認

### Validation

- PR #29 Godot CI: PASS（Recovery Screen Contract Smoke / existing regressionsを含む）
- PR #29 Windows Build: PASS
- Recovery Screenの実Game Theme / narrow viewport / long localized text / physical controller focus visual: NOT_RUN（Headless環境では確認不能。実Game統合時のVisual / Runtime Validationへ残す）


---

## v0.16.0-dev — Diagnostics Export Hook

### 目的

Phase 16のRecovery / Diagnostics情報をGame Dev Hub共有へ接続しやすくしつつ、内部Diagnostics SnapshotやRuntime Statusに含まれ得るGame Data・Absolute Path・Secretをそのまま外部共有しない専用境界を作る。

### 実装

- `diagnostics/diagnostics_export_hook.gd`
  - shared schemaVersion
  - App / Foundation / Godot / OS / Display情報
  - safe Runtime status whitelist
  - Runtime Failure State whitelist
  - `user://` / `res://` Virtual Pathだけ保持
  - Absolute Path redaction
  - known sensitive key redaction
  - known bearer / API key / GitHub token pattern redaction
  - Home Path redaction
  - bounded string / array / dictionary / depth
  - bounded recent entries / recent errors
  - 128 KiB total JSON limit
  - size超過時Recent detailを削減して再構築
- `FoundationRuntime.diagnostics_export(options)`
  - sanitized Dictionary
  - JSON text
  - payload byte count
  - reason metadata
- Domain-data boundary
  - `last_load`
  - Save Payload
  - Settings
  - Input Binding
  - Game固有State
  をexport whitelistへ含めない
- Dedicated Smoke
  - token / password / API key redaction
  - absolute path redaction
  - Virtual Path preservation
  - Domain Data non-leak
  - String truncation
  - byte bound
  - FoundationRuntime integration

### Boundary

- Foundationはsanitized payload生成まで
- Network送信 / Upload / Clipboard /共有パック保存はGame Dev Hub等のConsumer側
- Unknown secret patternを完全検出できる保証はないため、Game側はSecretをDiagnostics Contextへ記録しない
- Crash Markerは次Task

### Validation

- PR #30 Godot CI: PASS（Diagnostics Export Hook Smoke / existing regressionsを含む）
- PR #30 Windows Build: PASS
- Game Dev Hubへの実際の共有パック接続: NOT_RUN（Foundationはsanitized payload生成までを担当）


---

## v0.16.0-dev — Crash Marker

### 目的

Phase 16最後のTaskとして、前回Foundation Runtime Sessionが正常Cleanupされなかった可能性を次回起動時に検出できるLightweight Markerを追加する。Crash確定や完全なOS-level crash detectorとは扱わず、Recovery / Diagnosticsの追加Evidenceとして使う。

### 実装

- `recovery/crash_marker.gd`
  - `user://` path限定
  - bounded JSON marker
  - running-session marker
  - stale marker detection
  - corrupt marker detection
  - previous App / Foundation Version
  - Session ID ownership check
  - older session cleanupからnewer markerを保護
- `FoundationRuntime`
  - Optional `crash_marker` config
  - default disabled
  - Runtime initialize時にSession開始
  - `crash_marker_snapshot()`
  - `status_snapshot().crash_marker`
  - Window close request cleanup
  - `_exit_tree()` cleanup
  - Safe Quit Hook integration
- Safe Quit ordering
  - Save Hookを先に登録
  - Crash Marker cleanupを後に登録
  - Save失敗でQuitがBlockされた場合はMarkerを残す
  - Marker cleanup failureだけではQuitをBlockしない
- Diagnostics Export
  - previous-session possibility / reason / timestamp / versionsをWhitelist
  - Current Session ID / Marker Pathは共有しない
- Dedicated Smoke
  - first session
  - stale marker
  - corrupt marker
  - old/new session ownership
  - unsafe absolute path rejection
  - Runtime integration
  - safe quit cleanup
  - save-hook block時のmarker preservation
  - diagnostics handoff regression

### Boundary

- Marker残存はCrash確定ではなく `possible_unclean_exit`
- OS kill / power loss / kernel crash / mobile suspend termination等の全経路を完全に捕捉する保証はない
- Multiple process / multiple instanceはfalse positive要因になり得る
- Crash Marker自体はGame Stateを変更しない
- Actual OS hard crashをCIで強制再現したTestではなく、stale markerを使ったdeterministic simulation

### Validation

- PR #31 初回Godot CI: FAIL
  - 原因: corrupt markerを期待ケースとして読むTestでstatic `JSON.parse_string()` がengine `ERROR:` をstderrへ出し、CIのError検出に該当した
  - 修正: `JSON.new().parse()` + `get_error_message()/get_error_line()` へ変更し、破損JSONを構造化Resultとして処理
- 修正後PR #31 Godot CI: PASS（Crash Marker Smoke / Diagnostics Export regression / existing regressionsを含む）
- 修正後PR #31 Windows Build: PASS
- Actual OS hard crash / process kill / power loss: NOT_RUN（CIではstale/corrupt markerをdeterministicに再現してContractを検証）

---

## v0.17.0-dev — Starter Profile Contract

### 目的

Phase 11〜16で増えた共通Foundation機能を、新規Gameへ一律強制せず、用途別Starter Profileとして段階導入できるManifest Contractを作る。

### 実装

- Foundation Versionを `0.17.0-dev` へ更新
- `foundation-template.json`
  - `defaultProfile: "minimal"`
  - `starterProfiles`
  - `minimal`: 既存Starter互換 / selectable
  - `standard`: Game-ready Shell候補 / Hub materialization前はnon-selectable
- Foundation capabilityへ `starter_profile_contract` を追加
- Starter Template Smokeへ次を追加
  - defaultProfile存在確認
  - Profile ID lowercase / duplicate guard
  - label必須
  - capabilities non-empty
  - default Profile参照整合
  - standard Profile contract存在確認
- Starter Template / Roadmap / READMEをPhase 17開始状態へ更新

### Compatibility

- Manifest `schemaVersion` は1を維持
- Current Game Dev Hubのvalidatorは未知Fieldを拒否せず、既存 `starterFiles` / `managedPaths` Contractをそのまま利用する
- `minimal` はCurrent Starter生成と同じ意味を維持
- `standard` はHub側materialization実装前に選択可能扱いにしない
- Foundation UpdateのManaged Pathは引き続き `addons/game_foundation` のみ

### Validation

- Branch: `phase17-starter-profile-contract`
- Foundation-side Starter Template Smokeを追加
- PR #32 初回Godot CI: FAIL
  - `Run build configuration smoke test` がFoundation `0.17.0-dev` とHarness `project.godot` の `0.16.0-dev` 不一致を検出
  - Harness Versionを `0.17.0-dev` へ同期して修正
- 修正後のGodot CI / Windows Buildを再実行して最終確認する

---

## v0.17.0-dev — Standard Starter Materialization

### 目的

Phase 17の `standard` ProfileをManifest上の名前だけで終わらせず、新規Gameとして実際に生成・起動できるGame-readyな共通Shell Starterへする。

### 実装

- `starter/standard/scenes/main.tscn.template`
  - Foundation Main Menu Shell
  - Recovery Screen
  - Game固有Themeへ依存しないDark baseline
- `starter/standard/scripts/main.gd.template`
  - FoundationRuntime初期化
  - Settings / Game Flow / Diagnostics / Crash Marker
  - Main Menu Shell初期配線
  - Async Scene Loader + Loading Screen Contract初期配線
  - Runtime initialization failure時のRecovery Screen
  - Game固有Gameplay / Settings UIへ接続するHook
- `foundation-template.json`
  - `standard.selectable=true`
  - standard専用 `starterFiles` を宣言
  - `minimal` root starterFilesとの既存互換を維持
- `tools/materialize_starter_fixture.py`
  - Profile IDを受け取り、Profile固有File Setを展開
  - Installation metadataへ `starterProfile` を記録
- Foundation CI
  - `minimal` / `standard` の両方をmaterialize
  - Godot import
  - Main Scene load
  - Foundation Integration Smoke

### 境界

- SaveはGame固有Payload Adapterが必要なためStandardでも既定OFF
- Input actionはGame固有なので既定OFF
- Main MenuのNew Game / OptionsはGame固有実装へ接続するHookまで
- Theme / Gameplay / Balance / Game DataはStarter Profileへ固定しない
- Foundation更新のManaged Pathは引き続き `addons/game_foundation` のみ

### Validation

- Branch: `phase17-standard-starter-profile`
- PR #33 Godot CI: PASS
- Starter Template Smoke: PASS
- `minimal` materialize / import / Main Scene / Integration Smoke: PASS
- `standard` materialize / import / Main Scene / Integration Smoke: PASS
- PR #33 Windows Build: PASS

