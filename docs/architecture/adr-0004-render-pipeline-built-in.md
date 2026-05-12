# ADR-0004: Render Pipeline — Built-in default, URP opt-in (Phase 2)

## Status

Proposed

## Date

2026-05-12

## Last Verified

2026-05-12

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity build pipeline)
- `unity-shader-specialist` (consulted on variant-count economics)

## Summary

For v1 the project ships on Unity's **Built-in Render Pipeline**: lower shader-variant
overhead, simpler 4 MB first-package compliance, and well-trodden on WebGL.
**URP is officially supported by WeChat on WebGL 2.0** and is documented as a
**Phase 2 opt-in path** with documented caveats (variant-budget, iOS WebGL 2.0
mode requirements, the known `Hidden/Universal/CoreBlit: invalid pass index 1`
shader workaround). HDRP is unsupported and forbidden.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Rendering |
| **Knowledge Risk** | MEDIUM — URP on WebGL 2.0 + WeChat is a niche combination; documented but evolving |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat URP customization guide ("定制微信小游戏的 URP 管线") |
| **Post-Cutoff APIs Used** | URP package patches for WebGL 2.0 compatibility |
| **Verification Required** | If switching to URP later: confirm the project's URP version is patched for the `Hidden/Universal/CoreBlit: invalid pass index 1` issue and that iOS 高性能+ mode (iOS ≥ 14) renders correctly. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (variant-budget feeds the first-package cap) |
| **Enables** | All shader work |
| **Blocks** | Adoption of URP-only features (Renderer Features, Forward+ many-light, Volume system) without re-opening this ADR |
| **Ordering Note** | Accept early. Re-open as a new ADR (e.g., ADR-0007) if/when Phase 2 URP migration is approved. |

## Context

### Problem Statement

Unity 2021.3 supports three render pipelines (Built-in, URP, HDRP). On the WeChat
WebGL 2.0 target:

- **HDRP**: unsupported (forbidden).
- **URP**: officially supported but has known WebGL-specific issues (`CoreBlit`
  shader workaround required) and inflates shader-variant counts in ways that eat
  the first-package budget.
- **Built-in**: well-supported on WebGL, smaller variant footprint, but lacks
  modern features (Forward+, Renderer Features, Volume-based post-processing).

A team that defaults to "URP because it's modern" without measuring will likely
exceed the 4 MB first-package cap on shader variants alone. A team that defaults
to "Built-in because it's safe" without considering URP forfeits the platform's
documented support for the better pipeline.

### Current State

Greenfield. No SRP asset configured.

### Constraints

- First-package shader-variant footprint contributes to the 4 MB cap (ADR-0002).
- iOS 高性能 mode (iOS ≥ 15) and 高性能+ mode (iOS ≥ 14) are required for WebGL 2.0
  rendering; high-perf mode has known compatibility gaps.
- Android WeChat ≥ 8.0.24 is required for WebGL 2.0 on Android.
- No compute shaders on WebGL 2.0.
- `Hidden/Universal/CoreBlit: invalid pass index 1 in DrawProcedural` is a known
  URP-on-WebGL issue; fix is upgrading URP or patching the local URP package.

### Requirements

- Render pipeline must compile successfully for WebGL 2.0.
- First-package shader-variant cost must stay within the share of the 4 MB cap
  allocated to shaders (suggested budget: ≤ 500 KB).
- Render pipeline must support standard mobile-feel features (lit/unlit, transparent,
  particle, simple post-FX).

## Decision

**Phase 1 (v1):** Built-in Render Pipeline. No SRP asset is configured. URP package
is **not** in `Packages/manifest.json`.

**Phase 2 (future opt-in):** URP may be adopted via a successor ADR (e.g., ADR-0007)
that documents:

1. Variant-budget measurement before and after URP adoption.
2. URP package version pinned to one that includes the `CoreBlit` fix or local
   patch instructions.
3. iOS 高性能+ mode (iOS ≥ 14) and 高性能 mode (iOS ≥ 15) rendering verified on
   target devices.
4. Built-in → URP migration plan including shader rewrites.

**HDRP:** Forbidden for the WebGL target. No exceptions.

### Architecture

```
Phase 1 (v1):
  Unity build → Built-in RP → standard WebGL 2.0 output → Tuanjie transform → WeChat

Phase 2 (opt-in, future):
  Decision in ADR-0007 (when written) →
    Unity build → URP (patched for CoreBlit) → WebGL 2.0 → Tuanjie transform → WeChat
```

### Key Interfaces

None at the code level — this is a project-settings decision.

```
Project Settings → Graphics → no SRP asset (Phase 1)
                              SRP asset reference (Phase 2 only)

Packages/manifest.json:
  Phase 1: no com.unity.render-pipelines.universal entry
  Phase 2: opt-in entry with pinned version
```

