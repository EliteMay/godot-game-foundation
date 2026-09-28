# Audio Service

Phase 13では、Settingsの音量適用とは別に、複数Gameで繰り返すAudio再生LifecycleをOptional Serviceとして共通化します。

## Global Music Service

`addons/game_foundation/audio/global_music_service.gd` はSceneを跨いで維持できるBGM Playerです。

```gdscript
const GlobalMusicService = preload(
    "res://addons/game_foundation/audio/global_music_service.gd"
)

var music := GlobalMusicService.new()
add_child(music)

music.configure({
    "bus_name": "BGM",
    "persist_across_scenes": true,
    "default_fade_seconds": 0.25,
    "default_crossfade_seconds": 0.5,
})

music.play_music(menu_theme, {
    "track_id": "menu",
})
```

### Sceneを跨ぐLifetime

`persist_across_scenes=true` の場合、ServiceはSceneTreeへ入った後に `SceneTree.root` 直下へ移動します。

そのため、Game FlowがCurrent Sceneを変更してもMusic Service自体はSceneと一緒に解放されません。

Game側が独自AutoloadやLifecycle Managerを持つ場合は `persist_across_scenes=false` にして、その親側でLifetimeを管理できます。

### Fade / Crossfade

最初のTrackは `fade_in_seconds`、再生中の別Trackへの切替は `crossfade_seconds` を利用します。

Crossfadeは2つの `AudioStreamPlayer` を再利用し、旧TrackをFade outしながら新TrackをFade inします。Transition中の別Play / Stop requestは `transition_in_progress` として拒否し、複数Tweenが同じPlayerを同時変更しないようにします。

```gdscript
music.play_music(gameplay_theme, {
    "track_id": "gameplay",
    "crossfade_seconds": 0.8,
})

music.stop_music(0.4)
```

Fade値は0〜30秒です。0なら即時切替 / Stopです。

### Bus

推奨構成では、Settingsと同じGame-defined `audio_bus_map` を渡し、Global Musicはその `bgm` を利用します。

```gdscript
music.configure({
    "audio_bus_map": audio_bus_map,
    "persist_across_scenes": true,
})
```

旧 `bus_name` もStandalone / 既存Game互換用に残します。ただし `audio_bus_map` と `bus_name` を同時指定するとSource of Truthが二重になるため `ambiguous_bus_configuration` で拒否します。

### Asset Boundary

FoundationはBGM Asset自体を持ちません。

`AudioStream` はGame側から渡します。Loop設定、Import設定、Codec、Music内容等もGame Asset側の責務です。


## Audio Bus Contract

`addons/game_foundation/audio/audio_bus_contract.gd` は、Settings・Global Music・One-shot Audioが同じLogical Bus → Godot Bus名Mappingを使うための共通Contractです。

```gdscript
var audio_bus_map := {
    "master": "Master",
    "bgm": "Music",
    "sfx": "Effects",
    "ui": "Interface",
    "voice": "Dialogue",
}
```

### Logical keys

Foundation共通の基準は次です。

- `master` — Settings Master volume
- `bgm` — Settings BGM volume / Global Music
- `sfx` — Settings SFX volume / 2D・3D One-shot default
- `ui` — UI one-shot
- `voice` — Voice one-shot

既存Gameとの互換性のため、`master / bgm / sfx` だけの旧Mappingも有効です。その場合 `ui / voice` は `sfx` と同じBusへ自動Fallbackします。

Game固有の `ambience` 等の追加Logical keyも保持します。Foundationは未知keyを勝手に削除しません。

### FoundationRuntimeとの共有

`FoundationRuntime.settings.audio_bus_map` はconfigure時にこのContractでNormalizeされます。

```gdscript
runtime.configure({
    "settings": {
        "audio_bus_map": audio_bus_map,
    },
})
```

同じMappingをOptional Audio Serviceへ渡すことで、SettingsのVolume適用先と再生Serviceの出力先を一致させられます。

### Validation / AudioServer boundary

Bus名は空文字を拒否しますが、FoundationはProjectのAudio Bus Layoutを勝手に作成・Renameしません。

`AudioBusContract.inspect_audio_server()` でCurrent Projectに存在するBus / Missing Busを確認できます。Settings Runtimeも実際の適用時にMissing BusをResultへ返します。

このContractは「Logical keyとBus名の正本」を共通化するもので、AudioServer LayoutそのものをFoundationへ所有させる仕組みではありません。

## Current Phase 13 scope

実装済み:

- Global Music
  - scene-persistent lifetime
  - Play / Stop
  - Fade in / Fade out
  - Crossfade
  - overlapping transition guard
  - runtime status snapshot
- One-shot Audio
  - Global SFX / UI / Voice
  - 2D / 3D helper
  - active player limit
  - explicit stop / stop_all
  - finished / parent-exit tracking cleanup
- Bus Contract
  - Settings / Global Music / One-shot shared mapping
  - ui / voice → sfx compatibility fallback
  - legacy per-service mapping compatibility
  - AudioServer bus inspection

後続:

- Phase 13 full Audio Smoke / Runtime playback validation

Headless CIではLifecycle / State / Transition contractを検証します。実際のAudio出力品質、Codec、Loop seam、音量感は実Game / 実Audio deviceで確認します。

