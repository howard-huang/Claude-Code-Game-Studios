# ADR-0002: First-package Budget ≤ 4 MB

## Status

Proposed

## Date

2026-05-12

## Last Verified

2026-05-12

## Decision Makers

- `technical-director` (budget authority)
- `unity-specialist` (Unity build pipeline)
- User (final sign-off; payload constraints are platform-immutable)

## Summary

WeChat Mini Game enforces a 4 MB hard cap on the first package downloaded at
game-launch, 4 MB per subpackage, and 20 MB total. This ADR makes those caps
binding for the project: the first package contains only bootstrap code, the
Loading scene, `WxBridge`, and the `link.xml` whitelist — every asset larger
than 1 KB ships in a named subpackage.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Core / Build Pipeline |
| **Knowledge Risk** | MEDIUM — WeChat platform limit verified per WeChat docs; build pipeline behavior depends on Tuanjie SDK |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat Mini Game docs |
| **Post-Cutoff APIs Used** | None (limit is platform-level, not engine-level) |
| **Verification Required** | Confirm 4 MB / 20 MB caps still current at first ship date — WeChat occasionally relaxes these limits for verified game developers. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0003 (subpackage strategy), ADR-0005 (Strip High justification) |
| **Blocks** | Any "ship a 10 MB texture in the first package" type request |
| **Ordering Note** | This ADR justifies several others — accept early. |

## Context

### Problem Statement

WeChat enforces a 4 MB cap on the first package the user downloads when
launching the mini-game. Without explicit budgeting, normal Unity workflows
(default texture compression, eager asset references, full managed assembly
deployment) will blow this cap on the very first build, and the game will be
**unshippable** on WeChat. The cost of finding this out at the end of
production rather than now is weeks of emergency asset re-routing.

### Current State

Greenfield. No baseline measurement exists.

### Constraints

- **First package: ≤ 4 MB** (hard, enforced by WeChat platform).
- **Per subpackage: ≤ 4 MB** (hard).
- **Total package: ≤ 20 MB** (hard; can request increase for verified developers).
- WeChat client launches the first package and downloads subpackages on demand.
- The bootstrap path **must** reach a playable Loading scene from the first package alone.
- IL2CPP managed code typically takes 3–8 MB unstripped — Strip High mandatory (ADR-0005).

### Requirements

- First package contains: WebGL bootstrap, `WxBridge`, Loading scene, IL2CPP managed
  code (stripped per ADR-0005), `link.xml` whitelist, minimum UI for the Loading screen.
- All gameplay scenes ship in subpackages.
- Every audio/texture/mesh asset > 1 KB ships in a subpackage.
- Total of all packages (first + subs) ≤ 20 MB.

## Decision

Adopt the following budget structure as a binding rule:

| Package | Cap | Contents |
|---------|-----|----------|
| First package | 4 MB | bootstrap, `WxBridge`, Loading scene, `link.xml`, stripped IL2CPP code |
| `subpackage_core` | 4 MB | core gameplay scenes + minimum-viable asset set |
| `subpackage_audio` | 4 MB | BGM + voice (loaded via `wx.createInnerAudioContext` — ADR-0006) |
| `subpackage_levels_1` | 4 MB | first wave of level content |
| `subpackage_levels_2` | 4 MB | second wave (or DLC) |
| **Total** | **≤ 20 MB** | — |

CI must enforce these caps — fail the build if any package exceeds its cap.

### Architecture

```
WeChat launch
     │
     ▼
First package (≤ 4 MB)
  ├── bootstrap
  ├── WxBridge
  ├── Loading scene
  └── link.xml-preserved IL2CPP code
         │
         ▼
   Loading.Awake() → WxBridge.LoadSubpackage("subpackage_core")
         │
         ▼
   subpackage_core (≤ 4 MB)
         │
         ▼
   MainMenu / Gameplay scenes
         │  (lazy-load other subpackages as needed)
         ▼
   subpackage_audio / subpackage_levels_*
```

### Key Interfaces

