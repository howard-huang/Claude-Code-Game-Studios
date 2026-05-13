# ADR-0003: Asset Loading via WeChat SubPackages (Addressables Allowed, Resources Forbidden)

## Status

Accepted

## Date

2026-05-12

## Last Verified

2026-05-13

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity build pipeline)
- `unity-addressables-specialist` (consulted on catalog-size constraints)

## Summary

All non-bootstrap assets ship outside the first package. The WeChat Mini Game
SDK supports **three sanctioned loading mechanisms**: SubPackage, CDN, and
AssetBundle/Addressables. Unity's `Resources/` folder pattern remains forbidden
(it forces assets into the first package). **Addressables is officially
supported** by the WX SDK, but carries a catalog-size caveat: for large games
the `catalog.json` can exceed 10 MB and slow startup. This ADR allows
Addressables for small-to-medium projects and recommends AssetBundle for
projects whose Addressables catalog would exceed ~5 MB.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Asset Pipeline / Content Delivery |
| **Knowledge Risk** | LOW — WX SDK asset-loading behavior is well-documented in the official WeChat docs |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat Mini Game Unity docs (`AssetDescription.html`, `StartupOptimization.html`, `DataCDN.html`, `FileCache.html`, `PerfOptimization.html`) |
| **Post-Cutoff APIs Used** | `wx.loadSubpackage` semantics under Tuanjie SDK |
| **Verification Required** | Measure Addressables catalog size on first WebGL build; if > 5 MB, switch to AssetBundle. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (the `Wx` Facade exposes `LoadSubpackage`), ADR-0002 (first-package budget) |
| **Enables** | All gameplay-content stories |
| **Blocks** | Nothing (Addressables is allowed; Resources is forbidden) |
| **Ordering Note** | Accept after ADR-0001 and ADR-0002. |

## Context

### Problem Statement

Unity's default workflow uses either `Resources.Load`, AssetBundles, or
Addressables. The WeChat Mini Game platform adds SubPackage and CDN as
platform-specific options. Without clear guidance, a team might:

- Use `Resources/` and blow the 4 MB first-package cap (ADR-0002).
- Choose Addressables for a large game and hit the catalog.json > 10 MB
  bottleneck documented in the WeChat performance optimization guide.
- Duplicate work across the platform's built-in caching system and a
  custom asset-loading layer.

### Current State

Greenfield.

### Constraints

- First package ≤ 4 MB (ADR-0002), total ≤ 20 MB.
- WeChat client caches downloaded assets automatically (LRU, 200 MB default,
  upgradeable to 1 GB).
- Cache is triggered for `UnityWebRequest`, `WWW`,
  `UnityWebRequestAssetBundle`, and Addressables.
- `Resources/` folder contents are baked into the first package.
- IL2CPP Strip High (ADR-0005) removes unused code paths.
- Single AssetBundle < 2 MB recommended; download concurrency ≤ 20.

### Requirements

- Every non-bootstrap asset ships outside the first package.
- Loading is asynchronous with success/error callbacks.
- Scene references resolve correctly after the asset package loads.

## Decision

1. **Forbid `Resources/` folder pattern**: no folder named `Resources` is
   permitted under `Unity/Assets/`. This is a hard rule — platform-incompatible
   with the 4 MB budget.
2. **Allow Addressables**: `com.unity.addressables` is permitted. The WX SDK's
   file-cache system explicitly handles Addressables bundles (detects
   `StreamingAssets/aa/WebGL/` paths, triggers auto-cache). Addressables is the
   recommended choice for small-to-medium projects where the catalog stays under
   ~5 MB.
3. **Fall back to AssetBundle when needed**: if the Addressables catalog exceeds
   ~5 MB (or the total `StreamingAssets/aa/` footprint approaches the 4 MB
   first-package limit), switch to direct AssetBundle loading. The WX SDK
   supports `UnityWebRequestAssetBundle` and auto-caches downloaded bundles.
4. **SubPackage / CDN for first resource package**: configured via
   `MiniGameConfig.asset` (`assetLoadType`: 0=CDN, 1=小游戏包内). CDN mode is
   default — no 20 MB ceiling on the first resource package, but affects startup
   time.

### Architecture

```
Build time:
  Option A (Addressables):
    Unity Addressables build → StreamingAssets/aa/WebGL/
                             → WX SDK auto-caches downloaded bundles
  Option B (AssetBundle):
    Unity AssetBundle build   → bundles with hash in filename
                             → WX SDK auto-caches via bundlePathIdentifier

Runtime:
  Bootstrap → Loading scene (in first package)
            → Wx.LoadSubpackage("subpackage_core", ...)  OR
            → Addressables.LoadAssetAsync<T>(key)         OR
            → UnityWebRequestAssetBundle.GetAssetBundle(url)
                 │
                 ▼
            → Asset is available; scene loads.
```

### Key Interfaces

```csharp
// Option 1: SubPackage (via Wx Facade)
Wx.LoadSubpackage("subpackage_core",
    onSuccess: () => SceneManager.LoadSceneAsync("MainMenu"),
    onError: msg => HandleError(msg)
);

// Option 2: Addressables (standard Unity API)
var handle = Addressables.LoadAssetAsync<GameObject>("MainMenu");
await handle.Task;

// Option 3: AssetBundle (standard Unity API)
var request = UnityWebRequestAssetBundle.GetAssetBundle(url);
await request.SendWebRequest();
var bundle = DownloadHandlerAssetBundle.GetContent(request);
```

### Implementation Guidelines

