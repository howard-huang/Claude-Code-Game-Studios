# ADR-0001: WX-SDK Facade Layer

## Status

Proposed

## Date

2026-05-13

## Last Verified

2026-05-13

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (engine integration)
- User (final sign-off on Tuanjie SDK ↔ Unity 2021.3 compatibility)

## Summary

All gameplay calls to the WeChat runtime go through a single thin **Facade**
class `Wx` (namespace `CCGS.Core.Platform`) that wraps `WeChatWASM.WX.*` from
the Tuanjie SDK. The Facade exists for **namespace isolation, idiomatic C#
API shape, and a stable seam against future SDK swaps** — NOT to provide JS
bridging or Editor mocking (the SDK already provides both).

### Why a Facade, not a Bridge (revised 2026-05-13)

Inspection of `Library/PackageCache/com.qq.weixin.minigame@*/Runtime/` after
installing the Tuanjie SDK via UPM revealed the SDK already ships:

- 800+ public static methods on `WeChatWASM.WX` / `WXBase` covering the full
  `wx.*` surface (login, subpackages, audio, system info, share, payment, …)
- `wx-runtime-editor.dll` — Editor-side mock that lets `WX.*` calls succeed
  inside the Unity Editor without a real WeChat runtime
- `Runtime/Plugins/*.jslib` files and `Runtime/Plugins/link.xml` already
  bundled in the package
- Compile guards `#if UNITY_WEBGL || WEIXINMINIGAME || UNITY_EDITOR` on every
  managed entry point
- An assembly definition `WxWasmSDKRuntime.asmdef`

A custom Bridge with our own `[DllImport("__Internal")]`, our own
`WxBridge.jslib`, and our own Mock subclass would **reinvent what the SDK
already provides**. The Facade pattern is the correct fit: it gives us
namespace isolation and idiomatic-C# composed APIs without duplicating SDK
plumbing.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Core / Platform Integration |
| **Knowledge Risk** | HIGH — Tuanjie SDK targets the Tuanjie 团结 engine fork; pure Unity 2021.3 support is unverified |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, `minigame-tuanjie-transform-sdk` repo, package source at `Library/PackageCache/com.qq.weixin.minigame@*/Runtime/` |
| **Post-Cutoff APIs Used** | `WeChatWASM.WX.*` static methods (entire surface post-cutoff) |
| **Verification Required** | Tuanjie SDK loads, links, and runs on pure Unity 2021.3.40f1 + IL2CPP + WebGL build. If it does not, user must choose: (a) migrate to Tuanjie engine, or (b) pin to an older WX-SDK that supported Unity 2021. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0003 (`Wx.LoadSubpackage` wraps `WeChatWASM.WX.LoadSubpackage`), ADR-0006 (`Wx.PlayBgm` wraps `WeChatWASM.WX.CreateInnerAudioContext`) |
| **Blocks** | Any story that calls `WeChatWASM.WX.*` directly from gameplay code without going through `Wx` |
| **Ordering Note** | This ADR must be Accepted before any subpackage or platform-audio story can start. |

## Context

### Problem Statement

The Tuanjie SDK exposes 800+ static methods on `WeChatWASM.WX`. If gameplay
code calls these directly from every system, three problems emerge:

1. **Namespace pollution** — `WeChatWASM` leaks into gameplay code, coupling
   business logic to a third-party namespace.
2. **No composed APIs** — SDK methods are 1:1 mirrors of the JS callback
   shape (`success`, `fail`, `complete` option objects). Idiomatic C# wants
   `Action<T>` / `Task<T>` callbacks.
3. **No swap seam** — If we ever migrate off Tuanjie (to a different WX-SDK
   or to the native Tuanjie engine), every gameplay file needs editing.

A thin Facade solves all three with ~30 lines per public method. It needs
no `.jslib`, no `[DllImport]`, and no Mock subclass — the SDK already
provides them.

### Current State

Nothing exists yet — this is a greenfield template. The Tuanjie SDK is
installed via UPM (`com.qq.weixin.minigame` from the GitHub repo) and is
the only consumer of the WeChat runtime in the project.

