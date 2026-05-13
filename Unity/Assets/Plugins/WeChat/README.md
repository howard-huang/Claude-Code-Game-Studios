# WeChat Plugin Directory

This directory is **mostly empty by design**. Under ADR-0001, the Tuanjie
WeChat Mini Game SDK ships everything previously expected to live here — see
"Where the SDK actually lives" below.

## Where the SDK actually lives

The SDK installs via the Unity Package Manager (UPM) into:

```
Library/PackageCache/com.qq.weixin.minigame@<version>/
├── Runtime/
│   ├── WxWasmSDKRuntime.asmdef     ← C# surface (WeChatWASM.WX.*)
│   ├── Plugins/
│   │   ├── link.xml                ← SDK's own IL2CPP whitelist
│   │   └── *.jslib                 ← WebGL ↔ wx.* bindings
│   └── wx-runtime-editor.dll       ← Editor playmode mock
```

`Packages/manifest.json` should reference the package:

```json
{
  "dependencies": {
    "com.qq.weixin.minigame": "<version>"
  }
}
```

**Source repo**: <https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk>

## Why this directory is (almost) empty

The earlier v1 design assumed a custom `WxBridge.cs` adapter + project-side
`.jslib` files would live here. ADR-0001 was revised after inspecting the SDK:
it already provides the C# surface (`WeChatWASM.WX.*`), the Editor mock
(`wx-runtime-editor.dll`), the `.jslib` bindings, and its own `link.xml`. A
parallel project-side bridge would duplicate all of this.

Under the current design, gameplay code calls the **`Wx` Facade** at
`Unity/Assets/Scripts/Core/Platform/Wx.cs` — a thin static wrapper around
`WeChatWASM.WX.*` that flattens the SDK's callback-option pattern into
`Action`-based C# idioms and centralizes namespace isolation.

`using WeChatWASM;` outside `Unity/Assets/Scripts/Core/Platform/` is **forbidden**
(see `.claude/docs/technical-preferences.md`). All gameplay calls the Facade.

## What may live here

This directory exists as a designated location for **project-specific** WeChat
integration files that are not part of the SDK:

- `subpackages.json` — subpackage manifest consumed by the build pipeline (ADR-0003)
- Project-authored `.jslib` files for any `wx.*` API the SDK does not expose
  (rare; add only after the Facade proves insufficient)
- WeChat developer config (e.g. `project.config.json` post-build, but those
  typically land in `WeChatProject/` outside this tree)

If a feature requires a project `.jslib`, document the gap in a follow-up ADR
before adding it — the assumption is that the SDK's `WeChatWASM.WX.*` surface
is sufficient.

## Tuanjie ↔ Unity 2021.3 compatibility

The SDK targets the **Tuanjie 团结** engine (Unity China fork, Unity 2022 LTS
base). Pure Unity 2021.3 LTS compatibility is a known integration gap — verify
at first build per `CCGS/Docs/architecture/adr-0001-wx-sdk-adapter-layer.md`.
