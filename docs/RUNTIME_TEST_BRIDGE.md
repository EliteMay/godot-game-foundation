# Runtime Test Bridge

## 目的

Game Dev Hubが固定テストをAIのScreenshot判断へ依存せず、実Gameの内部状態を機械的に比較できるようにするための開発用Bridgeです。

Foundationはゲーム固有のStateを知りません。Game側がJSON互換DictionaryをProviderとして渡し、BridgeはHubが指定したLocal JSON FileへSnapshotを書き出します。

## 起動Contract

Game Dev HubはGodot起動時に `--` より後へ次のUser Argumentを渡します。

```text
--foundation-test-state=<absolute-json-path>
--foundation-test-session=<random-session-id>
```

Game側は `RuntimeTestBridge.configure_from_command_line(provider)` を呼びます。Argumentが無い通常起動ではBridgeは無効で、File出力も行いません。

## State Contract

ProviderはJSON互換Dictionaryだけを返します。

例:

```json
{
  "ready": true,
  "player": {
    "position": [1.0, 0.0, 2.0],
    "yaw": 0.25,
    "pitch": -0.1
  },
  "inventory": {
    "count": 3,
    "money": 25
  }
}
```

Foundation側Envelopeには `schemaVersion`、`sessionId`、`sequence`、`capturedAtUnixMs`、`processId`、`gameVersion` を付けます。

## Security / Scope

- Network Serverは開かない
- Command実行Channelは持たない
- Hubが明示的にTest Argumentを付けたRunだけ有効
- Game固有Stateの選定はGame Repository側が担当
- Secret / Credential / Home Path等をProviderへ含めない
- BridgeはRoadmap完了やGame RuleのSource of Truthにならない

## 使い分け

- WASD、Camera、Inventory、Save/Load等の固定確認 → Test Bridge + deterministic input
- UIの分かりやすさ、自由探索、未知Bug探索 → Human Playtest / Experimental Computer Use

Screenshotは補助Evidenceとして利用できますが、数値で取得できる固定条件のPrimary verdictには使いません。