### Constraints

- The Tuanjie SDK is the only currently supported transform — but it targets
  the Tuanjie engine (Unity China fork, Unity 2022 LTS base). Pure Unity
  2021.3 support is **unverified**.
- IL2CPP Strip High (ADR-0005) requires SDK reflection-used types in
  `link.xml`. The SDK ships its own `link.xml` at
  `Runtime/Plugins/link.xml` — no project-level entries needed for SDK calls.
- The SDK's compile guards already require `#if UNITY_WEBGL || WEIXINMINIGAME
  || UNITY_EDITOR`. The Facade inherits this constraint by reference.

### Requirements

- Exactly one C# file owns the Facade methods (`Wx.cs`).
- Gameplay code calls `CCGS.Core.Platform.Wx.*`, never `WeChatWASM.WX.*`
  directly.
- Facade methods return idiomatic C# shapes (`Action<T>` callbacks or
  `Task<T>`), not SDK option objects.
- Editor playmode works without modification — Facade calls dispatch through
  the SDK's `wx-runtime-editor.dll` automatically.
- An EditMode unit test verifies a representative Facade method compiles and
  the callback-shape conversion is correct.

## Decision

Create `Unity/Assets/Scripts/Core/Platform/Wx.cs` as a `static class` that
**wraps** `WeChatWASM.WX.*` calls. The class has:

1. Public static methods only — no fields, no state.
2. Each method composes 1 underlying SDK call, converting SDK option objects
   into idiomatic C# `Action<T>` callbacks.
3. **No** `[DllImport("__Internal")]` extern declarations.
4. **No** project-owned `.jslib` files.
5. **No** Mock subclass — the SDK's `wx-runtime-editor.dll` handles Editor
   mocking automatically.

### Architecture

```
Gameplay code (CCGS.Gameplay / CCGS.UI / ...)
     │
     ▼
CCGS.Core.Platform.Wx (static Facade — single entry point)
     │
     ▼
WeChatWASM.WX (SDK static surface — 800+ methods)
     │
     ├─ UNITY_WEBGL && !UNITY_EDITOR ─→ SDK's own .jslib ──→ wx.* runtime
     │
     └─ UNITY_EDITOR                  ─→ wx-runtime-editor.dll (SDK Editor mock)
```

### Key Interfaces

```csharp
using System;
using WeChatWASM;

namespace CCGS.Core.Platform
{
    /// <summary>
    /// Thin Facade over WeChatWASM.WX.*. Provides namespace isolation and
    /// idiomatic C# callback shapes. ~30 lines per wrapped API.
    /// </summary>
    public static class Wx
    {
        public static void Login(Action<string> onCode, Action<string> onError)
            => WX.Login(new LoginOption
            {
                success = res => onCode?.Invoke(res.code),
                fail    = res => onError?.Invoke(res.errMsg),
            });

        public static void LoadSubpackage(string name, Action onSuccess, Action<string> onError)
            => WX.LoadSubpackage(new LoadSubpackageOption
            {
                name    = name,
                success = _   => onSuccess?.Invoke(),
                fail    = res => onError?.Invoke(res.errMsg),
            });

