# ADR-0001: WX-SDK Adapter Layer

## Status

Proposed

## Date

2026-05-12

## Last Verified

2026-05-12

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (engine integration)
- User (final sign-off on Tuanjie SDK ↔ Unity 2021.3 compatibility)

## Summary

All WeChat JavaScript bridge calls (`wx.*`) must go through a single adapter class
`WxBridge` rather than being scattered across the codebase. This makes the
WeChat runtime mockable in the Unity Editor, isolates Tuanjie SDK churn behind a
stable interface, and provides one place to verify Tuanjie ↔ Unity 2021.3
compatibility.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Core / Platform Integration |
| **Knowledge Risk** | HIGH — Tuanjie SDK targets the Tuanjie 团结 engine fork; pure Unity 2021.3 support is unverified |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, `minigame-tuanjie-transform-sdk` repo |
| **Post-Cutoff APIs Used** | Tuanjie SDK `wx.*` exports (entire surface post-cutoff) |
| **Verification Required** | Tuanjie SDK loads, links, and runs on pure Unity 2021.3.40f1 + IL2CPP + WebGL build. If it does not, user must choose: (a) migrate to Tuanjie engine, or (b) pin to an older WX-SDK that supported Unity 2021. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0003 (`wx.loadSubpackage` routed through `WxBridge`), ADR-0006 (`wx.createInnerAudioContext` routed through `WxBridge`) |
| **Blocks** | Any story that calls `wx.*` directly from gameplay code |
| **Ordering Note** | This ADR must be Accepted before any subpackage or platform-audio story can start. |

## Context

### Problem Statement

WeChat Mini Game exposes a JavaScript API surface (`wx.loadSubpackage`,
`wx.createInnerAudioContext`, `wx.getSystemInfoSync`, `wx.login`, etc.) that
Unity code reaches via `.jslib` files and `[DllImport("__Internal")]` static
extern methods. Without an adapter layer, every system that needs the WeChat
runtime ends up with its own copy of `.jslib` glue, scattered `extern` decls,
and no mock path for Editor playmode — meaning **the game cannot be debugged
in the Unity Editor at all**.

### Current State

Nothing exists yet — this is a greenfield template.

### Constraints

- WeChat Mini Game requires `.jslib` for any `wx.*` call from managed code.
- `[DllImport("__Internal")]` in Unity WebGL maps to `.jslib` exports at link time.
- Editor builds have no WebGL runtime — calls to `wx.*` would crash without mocks.
- The Tuanjie SDK is the only currently supported transform — but it targets
  Tuanjie engine (Unity China fork, Unity 2022 LTS base). Pure Unity 2021.3 support
  is **unverified**.
- IL2CPP Strip High (ADR-0005) requires reflection-used types in `link.xml`.

### Requirements

- Exactly one file owns all `[DllImport("__Internal")]` declarations for `wx.*`.
- Every `wx.*` call has an Editor mock that returns a sensible default or logs a stub.
- The adapter layer must not allocate on hot paths (no per-call boxing).
- A single integration test in PlayMode verifies the mock path; a single manual
  smoke test on a real WeChat client verifies the bridged path.

## Decision

Create `Unity/Assets/Scripts/Core/Platform/WxBridge.cs` as a `static class`
that wraps all `wx.*` calls. The class has:

1. `[DllImport("__Internal")]` extern declarations conditionally compiled with
   `#if UNITY_WEBGL && !UNITY_EDITOR`.
2. Public static methods (the **only** API gameplay code uses) that branch to
   either the bridged or mock implementation based on `Application.platform`.
3. A `WxBridge.Mock` static subclass for Editor stubs.

### Architecture

```
Gameplay code
     │
     ▼
WxBridge (static class — single entry point)
     │
     ├─ UNITY_WEBGL && !UNITY_EDITOR ─→ DllImport extern ──→ Plugins/WeChat/WxBridge.jslib ──→ wx.*
     │
     └─ Editor / Standalone           ─→ WxBridge.Mock (returns defaults, logs stubs)
```

### Key Interfaces

```csharp
namespace CCGS.Core.Platform
{
    public static class WxBridge
    {
        public static bool IsWeChatRuntime { get; }

        public static void LoadSubpackage(string name, Action onSuccess, Action<string> onError);
        public static void PlayInnerAudio(string url, bool loop);
        public static SystemInfo GetSystemInfo();
        public static void Login(Action<string> onCode, Action<string> onError);
        // ... one method per wx.* the game uses
    }
}
```

```javascript
// Unity/Assets/Plugins/WeChat/WxBridge.jslib
mergeInto(LibraryManager.library, {
  WxBridge_LoadSubpackage: function(namePtr, onSuccessCb, onErrorCb) { /* ... */ },
  WxBridge_PlayInnerAudio: function(urlPtr, loop) { /* ... */ },
  // ... one entry per WxBridge public method
});
```

### Implementation Guidelines

