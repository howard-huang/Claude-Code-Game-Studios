# ADR-0005: IL2CPP Strip Level High + link.xml

## Status

Accepted

## Date

2026-05-12

## Last Verified

2026-05-12

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity build pipeline)

## Summary

The Unity Player Settings managed-code stripping level is fixed at **High**.
Without it, the IL2CPP-compiled managed assemblies blow the 4 MB first-package
budget (ADR-0002). The Tuanjie SDK ships its own `link.xml` at
`Library/PackageCache/com.qq.weixin.minigame@*/Runtime/Plugins/link.xml`, so
the SDK's reflection-used types are already preserved. A project-local
`Unity/Assets/link.xml` whitelist preserves **project** types reached via
reflection (JsonUtility/serialization targets, `[CreateAssetMenu]`
ScriptableObjects loaded by name, attribute-scanned MonoBehaviour subclasses,
etc.). The `Wx` Facade (ADR-0001) does not need a `link.xml` entry — it is
called directly by gameplay code and the static analyzer sees the references.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Build / IL2CPP |
| **Knowledge Risk** | LOW — IL2CPP Strip High behavior is well-documented and in training data |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, Unity IL2CPP documentation |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | After adding a new third-party library, verify Strip High does not remove the library's reflection-used types (run the suspect feature in a WebGL build, not Editor). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (first-package budget is the *reason* Strip High is mandatory) |
| **Enables** | A build that fits in 4 MB |
| **Blocks** | Anything that depends on JIT, runtime IL emission, or unreflected reflection (forbidden patterns) |
| **Ordering Note** | Accept together with ADR-0002. |

## Context

### Problem Statement

IL2CPP compiles managed assemblies into C++ that is then compiled to WebAssembly.
With no stripping, the full assembly surface (including unused mscorlib/UnityEngine
types) ships — typically 6–10 MB of code, eating most of the 4 MB cap on its own.
With Strip High, unused types are removed and managed-code contribution to the
first package drops to roughly 1–2 MB.

**But** Strip High is unsafe by default: anything reached only by reflection
(`Type.GetType`, `JsonUtility.FromJson`, attribute scans, `Activator.CreateInstance`)
appears unused to the static analyzer and gets stripped, causing runtime
`MissingMethodException` or similar.

`link.xml` is the standard escape valve: a whitelist of types/assemblies that
the stripper must preserve.

### Current State

Greenfield. No `link.xml` yet.

### Constraints

- 4 MB first-package cap (ADR-0002).
- Forbidden: `System.Reflection.Emit.*`, `Regex.Compile`, JIT-dependent patterns.
- `JsonUtility` works under Strip High *if* the target type is whitelisted.
- `[Preserve]` attribute works as an alternative to `link.xml` for project code,
  but does **not** help for third-party assembly types.

### Requirements

- Stripping Level = **High** in Player Settings.
- `Unity/Assets/link.xml` whitelist exists and is reviewed quarterly.
- Every `link.xml` entry has a one-line comment explaining the reflection use case.

## Decision

Configure:

- **Player Settings → Other Settings → Managed Stripping Level = High**
- **Player Settings → Other Settings → Scripting Backend = IL2CPP**
- **Player Settings → Other Settings → Api Compatibility Level = .NET Standard 2.1**

Maintain `Unity/Assets/link.xml` as the whitelist for reflection-used types.

### Architecture

```
Source code
    │
    ▼
Roslyn compile → managed assemblies
    │
    ▼
IL2CPP + Strip High (uses link.xml whitelist)
    │
    ▼
WebAssembly (managed contribution to first package: 1–2 MB)
```

### Key Interfaces

`Unity/Assets/link.xml` skeleton:

```xml
<linker>
  <!-- The Tuanjie SDK's own link.xml lives at                                -->
  <!-- Library/PackageCache/com.qq.weixin.minigame@*/Runtime/Plugins/link.xml -->
  <!-- and is preserved automatically. This file is for PROJECT reflection    -->
  <!-- targets only.                                                          -->

  <!-- JsonUtility / save-data targets — add each serializable class explicitly -->
  <!-- (example placeholder; add real types as features land)                   -->
  <!--
  <assembly fullname="Assembly-CSharp">
    <type fullname="CCGS.Gameplay.SaveData" preserve="all"/>
  </assembly>
  -->

  <!-- ScriptableObjects loaded by reflection (e.g., AudioStreamReference per ADR-0006) -->
  <!--
  <assembly fullname="Assembly-CSharp">
    <type fullname="CCGS.Core.Audio.AudioStreamReference" preserve="all"/>
  </assembly>
  -->

  <!-- Unity modules that get over-stripped on WebGL — add only if a -->
  <!-- runtime exception proves the need.                            -->
</linker>
```

### Implementation Guidelines

- Adding a new entry to `link.xml` requires:
  1. A failing test/repro showing the runtime error caused by stripping.
  2. A comment explaining *which reflection path* would otherwise fail.
  3. The narrowest entry that fixes the issue (`preserve="all"` only when needed;
     prefer per-member preservation when possible).
