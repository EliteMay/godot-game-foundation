# Windows Build

## 目的

Foundationを使ったGodot Projectが、Windows向けRelease Buildを再現可能な方法で作れる状態を共通化する。

このRepositoryではFoundation開発用HarnessをWindows x86_64へExportし、GitHub Actions Artifactとして保存する。

## Export Preset

`export_presets.cfg` に `Windows Desktop` Presetを定義する。

現在の基準:

- Platform: Windows Desktop
- Architecture: x86_64
- Release Export
- PCKをEXEへEmbed
- Windows Resource Metadataを有効化
- Code Signingは未設定

Output:

```text
builds/windows/GodotGameFoundation.exe
```

各GameへStarterとして導入した後はProduct Name / Description / Icon等をGame名に合わせて変更する。

## Version Source

Foundation Harnessでは次を一致させる。

```text
project.godot
application/config/version
        =
Foundation.FOUNDATION_VERSION
```

Windows Export Presetの `application/file_version` と `application/product_version` は空にしている。Godot Windows Exporterは空の場合 `ProjectSettings.application/config/version` へFallbackするため、Version SourceをProject Settingへ一本化する。

`tests/build_config_smoke.gd` がVersion DriftとExport Presetの主要設定をCIで検出する。

Game Repositoryへ導入した後はGame VersionとFoundation Versionは別物になるため、Game側の `application/config/version` をGame Versionとして管理し、DiagnosticsではFoundation Versionを別Fieldで保持する。

## CI Export

`.github/workflows/windows-build.yml` は次で動く。

- mainへのpush
- Pull Request
- `v*` Tag push
- 手動実行

処理:

1. Godot 4.7.2 EditorをDownload
2. Godot 4.7.2 Export TemplatesをInstall
3. Project Import
4. Build Config Smoke Test
5. Windows Desktop Release Export
6. EXEがPE形式として生成されたことを確認
7. `build-info.json` を生成
8. GitHub Actions ArtifactへUpload

Artifact:

```text
godot-game-foundation-windows-<commit sha>
├─ GodotGameFoundation.exe
└─ build-info.json
```

Artifactの保持期間は14日。

## build-info.json

CI Artifactには少なくとも次を含める。

- App Name
- App Version
- Godot Version
- Platform
- Architecture
- Commit SHA
- Git Ref
- GitHub Actions Run ID
- Code Signing有無

これにより「どのSourceから作ったEXEか」を後から追跡しやすくする。

## Release手順

Foundation Releaseを作る場合:

1. `main` のGodot CIとWindows Buildが成功していることを確認する
2. Release Versionを決める
3. `application/config/version` と `Foundation.FOUNDATION_VERSION` を同じVersionへ更新する
4. CIが再度すべて成功することを確認する
5. `v<version>` Tagを作成してpushする
6. Tag用Windows Build Artifactが成功することを確認する
7. GitHub Releaseを作成する
8. Tag BuildのArtifactをRelease Assetとして添付する
9. Release NotesへBreaking Change / Migration / Godot Baseline変更を記録する

現在は自動GitHub Release作成までは行わない。意図しないTagや開発中Versionを自動公開しないため、Release公開は明示操作に残す。

## Code Signing

現在のFoundation Harness ArtifactはUnsigned。

本番配布するGameでWindows Code Signingを使う場合は、CertificateやPasswordをRepositoryへCommitせず、GitHub Actions Secret / Environment等から渡す。

署名導入はGame側の配布方針とCertificate準備が必要なため、Foundation CoreのPhase 6完了条件には含めない。

## ローカルExport

Godot 4.7.2と同VersionのExport TemplatesがInstall済みなら:

```powershell
godot --path . --export-release "Windows Desktop" builds/windows/GodotGameFoundation.exe
```

Godot公式のCLI ExportはExport PresetとExport Templatesを必要とする。
