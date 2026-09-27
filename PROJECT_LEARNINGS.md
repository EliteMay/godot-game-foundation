# Project Learnings

## GF-001 — 再利用Systemだけでは共通基盤になりきらない

- Date: 2026-09-27
- Type: Architecture
- Status: Adopted
- Evidence: Save / Settings / Input / Flow / Diagnosticsは個別に再利用可能だったが、実Game導入時にService生成・初期化順・Adapter接続・Safe Quit等のLifecycle配線がGame側へ重複した。
- Decision: 独立Systemは維持したまま、共通Lifecycleだけを担当する `FoundationRuntime` を追加する。
- Prevention: Game固有StateをRuntimeへ埋め込まず、Callable AdapterとContractで境界を保つ。

## GF-002 — 明示SaveはPending Autosaveより新しいStateを必ず勝たせる

- Date: 2026-09-27
- Type: Data / Reliability
- Status: Adopted
- Risk: 古いPending Autosaveが明示Saveの後に実行されると、Canonical Saveを古いStateへ巻き戻せる。
- Decision: `FoundationRuntime.save_now()` は最新PayloadでAutoSaveServiceのPending payloadを置き換えてからflushする。
- Regression Guard: Runtime Smoke Testでscore=10をpendingにした後、score=20を明示Saveし、Loadで20が復元されることを確認する。

## GF-003 — Load / Restore Failure後はSave writeを止める

- Date: 2026-09-27
- Type: Data Safety
- Status: Adopted
- Risk: 壊れたSaveや非対応Saveを読めない状態で新規Runtime Stateを保存すると、復旧可能なCanonical Dataを上書きできる。
- Decision: Load / Migration / Game Adapter Restore失敗後は `save_writes_blocked=true` とし、そのSessionでは既存Saveを上書きしない。
- Regression Guard: Corrupt primary + backupなしのRuntime Smoke Testで、`save_now()` が保存をスキップし元Fileを保持することを確認する。


## GF-004 — Backend CoreだけではGame-ready Foundationにならない

- Date: 2026-09-28
- Type: Architecture / Product
- Status: Adopted
- Evidence: Maaack / ChristianWSmith / LucasMcClean / bitbrainの公開Godot Templateを比較すると、Save・Settings・Input等のBackendだけでなくMain Menu、Pause、Options、Loading、Audio等のApplication Shellを再利用資産として持つ例が共通していた。
- Decision: Current Foundationの安全なBackend Coreは維持し、次はApplication ShellとそのUX ComponentをOptional Moduleとして追加する。
- Boundary: Game固有Visual Theme、Player Controller、State Machine、Domain LogicはFoundationへ入れない。
- Prevention: 新しい共通機能を追加する前に「複数Gameで再利用されるShell/Infrastructureか、Game固有Featureか」を分類する。

## GF-005 — Public TemplateはPatternのEvidenceとして使い、丸ごとFramework化しない

- Date: 2026-09-28
- Type: Research / Scope
- Status: Adopted
- Evidence: 比較対象にはSteam、Event Bus、Traits、Obfuscation、Game Jam向けPersist group等、特定用途では有効でもCurrent Foundationの必須Coreには不要な機能も含まれていた。
- Decision: MIT Licenseの公開TemplateはArchitecture / UX PatternのReferenceとして扱い、必要性が現在のFoundation要件で説明できる機能だけRoadmapへ採用する。
- Prevention: Popularityや「他Templateにある」という理由だけでCore DependencyやManagerを追加しない。


## GF-006 — Managed Path更新とStarter生成File更新を混同しない

- Date: 2026-09-28
- Type: Distribution / Compatibility
- Status: Adopted
- Evidence: Foundation v0.10.0-devではStarterの `scripts/main.gd` が `FoundationRuntime` を初期化するよう更新された。一方、`foundation-template.json` のManaged Pathは `addons/game_foundation` のみで、Game Dev Hubの「基盤を更新」はGame固有Fileを上書きしない。
- Risk: v0.8等で生成済みのStarterへManaged Path更新だけを行い、「v0.10 Starterと同じBootstrapになった」と誤認すると、Runtime実機確認やMigration判断を誤る。
- Decision: Starter生成FileのBehavior変更を検証する場合は、Current Templateから新規Starterを生成する。既存Gameへ同じ変更が必要な場合はManaged Path更新とは別の明示Migrationとして扱う。
- Prevention: Roadmap / Test手順では「新規Starter生成」と「Foundation Managed Path更新」を別操作として明記する。


