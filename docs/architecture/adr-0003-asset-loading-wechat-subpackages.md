# ADR-0003: Asset Loading via WeChat SubPackages (Addressables Forbidden)

## Status

Proposed

## Date

2026-05-12

## Last Verified

2026-05-12

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity build pipeline)
- `unity-addressables-specialist` (consulted as negative specialist; recommendations rejected per platform)

## Summary

All non-bootstrap assets ship in named WeChat subpackages and load via
`wx.loadSubpackage()` routed through `WxBridge` (ADR-0001). Unity's
Addressables system is **forbidden** on this target — it claims ownership of
asset bundle layout in a way that conflicts with WeChat's subpackage system.
The legacy `Resources.Load` / `Resources/` folder pattern is **also forbidden**
because it forces assets into the first package and bypasses the budget gate.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Asset Pipeline / Content Delivery |
| **Knowledge Risk** | MEDIUM — `wx.loadSubpackage` is platform-level (post-cutoff for some semantics); Unity Addressables behavior is in training data |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat Mini Game docs |
| **Post-Cutoff APIs Used** | `wx.loadSubpackage` semantics under Tuanjie SDK |
| **Verification Required** | Confirm Tuanjie SDK exposes `wx.loadSubpackage` and that asset references inside a subpackage resolve correctly when loaded. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (WxBridge is the entry point for `wx.loadSubpackage`), ADR-0002 (first-package budget defines what goes where) |
| **Enables** | All gameplay-content stories |
| **Blocks** | Any story that proposes Addressables for asset loading |
| **Ordering Note** | Accept after ADR-0001 and ADR-0002. |

## Context

### Problem Statement

Unity's default workflow uses either `Resources.Load` (deprecated for new projects)
or Addressables (the modern, recommended path). Both are incompatible with the
WeChat Mini Game first-package budget:

- `Resources/` folder contents are baked into the first package — ignoring ADR-0002.
- Addressables generates its own bundle layout with its own dependency catalog,
  duplicating the work that `wx.loadSubpackage` does — and the two systems do not
  coordinate. Running both produces duplicated assets, broken references, or both.

### Current State

Greenfield.

### Constraints

- First package ≤ 4 MB (ADR-0002).
- Subpackage downloads happen at runtime via `wx.loadSubpackage("subpackage_name", callbacks)`.
- After `wx.loadSubpackage` succeeds, the assets in that subpackage are addressable
  via normal Unity APIs (`Resources.Load` would work but is forbidden per first-package
  rule; scene-embedded references work).
- IL2CPP Strip High removes unused code paths — anything loaded via reflection must
  be declared in `link.xml` (ADR-0005).

### Requirements

- Every non-bootstrap asset belongs to exactly one subpackage.
- Subpackage names are stable identifiers known at build time.
- Loading a subpackage is an asynchronous operation with success/error callbacks.
- Scene references inside a subpackage resolve cleanly after the subpackage loads.

## Decision

1. **Forbid Addressables**: `com.unity.addressables` is **not** in `Packages/manifest.json`.
2. **Forbid `Resources/` folder pattern**: no folder named `Resources` is permitted
   under `Unity/Assets/`.
3. **Adopt WeChat SubPackages** as the only sanctioned asset-loading mechanism.
4. Assets live in scene-graph references inside their subpackage; loading a
   subpackage = activating its scene/prefab references.
5. The `WxBridge.LoadSubpackage(name, onSuccess, onError)` method (ADR-0001) is
   the **only** path from managed code to `wx.loadSubpackage`.

### Architecture

```
Build time:
  Unity build pipeline → multiple AssetBundles, one per declared subpackage
                       → packaged into WeChat subpackage manifest

Runtime:
  Bootstrap → Loading scene (in first package)
            → WxBridge.LoadSubpackage("subpackage_core", onSuccess, onError)
                 │
                 ▼ (wx.loadSubpackage downloads + caches subpackage_core)
            → SceneManager.LoadSceneAsync("MainMenu")
                 │
                 ▼ (assets in subpackage_core are now resolvable)
            → MainMenu plays.

  Later (on demand):
            → WxBridge.LoadSubpackage("subpackage_levels_2", ...)
            → Level2 scene becomes loadable.
```

### Key Interfaces

```csharp
namespace CCGS.Core.Platform
{
    public static class WxBridge
    {
        public static void LoadSubpackage(string name, Action onSuccess, Action<string> onError);
    }
}

// Caller pattern:
WxBridge.LoadSubpackage(
    "subpackage_core",
    onSuccess: () => SceneManager.LoadSceneAsync("MainMenu"),
    onError: msg => UIErrorPopup.Show(msg)
);
```

### Implementation Guidelines

- Subpackage names are declared in `Unity/Assets/Plugins/WeChat/subpackages.json`.
- Each subpackage maps to a Unity scene + a prefab manifest.
- The Loading scene is the only thing in the first package that can call
  `WxBridge.LoadSubpackage` — gameplay code calls it only after Loading hands off.
