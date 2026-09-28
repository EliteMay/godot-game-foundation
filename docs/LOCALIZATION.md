# Localization Contract

Phase 15のLocalization共通境界です。

## Ownership

Foundationが所有するもの:

- Settingsのlocale preference適用
- Main Menu / Pause Menuのsemantic text contract
- TranslationServerへのCurrent Locale lookup
- 未翻訳時のfallback
- Locale変更時のShell refresh

Game側が所有するもの:

- Translation Resource / CSV / PO
- 実際の翻訳本文
- Font / fallback font
- 対応言語一覧とLanguage Selector UI
- Game固有Text key
- Long text / RTL / layout調整

## Locale Setting

Settingsの共通Field:

```json
{
  "locale": "automatic"
}
```

`automatic` はOSの優先言語を使用します。明示値はGodotのLocale標準化を通してTranslationServerへ適用します。

## Translation Entries

Main Menu / Pause Menuはsemantic actionごとにDefault entryを持ちます。

例:

```gdscript
menu.configure({
    "flow_service": flow,
    "new_game_action": start_new_game,
    "translation_entries": {
        "new_game": {
            "key": "MY_GAME_MENU_NEW_GAME",
            "fallback": "New Game",
            "context": "main_menu",
        },
        "options": "MY_GAME_MENU_OPTIONS",
    },
})
```

String値はTranslation keyだけを差し替えるshort formです。Dictionaryでは`key` / `fallback` / `context`を指定できます。

## Resolution Order

1. Existing explicit `labels` override
2. Current LocaleのTranslationServer translation
3. Translation Contract fallback

`labels`は既存互換と完全なGame側明示Text用です。Locale変更後も自動翻訳で上書きしません。

## Runtime Locale Change

Main Menu / Pause MenuはGodotの`NOTIFICATION_TRANSLATION_CHANGED`を受け、Translation Contractを再解決します。

必要な場合はGame側から明示的に`refresh_translations()`を呼ぶこともできます。

## Validation Boundary

Headless Smokeで確認するもの:

- Contract validation
- Translation key override
- context付きTranslation
- missing key fallback
- Japanese / English Locale切替
- Shell auto refresh
- legacy labels precedence

Game統合時に確認するもの:

- 実Translation Resource coverage
- Font fallback
- CJK glyph
- 長文によるLayout崩れ
- RTL / BiDi
- 実際の翻訳品質