- **Small-to-medium project**: start with Addressables (best Editor workflow,
  well-documented, supported by WX SDK). If catalog grows past 5 MB, reassess.
- **Large project**: prefer AssetBundle loading directly. The WX SDK's
  `bundlePathIdentifier` (default `StreamingAssets`) auto-triggers caching for
  any URL containing that path segment.
- Do NOT cache `.json` catalog/config files — the `bundleExcludeExtensions`
  defaults to `.json` for this reason. On each new version, either change the
  CDN path or set `no-cache` HTTP headers.
- Single bundle ≤ 2 MB, concurrency ≤ 20 requests.
- Show download progress UI; the WX cache system is transparent but network
  still takes time.
- Never duplicate an asset across packages; route shared assets into a core
  package that is always-loaded.

## Alternatives Considered

### Alternative 1: Forbid Addressables (previous v1 position)

- **Description**: Reject Addressables on the belief that it conflicts with
  WeChat SubPackages.
- **Pros**: Simplifies the decision.
- **Cons**: Contradicts official WeChat documentation, which lists Addressables
  as a supported loading mechanism. The WX SDK's file-cache system explicitly
  handles Addressables paths. Removes the most Unity-idiomatic asset workflow.
- **Rejection Reason**: Official docs confirm support. The catalog-size caveat
  is real but manageable with a size gate.

### Alternative 2: `Resources.Load` / `Resources/` folder pattern

- **Description**: Drop assets in `Resources/` and load by string name.
- **Pros**: Trivial code path.
- **Cons**: Every byte ships in the first package. Blows the 4 MB cap.
- **Rejection Reason**: Budget-incompatible.

### Alternative 3: AssetBundle.LoadFromMemory

- **Description**: Build bundles manually, load via raw bytes.
- **Pros**: Full control.
- **Cons**: Duplicates the WX SDK's built-in caching; worse memory profile
  (bundle in managed memory then duplicated into Unity heap). Forbidden by
  technical-preferences.
- **Rejection Reason**: Memory-pressure on 256 MB ceiling.

## Consequences

### Positive

- Addressables is available for small-to-medium projects (best Editor workflow).
- AssetBundle path documented for large projects (no catalog bottleneck).
- WX SDK auto-caching works for both paths — no custom caching layer needed.
- `Resources/` pattern blocked from day one.

### Negative

- Addressables → AssetBundle migration mid-project is non-trivial (refactors
  all asset load calls). The catalog-size gate should trigger early.
- Devs must understand three loading mechanisms (SubPackage, Addressables,
  AssetBundle) and when to use each.

### Neutral

- The `unity-addressables-specialist` agent is no longer REFUSE — it can be
  consulted for Addressables-specific decisions with the catalog-size caveat.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Addressables catalog exceeds 5 MB and startup degrades | MEDIUM | MEDIUM | Measure catalog size on every CI build; fail if > 5 MB. Switch to AssetBundle if it stays high. |
| Someone adds a `Resources/` folder | MEDIUM | HIGH | CI grep gate fails the build if `Resources/` exists under `Unity/Assets/`. |
| Cross-package asset reference breaks at runtime | MEDIUM | HIGH | Asset-reference validator in CI walks package manifests. |
| Download fails on flaky network | HIGH | MEDIUM | Retry-with-backoff in the caller (gameplay layer); show retry UI. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (asset-load frame time) | n/a | < 1 ms per load call (download is async) | < 1 ms |
| Memory | n/a | ~ proportional to active assets (256 MB ceiling) | 256 MB total |
| Load Time (first scene) | n/a | First-paint ≤ 3 s; first MainMenu ≤ 6 s | ≤ 6 s |
| Network (per bundle) | n/a | ≤ 2 MB (single bundle recommendation) | 2 MB |
| Addressables catalog size | n/a | ≤ 5 MB (gate threshold) | ≤ 5 MB |

## Migration Plan

Greenfield. Implementation order:

1. Choose Addressables or AssetBundle based on projected content scale.
2. If Addressables: add `com.unity.addressables` to manifest, configure groups.
3. If AssetBundle: configure build scripts, set `bundlePathIdentifier` in
   `MiniGameConfig.asset`.
4. Move MainMenu scene out of first package.
5. Loading scene loads first asset package, then MainMenu.
6. CI gates: no `Resources/` folder; catalog size ≤ 5 MB (Addressables path).

**Rollback plan for Addressables→AssetBundle**: refactor asset load calls from
`Addressables.LoadAssetAsync<T>` to `UnityWebRequestAssetBundle`. Addressables
groups map roughly to AssetBundle names. Documented as a known migration path.

## Validation Criteria

- [ ] No `Resources/` folder exists under `Unity/Assets/`.
- [ ] First WebGL build produces loadable assets outside the first package.
- [ ] Editor playmode confirms assets load correctly via chosen mechanism.
- [ ] WebGL build on real WeChat client confirms assets load and cache.
- [ ] CI gate: `Resources/` folder → build fails.
- [ ] CI gate (Addressables path): catalog > 5 MB → build warns (not fails).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Asset Pipeline | Game must respect WeChat's first-package budget while shipping full content | Assets ship outside first package via sanctioned WeChat-compatible loading mechanisms. |

> Foundational — no GDD requirement. Enables: every content-bearing feature.

## Related

- ADR-0001 (the `Wx` Facade exposes `LoadSubpackage`)
- ADR-0002 (first-package budget)
- ADR-0006 (audio assets live in a subpackage)
- Forbidden patterns list in `.claude/docs/technical-preferences.md`
- WeChat official docs: AssetDescription, FileCache, DataCDN, PerfOptimization