        // ... one method per WeChatWASM.WX.* call the game actually uses
    }
}
```

### Implementation Guidelines

- Add Facade methods **on demand** — never wrap an SDK method speculatively.
- Each Facade method maps 1:1 to one underlying SDK method, with callback
  conversion as the only allowed transformation. If you need to compose 2+
  SDK calls, add a separate method named for the composed operation
  (e.g., `Wx.LoadSubpackageAndPreloadScene`, not generic batching).
- Do **not** add caching, retry, or business logic inside the Facade. Those
  belong in gameplay-layer code that calls the Facade.
- Use `Action<T>` for one-shot async callbacks; reserve `Task<T>` for cases
  where the caller already runs in an async context (Unity coroutine-first
  gameplay rarely needs this).
- Strings cross the C# / JS boundary inside the SDK — no need to marshal
  manually.

## Alternatives Considered

### Alternative 1: Call `WeChatWASM.WX.*` directly from gameplay (no Facade)

- **Description**: Skip the Facade entirely. Every system that needs the SDK
  imports `WeChatWASM` and calls it directly.
- **Pros**: Zero Facade maintenance; no abstraction tax.
- **Cons**: SDK namespace leaks into every gameplay file; SDK callback shapes
  (option objects with `success`/`fail`/`complete`) bleed into business logic;
  no swap seam if we migrate off Tuanjie.
- **Rejection Reason**: Namespace isolation alone is worth ~30 lines of
  Facade. The composed-API benefit compounds as the game grows.

### Alternative 2: Custom Bridge with own `.jslib` + Mock subclass (the original v1 design)

- **Description**: `WxBridge.cs` with `[DllImport("__Internal")]` extern
  declarations, custom `WxBridge.jslib`, custom `WxBridge.Mock` for Editor.
- **Pros**: Full control of the JS bridge surface; can intercept calls
  before they reach the SDK.
- **Cons**: Reinvents what the SDK already provides (`.jslib`, Editor mock,
  link.xml). Doubles maintenance — every `wx.*` call now has 3 layers
  (`WxBridge.*` → `WxBridge.jslib` → `wx.*`) instead of 2
  (`Wx.*` → `WeChatWASM.WX.*`). No real benefit because the SDK already gives
  us a Unity-managed entry point.
- **Rejection Reason**: SDK inspection (2026-05-13) showed the SDK ships
  `WeChatWASM.WX` static methods, `wx-runtime-editor.dll`, its own `.jslib`
  files, and `link.xml`. Building a parallel Bridge layer duplicates all of
  this for no architectural gain.

### Alternative 3: Scattered `[DllImport]` per system

- **Description**: Each system that needs `wx.*` declares its own externs and
  builds its own `.jslib`.
- **Pros**: No central file dependency.
- **Cons**: No mock path; multiple `.jslib` files; reflection-strip rules
  duplicated in N places; SDK upgrade requires edits in every system.
- **Rejection Reason**: Makes Editor debugging impossible *and* duplicates
  the SDK. Strictly worse than Alternative 2, which itself was rejected.

## Consequences

### Positive

- ~30 lines of code per wrapped API (vs ~80 lines for a Bridge with `.jslib`
  + Mock).
- Editor playmode works **out of the box** (SDK's `wx-runtime-editor.dll`).
- Gameplay code stays free of the `WeChatWASM` namespace.
- Future SDK migration is a single-file change inside `Wx.cs`.
- IL2CPP `link.xml` is the SDK's own — no project-level entries needed for
  `wx.*` calls (project-specific reflection entries still belong in a
  project-owned `link.xml` per ADR-0005).

### Negative

- Every new `wx.*` need requires a Facade method (~30 lines, ~5 min to write).
- Facade method shapes must be reviewed for idiomatic C# fit at PR time.

### Neutral

- All platform code clusters in `Unity/Assets/Scripts/Core/Platform/`.
- The Facade is a pure pass-through — no performance overhead worth
  measuring.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Tuanjie SDK refuses to load on pure Unity 2021.3 | HIGH | BLOCKING | Verify before first integration. If it fails, user decides: switch to Tuanjie engine, or pin to an older WX-SDK that supported Unity 2021. |
| Gameplay code starts calling `WeChatWASM.WX.*` directly, bypassing Facade | MEDIUM | MEDIUM | Add a forbidden-pattern rule: gameplay code must not import `WeChatWASM` outside `Core/Platform/`. Optionally enforce with an EditMode test that greps for `using WeChatWASM;` outside the allowed directory. |
| Facade methods drift from idiomatic C# style | LOW | LOW | Code review at PR time; the file is small enough to review in full on each change. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time per Facade call) | n/a | < 0.01 ms (pass-through, mostly inlined by IL2CPP) | Negligible |
| Memory | n/a | ~ 1 KB code per ~10 wrapped methods | < 50 KB |
| Load Time | n/a | n/a | n/a |
| Network | n/a | n/a | n/a |

## Migration Plan

This is a greenfield decision — no migration. Implementation order:

1. Create `Unity/Assets/Scripts/CCGS.Runtime.asmdef` that references
   `WxWasmSDKRuntime` (the SDK's assembly definition).
2. Create `Unity/Assets/Scripts/Core/Platform/Wx.cs` with one starter method
   (`Wx.Login`).
3. Modify `Unity/Assets/Tests/EditMode/EditModeTests.asmdef` to reference
   `CCGS.Runtime`.
4. Create `Unity/Assets/Tests/EditMode/WxFacadeTests.cs` with one EditMode
   test that verifies the SDK's Editor mock returns sensibly when `Wx.Login`
   is invoked.
5. **Run Editor playmode** to confirm `Wx.Login` does not crash and the SDK's
   `wx-runtime-editor.dll` returns the expected mock response.
6. **Run a smoke WebGL build to verify Tuanjie SDK + Facade link.**
7. If smoke build fails, escalate to user to resolve compatibility per the
   Verification Required field.
8. Once green, add real `wx.*` Facade methods on demand as features need them.

**Rollback plan**: revert `Wx.cs` and the asmdef. Nothing else depends on
the Facade yet.

## Validation Criteria

- [ ] `Unity/Assets/Scripts/CCGS.Runtime.asmdef` exists and references
      `WxWasmSDKRuntime`.
- [ ] `Unity/Assets/Scripts/Core/Platform/Wx.cs` exists with at least one
      Facade method (`Wx.Login`).
- [ ] No `[DllImport("__Internal")]` declarations in project code (SDK ships
      its own).
- [ ] No project-owned `*.jslib` files in `Unity/Assets/Plugins/WeChat/` for
      `wx.*` bridging (SDK ships its own).
- [ ] EditMode test `Wx_Login_SdkMockReturnsCode` (or equivalent) passes in
      Editor.
- [ ] No `using WeChatWASM;` outside `Unity/Assets/Scripts/Core/Platform/`.
- [ ] WebGL smoke build succeeds with no link errors.
- [ ] Tuanjie SDK loaded under Unity 2021.3 confirmed by either successful
      smoke build OR documented user decision to switch engine/SDK.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Platform | Game must run on WeChat Mini Game (微信小游戏) | Provides the sanctioned path for gameplay code to invoke WeChat runtime services without coupling to SDK internals |

> Foundational — no GDD requirement. Enables: every gameplay/UI/audio feature
> that needs WeChat runtime services. Without this ADR, every feature would
> either couple to the `WeChatWASM` namespace or reinvent JS bridging.

## Follow-up Work

- **ADR-0003** currently references "`wx.loadSubpackage` routed through
  `WxBridge`"; update to "`WeChatWASM.WX.LoadSubpackage` wrapped by
  `CCGS.Core.Platform.Wx.LoadSubpackage`".
- **ADR-0006** currently references "`wx.createInnerAudioContext` via
  `WxBridge`"; update to wrap via `Wx` Facade.
- **`.claude/docs/technical-preferences.md` Forbidden Patterns**: add
  `using WeChatWASM;` outside `Unity/Assets/Scripts/Core/Platform/` to the
  forbidden list to enforce Facade discipline.
- **`Unity/ProjectSettings/README.md`**: portrait-mobile target (720×1280)
  is project default — update default canvas size and add safe-area
  guidance for iOS. (Tracked separately from this ADR.)

## Related

- ADR-0003 (asset loading via `Wx.LoadSubpackage` Facade method)
- ADR-0005 (`link.xml` — SDK ships its own; project-level entries only for
  project reflection use)
- ADR-0006 (long audio routed through `Wx` Facade)
- Tuanjie SDK: <https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk>
- SDK package location post-install:
  `Library/PackageCache/com.qq.weixin.minigame@<hash>/Runtime/`
- SDK assembly definition:
  `Library/PackageCache/com.qq.weixin.minigame@<hash>/Runtime/WxWasmSDKRuntime.asmdef`