## GF-007 — Accessibility PreferenceをVisual Componentへ固定しない

- Date: 2026-09-28
- Type: UX / Architecture
- Status: Adopted
- Context: Transition LayerはFade Animationを提供するが、Reduced motionをどの設定名・UI・Profileで有効にするかはGameごとに異なる。
- Decision: Transition LayerはPreference自体を所有せず、`motion_scale`（0.0〜1.0）と `set_reduced_motion()` をExtension Pointとして公開する。
- Prevention: Optional ShellのVisual behaviorはGame側Preferenceを受け取れるようにし、Foundation Coreが特定のAccessibility UIやGame Themeを強制しない。


## GF-008 — Async LoaderはScene Pathの第二Source of Truthを作らない

- Date: 2026-09-28
- Type: Architecture / Reliability
- Status: Adopted
- Context: Background Loading用ServiceへGame固有Path一覧をもう一度持たせると、既存GameFlow Scene Contractと二重管理になり、片方だけ更新される可能性がある。
- Decision: Async Scene LoaderはScene IDだけを受け取り、既存 `GameFlowService.resolve_scene_path()` 等のResolver CallableからPathを解決する。
- Prevention: Scene loading / transition / loading UIを追加してもGame固有Path mappingはGameFlow Scene Contractへ集約し、Shell側へ複製しない。


## GF-009 — Pause MenuはInput名ではなくFlowとFocusを共通化する

- Date: 2026-09-28
- Type: UX / Architecture
- Status: Adopted
- Evidence: 公開Godot TemplateではPause Menuを開く前のFocusを保持し、Menuを閉じた後に元Controlへ戻すPatternが確認できる。一方、Pause Key / Action名やMenu ThemeはGameごとに異なる。
- Decision: Foundation Pause Menu ShellはPause / Main Menu / Safe QuitをGame Flow Contractへ接続し、OptionsをGame Callableで差し込む。Pause入力Action名・Visual Theme・Game固有Options構成は所有しない。
- Prevention: 共通Menuへ `ui_cancel` 等のInput名をHardcodeせず、Overlayを閉じる時は可能な限り操作開始前のFocusへ戻す。

## GF-010 — Loading VisualをLoader Stateの正本にしない

- Date: 2026-09-28
- Type: UX / Architecture
- Status: Adopted
- Context: Loading ScreenへScene Path、Progress、Failure状態を直接持たせると、Async Scene LoaderとVisual Sceneが同じFactを二重管理し、Theme差し替えや別Gameへの再利用で同期ずれが起きやすい。
- Decision: Loading Screen ContractはAsync Scene Loaderを観測して `idle / loading / loaded / failed` とProgressを正規化し、Visual SceneはSignal / SnapshotのConsumerに限定する。
- Prevention: Loading UIを追加・差し替えしてもResource loading / Scene ContractのAuthorityをVisual側へ移さず、Foundation Themeや特定Control構成をCore Contractへ固定しない。

## GF-011 — Main MenuはSave判定を所有せずAction slotとAvailabilityを分離する

- Date: 2026-09-28
- Type: UX / Architecture
- Status: Adopted
- Context: Continueを共通Menuへ入れる場合、Saveの存在条件やSlot構造までMain Menuが判断すると、Game固有Save Adapterや後続Save Profiles層と責務が重複する。
- Decision: Main Menu ShellはNew / Continue / OptionsをGame Callableとして受け取り、Continueは`continue_action`の有無と`continue_available`を分離する。Quitのみ既存Game Flow Safe Quitへ接続する。
- Prevention: Menuは「押された時に何を呼ぶか」と「今押せるか」だけを扱い、Save File / Slot / New Game初期Stateの正本を持たない。

## GF-012 — Menu Focusは表示状態から再構築し、物理Input名を所有しない