```csharp
// CI gate (build pipeline)
public static class PackageBudgetGate
{
    public const long FirstPackageMaxBytes = 4 * 1024 * 1024;
    public const long PerSubpackageMaxBytes = 4 * 1024 * 1024;
    public const long TotalMaxBytes = 20 * 1024 * 1024;

    public static void AssertWithinBudget(BuildReport report);
}
```

### Implementation Guidelines

- Any pull request that adds an asset > 1 KB must declare its target subpackage
  in the PR description.
- Run `PackageBudgetGate.AssertWithinBudget` as a post-build step.
- Profile package contents with WeChat Developer Tools' "包体分析" feature —
  put findings in a build-report comment.
- If a single subpackage is approaching 4 MB, split it before merging.

## Alternatives Considered

### Alternative 1: Optimistic budgeting, fix when it breaks

- **Description**: No explicit cap, react when WeChat refuses to upload the build.
- **Pros**: Zero upfront process cost.
- **Cons**: Emergency asset re-routing late in production is **the** classic mobile-
  game-shipping disaster. Sunk cost makes "just one more MB" arguments rational
  even when they aren't.
- **Rejection Reason**: Predictably catastrophic.

### Alternative 2: Single 20 MB package

- **Description**: Skip subpackages entirely.
- **Pros**: Simplest build pipeline.
- **Cons**: First-package cap is non-negotiable at 4 MB. This is impossible.
- **Rejection Reason**: Platform-forbidden.

## Consequences

### Positive

- Cost of an asset is visible at PR time, not at ship time.
- Forces correct subpackage architecture from day one.
- CI fails fast on budget regressions.

### Negative

- Every artist + audio dev must understand the subpackage model.
- Tools complexity: subpackage manifest + CI gate + WeChat pipeline integration.

### Neutral

- The 4 MB first-package cap is a Tetris game until it isn't. Plan for it.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| `link.xml` whitelist grows and pushes first package > 4 MB | MEDIUM | HIGH | Audit `link.xml` quarterly; reject any whitelist entry without a documented reflection-call justification. |
| CI gate is bypassed by an emergency override | MEDIUM | HIGH | Make `[budget-override]` PR tag explicitly require user sign-off; log every override. |
| WeChat raises the limit later and devs over-pack | LOW | MEDIUM | Re-baseline budgets in a follow-up ADR if WeChat publishes a relaxation. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time) | n/a | n/a | n/a |
| Memory | unknown | ~ 256 MB working set | 256 MB |
| Load Time | unknown | First-paint ≤ 3 s on Android WeChat ≥ 8.0.24 | ≤ 3 s |
| Network (initial download) | n/a | ≤ 4 MB first package | 4 MB |
| Network (total) | n/a | ≤ 20 MB sum | 20 MB |

## Migration Plan

Greenfield. Implementation order:

1. Document subpackage names in `Unity/Assets/Plugins/WeChat/subpackages.json`.
2. Add `PackageBudgetGate` to the build pipeline post-step.
3. First WebGL build verifies first-package size with empty Loading scene.
4. As features land, assets go into appropriately named subpackages.

**Rollback plan**: This decision cannot be rolled back without WeChat changing
the platform cap. Treat as load-bearing.

## Validation Criteria

- [ ] WebGL build first package ≤ 4 MB confirmed by `PackageBudgetGate`.
- [ ] Each subpackage ≤ 4 MB confirmed by `PackageBudgetGate`.
- [ ] Sum of all packages ≤ 20 MB.
- [ ] WeChat Developer Tools "包体分析" shows no surprise contents in first package.
- [ ] CI gate fails when an over-budget PR is opened (negative test).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Build / Distribution | Game must be installable on WeChat Mini Game | First-package + total caps are platform-immutable; this ADR makes them visible and enforced. |

> Foundational — no GDD requirement. Enables: every shippable build. Without
> this ADR, the game cannot be uploaded to WeChat.

## Related

- ADR-0003 (subpackage asset-loading strategy that allocates content to subpackages)
- ADR-0005 (Strip High is the only stripping level that keeps managed code in budget)
- ADR-0006 (audio routed to its own subpackage to keep first-package small)