- Code-side: use `[Preserve]` (from `UnityEngine.Scripting`) on types/members in
  project code as a `link.xml`-free alternative. Reserve `link.xml` for third-party
  or framework types.
- Run a WebGL build (not just Editor) after every new serialization/reflection
  addition. Editor playmode hides stripping bugs.
- CI logs the IL2CPP-stage code-size summary; flag any > 2.5 MB managed contribution
  as a regression.

## Alternatives Considered

### Alternative 1: Stripping Level = Low

- **Description**: Default. Strips only the most obviously unused types.
- **Pros**: Almost no `link.xml` needed.
- **Cons**: Managed code typically lands at 4–6 MB — single-handedly blows the
  first-package cap.
- **Rejection Reason**: Budget-incompatible.

### Alternative 2: Stripping Level = Medium

- **Description**: Middle ground.
- **Pros**: Fewer `link.xml` entries than High.
- **Cons**: Managed contribution typically lands at 2–4 MB. **Possibly** fits, but
  leaves no headroom for other first-package contents (bootstrap, Loading scene,
  the `Wx` Facade + stripped Tuanjie SDK assemblies). Risky.
- **Rejection Reason**: Wrong side of the budget cliff.

### Alternative 3: Strip High + heavy use of `[Preserve]` instead of `link.xml`

- **Description**: Annotate every reflectable type with `[Preserve]`.
- **Pros**: No XML file.
- **Cons**: Doesn't work for third-party assemblies (no source access).
- **Rejection Reason**: Incomplete coverage. Use both — `[Preserve]` for project
  code, `link.xml` for the rest.

## Consequences

### Positive

- Managed code fits in budget.
- One place (`link.xml`) audits all reflection use cases.
- Forces discipline around reflection — devs think before using it.

### Negative

- Stripping bugs are a runtime-only error. Editor passes; WebGL fails. Hard to
  catch in CI without a WebGL smoke test.
- Adding third-party libraries requires extra integration testing.

### Neutral

- The forbidden-patterns list (no `System.Reflection.Emit`, no `Regex.Compile`,
  no `async/await` on hot paths) interacts with Strip High but is its own concern.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Stripping bug reaches production undetected | MEDIUM | HIGH | Mandatory WebGL smoke test before each release; cover every gameplay feature in playtest. |
| `link.xml` grows unbounded as devs whitelist defensively | MEDIUM | MEDIUM | Quarterly audit; reject entries without justification comment. |
| Third-party library breaks under Strip High | MEDIUM | HIGH | Add libraries via ADR — each new dependency considers Strip High in its evaluation. |

## Performance Implications

| Metric | Before (Strip Low) | Expected After (Strip High) | Budget |
|--------|--------------------|-----------------------------|--------|
| First-package managed-code size | ~6 MB | ~1.5 MB | ≤ 2 MB |
| Build time | baseline | +20–30% (IL2CPP analysis cost) | acceptable |
| Runtime CPU | identical | identical | n/a |
| Memory | slightly lower | slightly lower (less code loaded) | within 256 MB |

## Migration Plan

Greenfield. Implementation order:

1. Set Player Settings as listed in Decision.
2. Create empty `Unity/Assets/link.xml` with project reflection entries (start
   with no entries; add as features land). The Tuanjie SDK's own `link.xml`
   under `Library/PackageCache/com.qq.weixin.minigame@*/Runtime/Plugins/` covers
   the SDK side automatically.
3. First WebGL build verifies managed-code size.
4. Add reflection-using libraries one at a time; each addition runs a WebGL smoke test.

**Rollback plan**: Lower Strip Level via Player Settings if a release-blocker
stripping bug is found and cannot be fixed via `link.xml` in time. Document the
incident as a Risk for re-baselining ADR-0002.

## Validation Criteria

- [ ] Player Settings → Managed Stripping Level = High (confirmed via `ProjectSettings/ProjectSettings.asset` inspection).
- [ ] `Unity/Assets/link.xml` exists (may be empty until reflection use cases land).
- [ ] Tuanjie SDK's bundled `link.xml` is auto-included by Unity (verify via
      Player log on first WebGL build: search for `Library/PackageCache/com.qq.weixin.minigame@*/Runtime/Plugins/link.xml`).
- [ ] First WebGL build managed-code contribution ≤ 2 MB.
- [ ] PlayMode smoke test exercises every reflection-using code path.
- [ ] WebGL build of the same smoke test passes (catches stripping bugs Editor misses).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Build / IL2CPP | Managed code must fit in 4 MB first-package cap | Strip High is the only stripping level that reliably achieves this. |

> Foundational — no GDD requirement. Enables: every shippable build. Without
> Strip High, the project cannot fit in WeChat's first-package limit.

## Related

- ADR-0002 (first-package budget that drives the need for High)
- ADR-0001 (the `Wx` Facade calls the Tuanjie SDK; SDK ships its own `link.xml`)
- Forbidden patterns list in `.claude/docs/technical-preferences.md` (JIT, reflection-emit)
