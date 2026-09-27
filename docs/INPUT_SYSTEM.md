# Input System

## 目的

Game固有のAction名をFoundationへ固定せず、各Gameが定義したInput Actionを共通APIで作成・Rebind・保存・復元できるようにする。

Foundationは `move_forward`、`jump`、`attack` などの名前を知る必要がない。

## Input Contract

Game側がDefault BindingをDictionaryで定義する。

```gdscript
var input_contract := {
    "move_forward": {
        "deadzone": 0.5,
        "events": [
            {
                "type": "key",
                "physical_keycode": KEY_W
            }
        ]
    },
    "attack": {
        "deadzone": 0.5,
        "events": [
            {
                "type": "mouse_button",
                "button_index": MOUSE_BUTTON_LEFT
            }
        ]
    }
}
```

FoundationはContractに書かれているActionだけを管理する。

## 対応Event

現在のData Modelは次を扱う。

- Keyboard
- Mouse Button
- Joypad Button
- Joypad Motion / Axis

保存形式とRuntime適用に加えて、Phase 12ではTheme-neutralなInput Remap UIからKeyboard / Mouse / GamepadをCaptureできる。

## Default適用

```gdscript
const InputSystem = preload(
    "res://addons/game_foundation/input/input_system.gd"
)

InputSystem.reset_to_defaults(input_contract)
```

Actionが無ければInputMapへ追加し、存在する場合はDefaultへ戻す。

## Rebind

```gdscript
InputSystem.rebind_action(
    input_contract,
    "move_forward",
    {
        "type": "key",
        "physical_keycode": KEY_UP
    }
)
```

既定ではAction内の既存Eventを置き換える。

Game固有UIから直接 `descriptor_from_event()` を使えるほか、Phase 12の `input_remap_control.gd` でCurrent Binding表示・入力待機・Rebindを共通化できる。

## Persistence

Default Path:

```text
user://input_bindings.json
```

Save:

```gdscript
InputSystem.save_bindings(input_contract)
```

Restore:

```gdscript
InputSystem.restore_bindings(input_contract)
```

保存Fileが無い場合やJSONが壊れている場合はDefault Bindingへ安全に戻る。

Game Updateで新しいActionがContractへ追加された場合、保存Fileに無いActionだけDefaultを使う。

## File Format

```json
{
  "metadata": {
    "format": "godot-game-foundation-input-bindings",
    "input_schema_version": 1,
    "saved_at_unix": 1790000000
  },
  "bindings": {
    "move_forward": {
      "deadzone": 0.5,
      "events": [
        {
          "type": "key",
          "physical_keycode": 87
        }
      ]
    }
  }
}
```

Key codeの数値はGodotのInput Eventとして復元するための値で、Game Logicが直接解釈する前提ではない。

## Keyboard

Keyboard Bindingでは `physical_keycode` を優先できる。

WASDのように物理位置を基準にしたいGameはPhysical Keyを使い、文字入力に近い用途では `keycode` を利用できる。

Modifierも保存可能:

- Shift
- Ctrl
- Alt
- Meta

## Mouse

Mouse Buttonを保存できる。

Mouse Motion自体はAction Bindingではないため、このPhaseではRebind対象にしない。Mouse SensitivityはSettings SystemのGame拡張Settingとして扱う。

## Gamepad

保存形式は以下に対応する。

- `joypad_button`
- `joypad_motion`

Deviceは `-1` を使えば特定Controllerへ固定しないBindingとして定義できる。

Input Remap UIではGamepad ButtonとAxisをCaptureできる。既定ではdeviceを`-1`へ正規化し、Axis driftは設定Threshold未満を無視する。

## 責務分担

Foundation:
- Input Contract検証
- InputMap Action作成
- Rebind
- Default復元
- Keyboard / Mouse / Gamepad EventのSerialize / Deserialize
- Binding保存 / 復元

Game:
- Action名
- Default Binding
- Actionの表示名 / Theme / Options画面構成
- 同じKeyを複数Actionへ割り当てるか等のConflict Policy
- Gameplay中にどのActionをどう使うか

## Conflict Detection

`InputConflictResolver.find_conflicts()` でCandidate DescriptorとCurrent Bindingの競合を取得できます。

`rebind_with_policy()` は次を提供します。

- `reject`: 競合時は変更しない
- `replace`: 競合Actionから一致Eventだけを外す
- `allow`: 既存Actionを残す

Joypadの`device=-1`はwildcardとしてspecific deviceと重なります。Axisは同じaxisでも正負方向を別Bindingとして扱います。

Conflict policyはGame側が選択し、Foundationは特定Policyを正解として固定しません。

## Input Prompt Resolver

`InputPromptResolver` はCurrent deviceとCurrent Bindingから、HUD / Tutorial / Optionsで再利用できるTextとsemantic Icon keyを解決する。

- keyboard/mouseとgamepadのCurrent device familyを追跡
- drift / jitter / release / key echoをdevice切替から除外
- Current device向けBindingを優先
- 必要なら別device BindingへFallback
- Modifierは複数`icon_keys`へ分離
- Gamepad face buttonは`gamepad_south/east/west/north`として製品非依存化
- `text_overrides` / `icon_key_overrides`でLocalizationや外部Icon PackへAdapter可能
- Icon画像自体はFoundationへ含めない

Current deviceはPrompt presentation用Stateであり、InputMapや保存BindingのSource of Truthではない。

## Rebind UI

`addons/game_foundation/input/input_remap_control.gd` は、Input Systemの既存Contract / Descriptor / Rebind APIを利用する共通Rowです。

- Internal Action IDと表示名を分離
- Keyboard / Mouse Button / Joypad Button / Joypad MotionをCapture
- Capture Cancelの物理Keyを固定しない
- Optional persistence callback
- Persistence failure時はRebind前BindingsへRuntime rollbackを試す
- Theme / final layout / Conflict PolicyはGameまたは後続Componentへ残す

Conflict Detectionは `input_conflict_resolver.gd`、Input Prompt Resolverは `input_prompt_resolver.gd` として実装済みです。Game側はConflict Policy、表示Text、Icon Pack mappingを選択できます。