- Date: 2026-09-28
- Type: UX / Accessibility / Architecture
- Status: Adopted
- Context: Optional Actionをhide / disableするMenuでScene固定のFocus neighborを持つと、利用不能ButtonへFocusが向いたり、Game固有Controller MappingとFoundation側Input処理が二重管理になりやすい。
- Decision: Focus graphは現在のvisible / enabled ControlからRuntimeで再構築し、FoundationはGodot標準UI Focusを使う。物理Key / Gamepad ButtonはHardcodeせず、Custom layoutは`manage_focus_navigation=false`でGame側へ委譲できる。
- Prevention: Menu Action availabilityを変更する時はFocus graphも同時に更新し、Focused ActionをRuntime Snapshotから観測可能にする。Headless Testではsemantic UI actionでMouseなし操作をRegression Guardする。

## GF-013 — Settings PreviewとCommitted Stateを分離する

- Date: 2026-09-28
- Type: UX / Data / Reliability
- Status: Adopted
- Context: Options画面でSlider等を即時Previewすると、Runtime値だけ先に変わる。一方でCancel / Resetが直接Settings Fileを更新すると、Userが「戻る」を選んでもSession開始時点へ復元できない。
- Decision: Settings Edit SessionはBaseline / Draft / Runtime Preview / Persisted Settingsを分離する。PreviewとResetはDiskを書き換えず、Apply成功時だけPersistする。Cancelは直近Apply時点のBaselineへRuntimeを戻す。
- Prevention: Options UI ComponentはSettings Fileへ直接書かずSession Draftを編集する。Preview失敗時は直前Runtime PreviewへRollbackを試み、復元失敗を成功扱いしない。

## GF-014 — Option ControlはDraftへBindingし、Settings Fileを所有しない

- Date: 2026-09-28
- Type: UX / Architecture / Reliability
- Status: Adopted
- Context: Toggle / Slider等が各自Settings Fileへ直接保存すると、Apply / Cancel / ResetのSession Contractを迂回し、複数Control間でCommitted StateとPreview Stateが分裂する。
- Decision: Generic Option ControlsはSettings Edit SessionのDraftだけを編集する。Pathは既存Draftに存在するものだけを受け、Theme / Label / Option listはGame側が定義する。
- Prevention: Settings UI Componentを追加する時はPersistence APIを直接呼ばずSessionへBindingする。Game固有OptionやResolution候補をFoundationへHardcodeしない。

## GF-015 — Rebind UIはCaptureを共通化してもConflict Policyを先取りしない

- Date: 2026-09-28
- Type: UX / Input / Architecture
- Status: Adopted
- Context: Input Remap UIが「同じKeyを別Actionで使えるか」まで独自判断すると、BackendとUIでConflict policyが分裂し、GameごとのReject / Replace / Allow要件を固定してしまう。
- Decision: Input Remap ControlはCurrent Binding表示、入力待機、InputEvent → Descriptor、既存Input SystemへのRebind、任意Persistenceだけを担当する。Conflict判定は後続の共通Policy層へ分離する。
- Reliability: Persistence失敗時は変更前BindingsへRuntime rollbackを試みる。Gamepadは既定でdevice=-1へ正規化し、Axis driftはthreshold未満を採用しない。
- Prevention: Capture UIへ特定物理Cancel KeyやGame固有Action名、Conflict winnerをHardcodeしない。

## GF-016 — Binding ConflictはUIの都合ではなくDescriptor overlapとして共通化する

- Date: 2026-09-28
- Type: Input / UX / Architecture
- Status: Adopted
- Context: Conflict判定を各Rebind Rowへ埋め込むと、Keyboard / Mouse / Gamepadで比較規則が分裂し、Reject / Replace / Allowの選択とInputMap mutationがUI実装へ閉じ込められる。
- Decision: Conflict ResolverをInput Remap UIから分離し、Current InputMapのDescriptor overlapを共通判定する。Game側はPolicyだけを選び、UIはResultを表示・継続する。
- Semantics: device=-1はgamepad wildcard、specific device同士は同一deviceだけ競合、Axisは方向を区別する。Replaceは一致Eventだけを外して他Bindingを保持する。
- Prevention: Foundationが特定Game向けConflict winnerやReserved KeyをHardcodeしない。Persistence失敗時は複数Actionの変更を含めて以前のBinding snapshotへ戻す。