### Implementation Guidelines

- Phase 1: do not add `com.unity.render-pipelines.universal` to manifest; do not
  configure an SRP asset.
- All shaders use Built-in shader APIs (`Shader.Find("Standard")`, etc.).
- Custom shaders use `CGPROGRAM`/`HLSLPROGRAM` blocks targeting Built-in RP.
- Shader variant gating via `shader_feature` (stripped if unused) preferred over
  `multi_compile` (always included).
- Post-processing v2 package is acceptable for Built-in — Volume-based stack is
  URP-only and not used in Phase 1.

## Alternatives Considered

### Alternative 1: URP from day one

- **Description**: Add URP, configure SRP asset, write all shaders in Shader Graph.
- **Pros**: Modern pipeline, future-proof, better defaults.
- **Cons**: Variant inflation eats 4 MB cap; known `CoreBlit` issue requires
  patching; iOS WebGL 2.0 high-perf mode compat gaps add risk.
- **Rejection Reason**: Risk-to-reward is wrong for v1. URP is preserved as a
  Phase 2 path so the decision is reversible.

### Alternative 2: HDRP

- **Description**: Use HDRP for high-end fidelity.
- **Pros**: Best-looking pipeline.
- **Cons**: Unsupported on WebGL 2.0. Build won't even produce.
- **Rejection Reason**: Platform-incompatible.

### Alternative 3: Custom SRP

- **Description**: Write a project-specific Scriptable Render Pipeline.
- **Pros**: Surgical variant control.
- **Cons**: Massive engineering cost; sample-of-one with no community support.
- **Rejection Reason**: Cost wildly disproportionate to benefit.

## Consequences

### Positive

- Variant count stays manageable.
- First-package budget has shader-headroom.
- Built-in RP behavior is well-known to both LLM training data and the dev community.
- URP migration remains a clean opt-in via a successor ADR.

### Negative

- No Forward+ (relevant only for many-light scenes).
- No Renderer Features (limits custom render passes).
- Post-processing via the older Post-Processing v2 package, not the URP Volume stack.

### Neutral

- The `unity-shader-specialist` Version Awareness section tracks both pipelines.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| A future feature requires URP-only capability mid-Phase-1 | MEDIUM | MEDIUM | Open ADR-0007 to evaluate Phase 2 migration with measured variant-cost. |
| Built-in RP variant count still exceeds budget under heavy custom shader use | LOW | HIGH | Variant-count audit at every CI build; reject PRs that push past budget. |
| HDRP mistakenly added by a contributor | LOW | HIGH | CI grep gate forbidding `com.unity.render-pipelines.high-definition`. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time) | n/a | ≤ 33 ms (30 fps) | 33 ms |
| Memory | n/a | within 256 MB ceiling | 256 MB |
| Load Time | n/a | First-paint ≤ 3 s | ≤ 3 s |
| First-package shader-variant size | n/a | ≤ 500 KB | ≤ 500 KB (of 4 MB) |

## Migration Plan

Phase 1 is greenfield — no migration.

**If/when Phase 2 (URP) is adopted via ADR-0007:**

1. Measure current variant footprint (baseline).
2. Pin URP package to a version known to include the `CoreBlit` fix.
3. Add SRP asset, swap shaders incrementally, measure variant count after each swap.
4. Verify rendering on Android WeChat ≥ 8.0.24 and iOS 高性能 + 高性能+ modes.
5. If variant footprint exceeds budget, roll back via git revert.

**Rollback plan**: Remove `com.unity.render-pipelines.universal` from manifest,
clear SRP asset reference. Built-in RP resumes by default.

## Validation Criteria

- [ ] `Packages/manifest.json` does not contain `com.unity.render-pipelines.universal`.
- [ ] `Packages/manifest.json` does not contain `com.unity.render-pipelines.high-definition`.
- [ ] Project Settings → Graphics → SRP Asset is empty.
- [ ] First WebGL build succeeds with Built-in RP shaders only.
- [ ] Shader variant count log shows total < 500 KB contribution to first-package.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Rendering | Game must render correctly on WeChat WebGL 2.0 | Built-in RP is the lowest-risk path to a shippable render pipeline. |

> Foundational — no GDD requirement. Enables: all art and shader work. Future
> URP adoption (Phase 2) remains supported with documented caveats.

## Related

- ADR-0002 (first-package budget that the variant cost contributes to)
- ADR-0005 (Strip High interacts with shader-keyword reflection)
- Successor ADR-0007 (when written — URP Phase 2 opt-in)
- WeChat URP customization guide ("定制微信小游戏的 URP 管线")