## One-shot Audio Service

`addons/game_foundation/audio/one_shot_audio_service.gd` は短いSFX / UI音 / Voiceと、Scene内の2D / 3D空間音を同じLifecycle APIから再生します。

```gdscript
const OneShotAudioService = preload(
    "res://addons/game_foundation/audio/one_shot_audio_service.gd"
)

var one_shots := OneShotAudioService.new()
add_child(one_shots)

one_shots.configure({
    "persist_across_scenes": true,
    "max_active_players": 64,
    "bus_names": {
        "sfx": "SFX",
        "ui": "SFX",
        "voice": "SFX",
    },
})

one_shots.play_sfx(hit_sound, {"tag": "hit"})
one_shots.play_ui(confirm_sound)
one_shots.play_voice(dialogue_line)
```

### Global SFX / UI / Voice

`play_sfx()` / `play_ui()` / `play_voice()` は通常の `AudioStreamPlayer` をService配下へ作成します。

- 再生完了時にPlayerを自動解放する
- `token` を返し、必要なら `stop_one_shot(token)` で明示停止できる
- `stop_all()` でService配下のOne-shotをまとめて停止できる
- `max_active_players` で同時生成数を上限化する
- `volume_db` / `pitch_scale` / `start_position` / `tag` / `bus_name` を指定できる

既定の同時再生上限は64、Foundation側Hard Limitは256です。

### 2D / 3D helper

Spatial AudioはWorld Contextを失わないよう、Game側のScene-owned Parentを明示して再生します。

```gdscript
one_shots.play_2d(
    explosion_sound,
    world_2d,
    explosion_global_position
)

one_shots.play_3d(
    voice_sound,
    actor_3d,
    actor_3d.global_position
)
```

2Dは `Node2D`、3Dは `Node3D` のParentを要求します。PlayerはそのParentのChildになるため、World / Scene側が解放された時はSpatial Playerも一緒に解放され、Serviceのactive trackingから外れます。

特殊なAttenuation、Area Mask、Emission Angle等が必要なGameはGame側の専用Playerを使えます。FoundationのHelperは共通的なStream / Bus / Volume / Pitch / Position Lifecycleへ限定します。

### Bus mapping

推奨構成ではGlobal Music / Settingsと同じ `audio_bus_map` を渡します。One-shot Serviceは `sfx / ui / voice` を利用し、2D / 3Dは既定で `sfx` を利用します。

```gdscript
one_shots.configure({
    "audio_bus_map": audio_bus_map,
    "persist_across_scenes": true,
})
```

旧 `bus_names` も互換用に残しますが、Shared Contractとの同時指定は拒否します。個別の `play_*()` 呼出しで `bus_name` を明示するOverrideは引き続き利用できます。

### Headless / Runtime validation

Headless Smokeでは次を検証します。

- Global SFX / UI / Voice helper
- 2D / 3D helperのParent Contract
- active player上限
- explicit stop / stop_all
- finished playerの自動cleanup
- Spatial Parent解放時のtracking cleanup
- Serviceのscene-persistent lifetime

実Audio device上の定位、距離減衰、Voiceの聞こえ方、同時発音時のMixは実Game統合時のRuntime Validation対象です。


## Audio Resource Lifecycle / Cleanup

Phase 13のPlayback Serviceは、再生開始だけでなく**明示的な終了とScene / Service破棄時のResource解放**もContractに含めます。

### Global Music

`GlobalMusicService.dispose_audio()` は次を行います。

- Active Fade / Crossfade Tweenを停止
- 2つの再利用 `AudioStreamPlayer` を停止
- Playerの `stream` 参照を `null` へ戻す
- Current / Pending Track IDとTransition StateをReset
- Serviceを未configured状態へ戻し、新しいPlayback前に再configureを要求

Dispose時にLifecycle Generationを進めるため、Dispose前に作られた古いTween callbackが後から実行されても、再configure後の新しいTrack Stateを書き換えません。

Service Node自体が破棄される場合も `NOTIFICATION_PREDELETE` で同じCleanupをSignalなしで行います。Scene-persistent化のためのReparentではCleanupしません。

### One-shot Audio

`OneShotAudioService.dispose_audio()` は、Serviceが追跡しているGlobal SFX / UI / Voiceと2D / 3D Spatial Playerをすべて停止・解放します。

- active trackingを即時0へ戻す
- Serviceを未configured状態へ戻す
- 同じService Instanceを再configureして再利用できる
- Service Node自体が破棄される時も、外部Node2D / Node3D配下へ生成したSpatial PlayerをCleanupする

これにより、Scene-persistent Serviceだけを破棄した時にSpatial PlayerがWorld側へ孤立して残る状態を防ぎます。

通常再生時は既存のCleanupも継続します。

- AudioStreamPlayerの `finished`
- `stop_one_shot(token)`
- `stop_all()`
- Spatial Parentのtree exit

### Boundary

`dispose_audio()` はPlayback Resourceを解放しますが、Service Node自体を `queue_free()` しません。Gameは必要に応じて再configureして再利用するか、その後Service Nodeを破棄できます。

FoundationはGameのScene Tree ownershipそのものを変更しません。Spatial Playerは引き続きGame側World Parentへ所属します。


