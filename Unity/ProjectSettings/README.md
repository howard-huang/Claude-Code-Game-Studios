# Player Settings Checklist — First Open

Unity overwrites most binary `*.asset` files on first project load, so the
template only ships `ProjectVersion.txt`. After Unity Hub recognizes the project
and Library/ has been rebuilt, configure these settings manually in
**Edit → Project Settings**.

## Player → Other Settings

### Scripting

- [ ] **Scripting Backend** = `IL2CPP`
- [ ] **Api Compatibility Level** = `.NET Standard 2.1`
- [ ] **Managed Stripping Level** = `High`  *(ADR-0005)*
- [ ] **C++ Compiler Configuration** = `Master` (release builds)
- [ ] **Use incremental GC** = ON

### Rendering

- [ ] **Color Space** = `Linear`
- [ ] **Auto Graphics API** = OFF
- [ ] **Graphics APIs** = `WebGL 2.0` only  *(no WebGL 1.0 fallback)*
- [ ] **Static Batching** = ON
- [ ] **Dynamic Batching** = ON
- [ ] **GPU Skinning** = OFF  *(WebGL incompatible)*
- [ ] **Lightmap Encoding** = `Normal Quality`

### Configuration

- [ ] **Scripting Define Symbols** = (leave empty unless feature-flagging)
- [ ] **Allow 'unsafe' Code** = OFF

## Player → Publishing Settings (WebGL)

- [ ] **Compression Format** = `Brotli`
- [ ] **Decompression Fallback** = OFF  *(WeChat handles it)*
- [ ] **Name Files As Hashes** = ON
- [ ] **Data Caching** = ON
- [ ] **Debug Symbols** = OFF (release) / `Embedded` (dev only)

## Player → Resolution and Presentation

- [ ] **Default Canvas Width** = `720`  *(portrait mobile — WeChat default)*
- [ ] **Default Canvas Height** = `1280`
- [ ] **Run In Background** = OFF

## Build Settings

- [ ] **Build Target** = `WebGL`
- [ ] **Switch Platform** invoked once (creates platform-specific assets)
- [ ] **Development Build** = OFF (release) / ON (dev iterations)

## Graphics → Built-in Render Pipeline  *(ADR-0004)*

- [ ] **Scriptable Render Pipeline Settings** = `None` *(empty — no SRP asset)*
- [ ] `Packages/manifest.json` does NOT contain `com.unity.render-pipelines.universal`
- [ ] `Packages/manifest.json` does NOT contain `com.unity.render-pipelines.high-definition`

## Memory (WebGL Player Settings → Memory)

- [ ] **Initial Memory Size** = `32 MB`
- [ ] **Maximum Memory Size** = `256 MB`  *(WeChat ceiling — ADR-0002)*
- [ ] **Memory Growth Mode** = `Geometric`
- [ ] **Linear Memory Growth Step** = `16`

## Quality

- [ ] Single quality preset for WebGL  *(strip the others)*
- [ ] **VSync Count** = `Don't Sync`
- [ ] **Anti Aliasing** = `Disabled` or `2× Multi Sampling`  *(measure cost)*
- [ ] **Shadows** = `Hard Shadows Only` or `Disable Shadows`

## Verification After First Build

- [ ] First-package size ≤ 4 MB *(measured by `PackageBudgetGate` — ADR-0002)*
- [ ] Each subpackage ≤ 4 MB
- [ ] Total ≤ 20 MB
- [ ] WebGL build opens in Chrome without console errors

## Related ADRs

- ADR-0001 — `Wx` Facade (`Unity/Assets/Scripts/Core/Platform/Wx.cs`) wraps `WeChatWASM.WX.*`
- ADR-0002 — 4 MB first-package budget
- ADR-0003 — SubPackages mandatory; Addressables forbidden
- ADR-0004 — Built-in RP default; URP Phase 2 opt-in
- ADR-0005 — IL2CPP Strip High + link.xml
- ADR-0006 — Audio routing strategy
