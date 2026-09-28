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

後続:

- One-shot Audio
- Bus Contract
- Lifetime / Cleanup for one-shot players
- Phase 13 full Audio Smoke / Runtime playback validation

Headless CIではLifecycle / State / Transition contractを検証します。実際のAudio出力品質、Codec、Loop seam、音量感は実Game / 実Audio deviceで確認します。
