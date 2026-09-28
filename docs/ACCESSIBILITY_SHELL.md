# Accessibility Shell

Phase 15の基本操作Accessibility Contractです。

## Focus / Navigation Baseline

FoundationのMain Menu / Pause Menuは、物理Keyや特定Controller製品ではなくGodotのsemantic UI actionを基準にします。

Required Baseline:

- `ui_up`
- `ui_down`
- `ui_accept`

`FocusNavigationBaseline.validate_input_actions()` は各Actionについて次を確認します。

- InputMap actionが存在する
- Keyboard bindingが1つ以上ある
- Gamepad bindingが1つ以上ある

不足時はInputMapを勝手に変更せず、構造化Resultで不足Action / Device coverageを返します。

Required semantic action自体が無い場合はBaseline成立不能として扱います。一方、Keyboard / Gamepadのどちらか一方のBinding不足はFocus graph構築を止めません。Runtime Snapshotの `keyboard_ready` / `gamepad_ready` で不足を観測し、Game側InputMapで補います。

## Focus Graph

Vertical Menuでは既存 `MenuFocusNavigation` を利用します。

- hidden Controlを除外
- disabled Buttonを除外
- visual orderで上下Neighborを構成
- 非Modal Baselineでは先頭 / 末尾をHard wrapしない
- Custom layoutは `manage_focus_navigation=false` でGame側へ委譲可能

## Focus Recovery

Menu action availabilityの変更等でCurrent Focusが無効になった場合:

1. 現在Focusがまだ有効なら維持
2. 別Overlay等のValid external focusなら奪わない
3. Preferred controlが指定され利用可能ならそこへ移動
4. それ以外は最初のfocusable controlへ戻す

Main MenuはContinue等のavailability変更後にこのrepairを利用します。

Pause MenuはOpen時に最初の利用可能ActionへFocusし、Close時には既存Contractどおり可能なら前のFocus ownerへ戻します。

## Back / Cancel

`ui_cancel` はRequired Baselineに含めません。

理由:

- Pause Menuを閉じる
- Submenuへ戻る
- Modalを閉じる
- ConfirmationをCancelする

など、Back / Cancelの意味がGame / Surfaceごとに異なるためです。Foundationは物理Escape / Controller ButtonをHardcodeしません。

## Validation

Headless CI:

- Required semantic action存在確認
- Keyboard / Gamepad binding coverage
- hidden / disabled skip
- `ui_down / ui_up / ui_accept`
- Focus repair
- External focus preserve
- Main / Pause Menu regression

Game統合時:

- 実Keyboardでの操作感
- 実ControllerでのD-pad / Stick / Confirm操作
- Game固有Options / Modal / Nested Menu
- Focus visual readability
- Controller種類ごとのPrompt / Glyph整合
