# Public Godot Template Research

調査日: 2026-09-28

## 目的

Godot Game Foundationを独自発明だけで拡張せず、公開されているGodot 4向けGame Template / Project Skeletonを実装・構成まで確認し、再利用価値の高い共通機能と、Foundationへ入れるべきでないGame固有機能を分ける。

この文書は「どれか1つを丸ごとコピーする」ためのものではない。各Repositoryの責務分割・Lifecycle・UX Shell・Save / Settings / Input等の実装パターンを比較し、FoundationのCurrent Roadmapへ反映するための設計Reference。

## 調査対象

| Repository | Snapshot | License | 主な特徴 |
| --- | --- | --- | --- |
| [Maaack/Godot-Game-Template](https://github.com/Maaack/Godot-Game-Template) | 2026-09-10 push | MIT | Main / Pause / Options / Credits / Loading / Input Remap / Input Icon / UI Sound / Music / Plugin分割 |
| [ChristianWSmith/godot4-template](https://github.com/ChristianWSmith/godot4-template) | 2025-11-19 push | MIT | InitManager、Manager Lifecycle、Async Scene Loading、Save Slots、Settings Migration、Audio、Crash Screen、Steam |
| [LucasMcClean/godot-game-template](https://github.com/LucasMcClean/godot-game-template) | 2025-01-23 push | MIT | Modular Autoload、Save / User Preferences / Scene Manager / Audio / Event、簡素なMenus |
| [bitbrain/godot-gamejam](https://github.com/bitbrain/godot-gamejam) | 2026-08-19 push | MIT | Main / Settings / Pause、Persist Group Save、Localization、Bootsplash、itch.io CI |

PopularityやStar数は採用条件にしない。Current Godot version compatibility、責務分離、Testability、安全なData handling、FoundationのNon-goalと一致するかを優先する。

## 比較結果

| 領域 | Current Foundation | Public Templateで確認したPattern | 判断 |
| --- | --- | --- | --- |
| Lifecycle / Bootstrap | FoundationRuntimeでSettings → Input → Flow → Save → Diagnostics → Test Bridgeを統合 | ChristianのInitManagerがManagerを順序初期化 | **維持・強化**。Current方向は妥当 |
| Save Core Safety | Atomic write、Backup、Version、Migration、Autosave、Load failure write block | ChristianはSlot / Cloud、MaaackはResource Save、Lucasは手動Serialize順、bitbrainはPersist group | **CoreはCurrent Foundationを維持**。外部実装へ置換しない |
| Settings Backend | Audio / Display / Gameplay extension、Backup、Normalize | MaaackはPlayerConfig、ChristianはVersion / checkpoint / event、bitbrainはConfigFile | **Transaction / Apply-Cancelを追加候補** |
| Input Backend | Keyboard / Mouse / Gamepad Rebind、Persistence | MaaackはRemap UI + Icon mapping、ChristianはSettings連携Input Manager | **Backend維持、UX部品を追加** |
| Main / Pause / Options Shell | なし | Maaack / Lucas / bitbrainに共通 | **追加する**。ただしTheme固定しない |
| Scene Loading UX | Scene Contract + change_scene | Maaack Scene Loader、Christian threaded load + progress + fade、Lucas loading screen | **追加する**。Async loading / progress / transitionを共通化 |
| Audio Playback | SettingsからBus volume適用のみ | Maaack Music/UI Sound、Christian global/2D/3D Audio、Lucas Audio Manager | **追加する**。BGM / SFX / UI / Voice helperを共通化 |
| Save Slot / New / Continue | Generic path 1本をGame側から指定 | Christian named slots、Maaack / bitbrain Continue flow | **Optional層として追加**。Core Saveの上に構築 |
| Localization | なし | bitbrain locale setting + TranslationServer、Maaack menu translations | **最小Bootstrapを追加** |
| Input Prompt / Glyph | なし | Maaack InputIconMapper、device別Prompt | **追加候補**。Icon Asset自体はBundled必須にしない |
| UI Focus / Controller Navigation | Game側任せ | MaaackはFocus capture / restore、Menu全体でGamepad support | **共通UI Shellへ追加** |
| Boot / Opening | Starter mainのみ | Maaack opening、bitbrain bootsplash | **Optional Shell**。Game固有演出は持たない |
| Crash / Recovery UI | Diagnostics log/overlayのみ | Christian CrashReport + crash screen | **Controlled fatal/recovery screenを追加候補**。OS hard crash捕捉とは区別 |
| Event Bus | Signal中心 | Christian / LucasはGlobal Event Bus | **今は追加しない**。必要Evidenceが出た時だけ検討 |
| Generic State Machine / Player | なし | LucasはPlayer State Machine | **Foundationへ入れない**。Game固有 |
| Steam / Cloud | なし | ChristianはSteam Cloud save/settings | **Later / Extension**。Coreへ直結しない |
| Code Obfuscation | なし | ChristianはGDMaim | **Non-goal**。必要Gameだけ |
| itch.io Auto Publish | Windows Build artifactまで | bitbrain / MaaackにPublish workflow | **Later**。Primary Windows配布要件確定後 |
| Credits Parser | なし | Maaack Markdown Credits | **Optional UI Utility**。Core必須ではない |

## 参考にする設計

### Maaack — UI Shellを機能単位へ分離する

MaaackはGame Templateを1つの巨大Sceneにせず、Menus Template、Options Menus、Input Remapping、Scene Loader、Credits、UI Sound、Music Controllerへ分けている。

Foundationでも同じ考え方を採用し、Main Menu / Pause / Options等を「FoundationRuntime必須機能」にしない。個別Moduleとして利用可能にする。

特に参考にするもの:

- Main Menu / Pause / Optionsの再利用可能Scene
- UI focus restore
- Keyboard / Gamepad navigation
- Input Remap UI
- Input Prompt / Icon resolver
- UI Sound / Music Controllerの分離
- Scene Loaderの独立Module

### ChristianWSmith — LifecycleとAsync Scene Loading

`InitManager` がSubsystemの初期化順を管理する設計はFoundationRuntimeと同じ方向。

追加で参考にするもの:

- Managerの初期化Failureを止めるLifecycle
- `ResourceLoader.load_threaded_request` を使うAsync Scene loading
- Loading progress
- Fade transition
- Settings checkpoint / reinstate
- Named Save Slots
- Controlled fatal error screen

Steam、Traits、Obfuscation等はFoundation Coreへ持ち込まない。

### LucasMcClean — 取り外し可能なModule境界

LucasMcClean templateはAutoload単位でAudio / Save / User Preferences / Scene Manager等を分離し、不要なら削除できる思想を持つ。

Foundationも既存Systemを単独利用可能なまま維持し、FoundationRuntimeを「全部必須のFramework」にしない。

Global Event BusとPlayer State Machineは今回採用しない。

### bitbrain — 小さいStarterでもGameとして成立する外枠

bitbrain templateはMain Menu、Settings、Pause、Save、Localization、Bootsplashを少ない構成で提供している。

Foundation Starterも「Runtime readyと表示するだけ」から、必要に応じてGame Shellを選択導入できる方向へ進める。ただしGame Jam向けのPersist Group Save方式をFoundation Save Coreへ取り込まない。

## 採用する次の共通機能

### 1. Application Shell / Scene UX

- Optional Boot / Opening entry
- Reusable Main Menu
- Reusable Pause Menu
- Options Menu container
- Async Scene Loader
- Loading progress
- Fade transition
- Focus restore / controller navigation
- Theme差し替え前提

### 2. Settings / Input UX

- Settings edit session
- Apply / Cancel / Reset
- Temporary checkpoint / rollback
- Generic option controls
- Input Remap UI
- Binding conflict detection policy
- Current binding text
- Input prompt resolver / device detection extension

### 3. Audio Service

- Global BGM
- Crossfade / fade
- Global SFX / UI / Voice
- 2D / 3D one-shot helper
- Existing Settings bus mappingとの連携
- Audio content自体はGame側

### 4. Save Profiles / Slots

- Slot metadata
- list / create / load / delete
- Continue latest
- New Game helper
- Existing Generic Save System上へ構築
- Cloud syncは別Extension

### 5. Localization / Accessibility Shell

- Locale persistence
- TranslationServer apply
- Menu translation contract
- Keyboard / Gamepad focus baseline
- Reduced motion等はGame要件に応じるExtension Point

### 6. Controlled Failure / Recovery UX

- Foundation initialization failureをUserへ表示できるScene
- Diagnostics summary
- Log location / recovery guidance
- Safe return to menu / quit
- OS-level hard crash recoveryと誤認しない

## 今回採用しないもの

- Game固有Player Controller / State Machine
- Global Event Busの強制
- Trait framework
- Steam dependency
- Cloud SaveをCoreへ直結
- Code obfuscation
- Game固有UI Theme / Visual Style
- Resource script serialization型のSave
- Persist groupをFoundation SaveのSource of Truthにする方式

これらは特定Gameで必要になった時にExtensionとして検討する。

## 実装原則

Public TemplateのCodeをまとめてCopyするのではなく、MIT Licenseを確認した上でArchitecture / UX PatternをReferenceにする。

Foundationでは既存の安全Contractを優先する。

- SaveはCurrent Atomic / Backup / Migration / write-block Contractを維持
- Game固有DataをFoundationへ固定しない
- Module単位で無効化・単独利用可能にする
- User-facing ShellもTheme / Game ruleを固定しない
- Headless Behavior TestとWindows Runtime確認を分ける
- 追加機能はStarterへ全部強制せず、Minimal / Standard等のProfile化を検討する
