# Starter Template / Distribution Contract

## 目的

Game Dev Hubから新しいGodot Gameを作る時に、Foundation本体とゲーム固有領域を混ぜずに初期Projectを生成する。

## 採用方式

Phase 7では **Game Dev HubによるManaged Path Copy** を採用する。

```text
godot-game-foundation
├─ starter/*.template
├─ addons/game_foundation/
└─ foundation-template.json
        ↓ Game Dev Hub
新しいGame Repository
├─ project.godot
├─ scenes/
├─ scripts/
├─ tests/
├─ docs/
├─ addons/game_foundation/
└─ .game-foundation.json
```

Git submodule / subtreeをDefaultにしない。初心者向けHubでGitの追加概念を要求せず、Foundation更新時も管理対象を限定しやすいため。

## Source of Truth

`foundation-template.json` がStarter配布Contractの機械可読Source of Truth。Game Dev HubはこのManifestをValidationしてから生成・更新する。

## Managed Path

現在Foundationが後から更新してよいのは `addons/game_foundation/` だけ。

Starter生成後の `project.godot`、README、Roadmap、scenes、scripts、tests、Assets等はGame固有領域として扱い、Foundation更新では自動上書きしない。

## Installation Metadata

生成Game側にはGame Dev Hubが `.game-foundation.json` を作成する。

```json
{
  "schemaVersion": 1,
  "sourceRepository": "EliteMay/godot-game-foundation",
  "foundationVersion": "0.8.0-dev",
  "foundationCommit": "<full commit sha>",
  "managedPaths": ["addons/game_foundation"],
  "installedAt": "<ISO-8601>"
}
```

## 新規Game生成Flow

1. UserがGame Dev Hubでゲーム名と空のGitHub Repository URLを指定
2. Hubが対象RepositoryをClone
3. Repositoryが空であることを確認
4. HubがFoundation Repositoryの最新版を取得
5. ManifestをValidation
6. Starter FileをToken展開してCopy
7. Managed PathをCopy
8. `.game-foundation.json` を作成
9. Generated ProjectをGit Commit
10. GitHubへPush
11. HubへGameを登録

対象Repositoryに既存Fileがある場合は上書き生成しない。

## Foundation更新Flow

1. Game Repositoryが正常・clean・expected branchであることを確認
2. Foundation最新版とManifestを取得
3. Installation MetadataのSource / Managed PathをValidation
4. ManifestにあるManaged Pathだけ更新
5. Metadataを新Version / Commitへ更新
6. Hubの既存「GitHubに保存」FlowでDiff確認・Commit / Push

更新操作そのものではGame Repositoryを自動Commit / Pushしない。

## Version

Foundation Versionは `FOUNDATION_VERSION` とManifestの `foundationVersion` を一致させる。Game Versionとは別物。

## Compatibility

Breaking ChangeはManaged Pathを黙って配布せず、Foundation Version / Release Note / Migration方針で扱う。

Phase 8ではDeep FactoryをPilotとして導入し、既存GameplayとSave compatibilityを壊さないことを確認する。

## Generated Starter CI

Manifest単体のValidationだけでなく、CIでは `tools/materialize_starter_fixture.py` で実際のStarter Projectを一時Directoryへ生成する。

その生成物に対して:

1. Godot 4.7.2 import
2. Main Scene load
3. `FOUNDATION_INTEGRATION_SMOKE: PASS`

まで確認する。

これにより `.template` File自体はFoundation HarnessのImport対象外に保ちながら、実際にGame Dev Hubが展開する形のGodot ProjectがCold環境で成立することを確認する。

## Game Dev Hub Integration

Game Dev Hub v0.1.12で次を実装した。

- Foundation Starter Create Dialog
- Empty GitHub Repository Guard
- Initial Starter Commit / Push
- `.game-foundation.json` 読込
- Foundation Version / Commit表示
- Explicit Foundation Update
- Managed Path Contract Guard
- Existing GitHub Save FlowへのHandoff

Hub側のNode Test / Windows Installer CIと、Foundation側のGodot CI / Windows Buildは成功済み。

Windows実機での最終確認はRoadmapのUser Taskとして分離する。
