# ADR-0003: Asset Loading — Addressables or AssetBundle (Resources Forbidden)

## Status

Accepted

## Date

2026-05-12

## Last Verified

2026-05-14

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity build pipeline)
- `unity-specialist` (Unity build pipeline; `unity-addressables-specialist` was
  consulted during ADR drafting but has been removed from this target due to LLM
  training-data bias — see agent file)

## Summary

All non-bootstrap assets ship outside the first package. The WeChat Mini Game
SDK supports **three sanctioned loading mechanisms**: Addressables (AA),
AssetBundle (AB), and Instant Game. Unity's `Resources/` folder pattern remains
forbidden (it forces assets into the first package).

**Addressables is officially supported** by the WX SDK — the official WeChat
documentation has a dedicated `UsingAddressable.html` guide page, and the SDK's
file-cache system (ADR-0005 covers cache) explicitly handles Addressables bundle
requests. The official docs list Addressables as the **recommended default**
for most projects. For very large projects with thousands of Addressable keys,
the uncompressed `catalog.json` can become a bottleneck; at that scale,
AssetBundle is the advised alternative.

**Project-scale guidance (from official WeChat docs, ResourcesLoading.html):**

| Project Scale | Recommendation | Rationale |
|--------------|---------------|-----------|
| Most projects | **Addressables** | Easier workflow, well-documented, WX SDK auto-caches |
| Very large scale (thousands of keys) | **Evaluate AssetBundle** | Catalog may become a bottleneck; AB can improve loading performance |

The hard catalog-size gate remains at ~5 MB: measure on the first WebGL build
and decide before the project's asset count commits the team to one path.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Asset Pipeline / Content Delivery |
| **Knowledge Risk** | LOW — WX SDK asset-loading behavior is well-documented in the official WeChat docs |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat Mini Game Unity docs: `Guide.html` (quick-start), `ResourcesLoading.html` (方案选择), `UsingAddressable.html` (AA 指南), `UsingAssetBundle.html` (AB 指南), `FileCache.html` (缓存), `StartupOptimization.html` (启动优化), `DataCDN.html` (CDN 部署) |
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

2. **Recommend Addressables as the default**: `com.unity.addressables` is the
   preferred loading mechanism for most projects. The WX SDK officially supports
   Addressables (dedicated guide page: `UsingAddressable.html`). The SDK's
   file-cache system automatically handles Addressables bundles (detects
   `StreamingAssets/aa/WebGL/` paths, triggers auto-cache). Use AssetBundle only
   when profiling or the CI catalog-size gate indicates a bottleneck.

3. **AssetBundle as a scale optimization**: for projects where the
   Addressables catalog grows very large (thousands of keys), the official docs
   (`ResourcesLoading.html`) note that the uncompressed catalog can affect
   loading efficiency — "未压缩的 catalog 较大，加载效率低，改用 AB 包后效果提升明显."
   In those cases, direct `UnityWebRequestAssetBundle` loading may perform better.
   The WX SDK auto-caches downloaded bundles via `bundlePathIdentifier`
   (default `StreamingAssets`).

4. **Hard catalog-size gate at 5 MB**: on every CI WebGL build, measure
   `catalog.json` uncompressed size. If > 5 MB, evaluate AssetBundle as a
   performance optimization. This gate catches scale issues before the key
   count grows further.

5. **Instant Game is a known alternative**: the official docs list Unity's
   Instant Game as a third option (requires Unity 2021.2.5+, uses Tencent
   Cloud CDN). Not selected as the default because it locks the CDN choice
   and the engine version. Teams may opt into it as a faster conversion path
   for simple projects.

6. **First resource package deployment**: configured via `MiniGameConfig.asset`
   (`assetLoadType`: 0=CDN, 1=小游戏包内). CDN mode is default — no 20 MB
   ceiling on the first resource package, but affects startup time.

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

- **Most projects**: use Addressables as the default. Best Editor workflow,
  well-documented, officially supported by WX SDK. Measure catalog size on the
  first CI WebGL build; if > 5 MB, evaluate AssetBundle as an optimization.
- **Large-scale projects / thousands of keys**: AssetBundle may offer better
  loading performance. The official WeChat docs note that a very large catalog
  can become a bottleneck. Direct `UnityWebRequestAssetBundle` with
  `bundlePathIdentifier` (default `StreamingAssets`) triggers WX SDK auto-caching.
- **Unsure of scale**: use Addressables. Migrating to AssetBundle later is
  straightforward if the catalog grows; the CI gate catches size issues early.
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

- Addressables is the recommended default for most projects (best Editor
  workflow, officially supported by WX SDK).
- AssetBundle path documented as a scale optimization when the catalog grows.
- WX SDK auto-caching works for both paths — no custom caching layer needed.
- `Resources/` pattern blocked from day one.

### Negative

- Addressables → AssetBundle migration requires refactoring asset load calls.
  The CI catalog-size gate detects this need early to avoid mid-project surprises.
- Devs must understand three loading mechanisms (SubPackage, Addressables,
  AssetBundle) and when to use each.

### Neutral

- The `unity-addressables-specialist` agent was removed from this target (2026-05-14)
  due to LLM training-data bias that could not be overridden via prompt engineering.
  Addressables guidance is handled by `unity-specialist` (see ADR-0003).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Addressables catalog exceeds 5 MB and startup degrades | MEDIUM | MEDIUM | Measure catalog size on every CI build. Optimize with AssetBundle if the catalog stays above the gate. |
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

1. Start with Addressables (add `com.unity.addressables` to manifest).
2. Configure groups and build Addressables.
3. If the CI catalog-size gate later indicates a bottleneck, migrate to
   AssetBundle by configuring build scripts and setting `bundlePathIdentifier`
   in `MiniGameConfig.asset`.
4. Move MainMenu scene out of first package.
5. Loading scene loads first asset package, then MainMenu.
6. CI gates: no `Resources/` folder; catalog size ≤ 5 MB (Addressables path).

**Addressables → AssetBundle migration path**: if the catalog-size gate
indicates a bottleneck, refactor asset load calls from
`Addressables.LoadAssetAsync<T>` to `UnityWebRequestAssetBundle`. Addressables
groups map roughly to AssetBundle names.

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
- WeChat official docs: `ResourcesLoading.html` (方案选择), `UsingAddressable.html` (AA 指南), `UsingAssetBundle.html` (AB 指南), `FileCache.html` (缓存), `DataCDN.html` (CDN 部署), `InstantGameGuide.html` (Instant Game)
