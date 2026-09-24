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

GamepadはPrototype段階でUIまで固定しないが、保存形式とRuntime適用は最初から対応する。

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

Game固有のInput UIは、ユーザーが押したInputEventを `descriptor_from_event()` で保存用Descriptorへ変換できる。

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

今後Gamepad UIを追加してもFile Schemaを作り直さなくてよい構造にする。

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
- Rebind UI
- 同じKeyを複数Actionへ割り当てるか等のConflict Policy
- Gameplay中にどのActionをどう使うか
