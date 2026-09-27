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