- Strings cross the managed/native boundary via UTF-8 pointer marshalling. Cache
  marshalled strings — do not allocate per call.
- Callbacks from `.jslib` to managed code go through `[MonoPInvokeCallback]`
  static functions registered with `GCHandle`.
- Every public method has a default mock implementation that **does not throw**
  in Editor — return a sensible default or log `[WxBridge.Mock] <method>(args)`.
- Mock implementations must be marked with `[Conditional("UNITY_EDITOR")]` where
  possible to strip from WebGL builds.

## Alternatives Considered

### Alternative 1: Scattered `[DllImport]` per system

- **Description**: Each system that needs `wx.*` declares its own externs.
- **Pros**: No central file dependency; teams can move independently.
- **Cons**: No mock path; Editor playmode broken; Tuanjie SDK upgrade requires
  edits in every system; reflection-strip rules duplicated in N places.
- **Estimated Effort**: Lower upfront, much higher long-term.
- **Rejection Reason**: Makes Editor debugging impossible — non-negotiable.

### Alternative 2: Embed Tuanjie SDK calls as-is, no adapter

- **Description**: Use the SDK's provided C# wrappers directly from gameplay code.
- **Pros**: Zero adapter maintenance.
- **Cons**: Tuanjie SDK targets Tuanjie engine — wrappers may not exist or may
  fail to compile on pure Unity 2021.3. Couples gameplay to a specific SDK version.
- **Rejection Reason**: We have not yet verified Tuanjie SDK loads on pure Unity
  2021. The adapter layer gives us a single chokepoint to swap if compatibility fails.

## Consequences

### Positive

- Editor playmode works (huge for iteration speed).
- Tuanjie SDK churn is contained to one file.
- IL2CPP `link.xml` whitelist is short and centralized (ADR-0005).
- Future SDK migration (Tuanjie → some-other-WX-SDK) is a one-file change.

### Negative

- Every new `wx.*` call requires a `WxBridge` method + a `.jslib` entry + a mock.
- Slight per-call indirection cost (negligible; mostly inlined by IL2CPP).

### Neutral

- All platform code clusters in `Unity/Assets/Scripts/Core/Platform/`.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Tuanjie SDK refuses to load on pure Unity 2021.3 | HIGH | BLOCKING | Verify before first integration. If it fails, user decides: switch to Tuanjie engine, or pin to an older WX-SDK that supported Unity 2021. |
| `.jslib` link errors on first build | MEDIUM | HIGH | Add a CI smoke build immediately after WxBridge lands. |
| Mock implementations diverge from real behavior | MEDIUM | MEDIUM | Each mock has a `// TODO: matches behavior of wx.<method>` comment; cross-check during integration playtests. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time per wx.* call) | n/a | < 0.05 ms | Negligible |
| Memory | n/a | ~ 4 KB code + per-call P/Invoke marshal buffer | < 100 KB |
| Load Time | n/a | n/a | n/a |
| Network | n/a | n/a | n/a |

## Migration Plan

This is a greenfield decision — no migration. Implementation order:

1. Create `WxBridge.cs` with `IsWeChatRuntime` property + 1 stub method.
2. Create `WxBridge.jslib` with the matching 1 stub entry.
3. Write PlayMode test verifying the mock path returns sensibly.
4. **Run a smoke WebGL build to verify Tuanjie SDK + `.jslib` link.**
5. If smoke build fails, escalate to user to resolve compatibility per the Verification Required field.
6. Once green, add real `wx.*` methods one at a time as features need them.

**Rollback plan**: revert the file; the adapter is the only consumer of the
`.jslib` so nothing else depends on it yet.

## Validation Criteria

- [ ] `WxBridge.cs` exists at `Unity/Assets/Scripts/Core/Platform/WxBridge.cs`.
- [ ] `WxBridge.jslib` exists at `Unity/Assets/Plugins/WeChat/WxBridge.jslib`.
- [ ] No `[DllImport("__Internal")]` for `wx.*` exists outside `WxBridge.cs`.
- [ ] PlayMode test "WxBridge_Mock_ReturnsDefaults" passes in Editor.
- [ ] WebGL smoke build succeeds with no link errors.
- [ ] Tuanjie SDK loaded under Unity 2021.3 confirmed by either successful smoke
      build OR documented user decision to switch engine/SDK.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Platform | Game must run on WeChat Mini Game (微信小游戏) | Provides the only sanctioned path for managed code to invoke `wx.*` |

> Foundational — no GDD requirement. Enables: every gameplay/UI/audio feature
> that needs WeChat runtime services. Without this ADR, no system that depends
> on `wx.*` (subpackages, login, audio, system info, share, payment) can ship.

## Related

- ADR-0003 (asset loading via `wx.loadSubpackage`)
- ADR-0005 (`link.xml` whitelist for IL2CPP Strip High includes `WxBridge` PInvoke types)
- ADR-0006 (long audio routed through `wx.createInnerAudioContext` via `WxBridge`)
- Tuanjie SDK: <https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk>