- Show progress UI during subpackage download — `wx.loadSubpackage` returns a
  `loadTask` object whose `onProgressUpdate` exposes percent complete.
- Never duplicate an asset across subpackages; route shared assets into a
  `subpackage_core` that is always-loaded.

## Alternatives Considered

### Alternative 1: Use Unity Addressables

- **Description**: Adopt the recommended Unity asset-loading system.
- **Pros**: Mature, well-documented, mockable in Editor.
- **Cons**: Addressables generates its own asset bundle layout with its own
  catalog. WeChat subpackages are a separate, mutually-exclusive mechanism.
  Running both produces broken references or asset duplication.
- **Rejection Reason**: Platform-incompatible.

### Alternative 2: `Resources.Load` / `Resources/` folder pattern

- **Description**: Drop assets in `Resources/` and load by string name.
- **Pros**: Trivial code path.
- **Cons**: Every byte in `Resources/` ships in the first package. Blows the 4 MB cap.
- **Rejection Reason**: Platform-incompatible with budget.

### Alternative 3: AssetBundle.LoadFromMemory

- **Description**: Build asset bundles manually, load via raw bytes.
- **Pros**: Full control.
- **Cons**: Duplicates `wx.loadSubpackage`'s caching, has worse memory profile
  (loads bundle into managed memory then duplicates into Unity heap), and is
  forbidden by the technical-preferences "Forbidden Patterns" list.
- **Rejection Reason**: Memory-pressure on a 256 MB-ceiling platform.

## Consequences

### Positive

- Single, platform-native asset-loading model.
- First-package budget remains controllable.
- Subpackages are downloaded and cached by the WeChat client — no custom caching.

### Negative

- Unity Editor playmode cannot use `wx.loadSubpackage` — `WxBridge.Mock` returns
  immediately, all assets are assumed present. This means Editor playmode does
  not catch missing-asset errors that the WeChat client would catch.
- Devs must learn the subpackage model.

### Neutral

- The `Addressables` and `unity-addressables-specialist` agent become advisory-only
  on this template — flagged in the agent's frontmatter as REFUSE.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Someone adds `com.unity.addressables` to `manifest.json` | MEDIUM | HIGH | Add a CI grep gate that fails the build if the package appears. |
| Cross-subpackage asset reference breaks at runtime | MEDIUM | HIGH | Run an asset-reference validator in CI that walks subpackage manifests. |
| Subpackage download fails on flaky network | HIGH | MEDIUM | Mandatory retry-with-backoff in `WxBridge.LoadSubpackage`; show user retry UI. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (asset-load frame time) | n/a | < 1 ms per `LoadSubpackage` call (download is async) | < 1 ms |
| Memory | n/a | ~ proportional to active subpackages (256 MB ceiling) | 256 MB total |
| Load Time (first scene) | n/a | First-paint ≤ 3 s; first MainMenu ≤ 6 s | ≤ 6 s |
| Network (per subpackage) | n/a | ≤ 4 MB | 4 MB |

## Migration Plan

Greenfield. Implementation order:

1. Create `subpackages.json` with one named subpackage: `subpackage_core`.
2. Move the MainMenu scene into `subpackage_core`.
3. Implement `WxBridge.LoadSubpackage` (ADR-0001 dependency).
4. Loading scene calls `LoadSubpackage("subpackage_core")` then loads MainMenu.
5. CI grep gate: `manifest.json` must not contain `addressables`; tree must not
   contain a `Resources/` folder.

**Rollback plan**: Not rollback-able without changing platform.

## Validation Criteria

- [ ] `Packages/manifest.json` does not contain `com.unity.addressables`.
- [ ] No `Resources/` folder exists under `Unity/Assets/`.
- [ ] First WebGL build produces multiple `.wxpkg` (or equivalent) files matching
      `subpackages.json`.
- [ ] PlayMode test confirms `WxBridge.Mock.LoadSubpackage` calls `onSuccess`.
- [ ] WebGL build on real WeChat client confirms `LoadSubpackage` downloads and
      activates assets.
- [ ] CI grep gate fails when Addressables or `Resources/` are reintroduced (negative test).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Asset Pipeline | Game must respect WeChat's first-package budget while shipping full content | Subpackage model lets assets ship outside the first package without violating platform constraints. |

> Foundational — no GDD requirement. Enables: every content-bearing feature.
> Without this ADR, gameplay content cannot ship at all.

## Related

- ADR-0001 (WxBridge owns the bridge to `wx.loadSubpackage`)
- ADR-0002 (first-package budget that drives the need for subpackages)
- ADR-0006 (audio strategy uses a dedicated audio subpackage)
- Forbidden patterns list in `.claude/docs/technical-preferences.md`
