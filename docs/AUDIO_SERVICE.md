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

Current Global Music実装は `bus_name` をGame側から受け取ります。Standaloneの安全なDefaultは `Master` です。

Phase 13の後続Bus Contractで、既存Settingsの `audio_bus_map` と同じGame-defined Bus名を正式に共有します。現時点ではFoundationが `BGM` Busの存在を勝手に作成したり、ProjectのAudio Bus Layoutを書き換えたりしません。

### Asset Boundary

FoundationはBGM Asset自体を持ちません。

`AudioStream` はGame側から渡します。Loop設定、Import設定、Codec、Music内容等もGame Asset側の責務です。

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

後続:

- Bus Contract
- Lifetime / Cleanupの最終Contract確認
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

### Interim bus mapping

One-shot Serviceは現段階で `sfx / ui / voice` のBus名をGame側から受け取ります。2D / 3Dは既定で `sfx` Busを使います。

これはPhase 13後続のBus Contract前の局所設定です。FoundationはBusを作成せず、存在しないBusを自動修正しません。後続TaskでSettingsの `audio_bus_map` とAudio Serviceを同じGame-defined Bus Contractへ接続します。

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

