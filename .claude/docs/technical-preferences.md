# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Unity 2021.3 LTS (pinned: 2021.3.40f1 or later 2021.3.x).
  Note: WeChat's current SDK (`minigame-tuanjie-transform-sdk`) targets the
  Tuanjie 团结 engine; pure Unity 2021.3 compatibility is a known integration
  gap — see `docs/architecture/adr-0001-wx-sdk-adapter-layer.md`.
- **Language**: C# (.NET Standard 2.1, IL2CPP backend)
- **Rendering**: Built-in Render Pipeline (default — see ADR-0004). URP is
  supported by WeChat (WebGL 2.0) and may be adopted in Phase 2 with documented
  caveats.
- **Physics**: Unity 3D Physics (PhysX 4.1, Unity 2021 default). 2D-only
  projects can switch to Box2D and note in `CLAUDE.md`.

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: WeChat Mini Game (微信小游戏) via WebGL 2.0 only
- **Input Methods**: Touch
- **Primary Input**: Touch
- **Gamepad Support**: None
- **Touch Support**: Full
- **Platform Notes**:
  - Android: WeChat client ≥ 8.0.24 for WebGL 2.0
  - iOS: "高性能 mode" needs iOS ≥ 15; "高性能+ mode" needs iOS ≥ 14
  - iOS high-perf mode WebGL 2.0 has known compat gaps — verify per-feature
  - Embedded iOS host: respect safe area

## Naming Conventions

- **Classes**: PascalCase
- **Variables**: camelCase for locals and private fields; PascalCase for public properties
- **Signals/Events**: `On`-prefix + PascalCase (e.g., `OnPlayerDamaged`)
- **Files**: PascalCase matching the primary class name
- **Scenes/Prefabs**: PascalCase
- **Constants**: PascalCase `const` / `static readonly`

## Performance Budgets

- **Target Framerate**: 30 fps (60 fps only for low-asset games — verify on target devices)
- **Frame Budget**: 33 ms
- **Draw Calls**: <100 / frame
- **Memory Ceiling**: 256 MB
- **First Package**: ≤ 4 MB
- **Per-Subpackage**: ≤ 4 MB
- **Total Package**: ≤ 20 MB

## Testing

- **Framework**: Unity Test Framework (NUnit 3) — EditMode + PlayMode in
  `Unity/Assets/Tests/{EditMode,PlayMode}/` for in-engine tests;
  `tests/` for non-Unity integration / performance scripts.
- **Minimum Coverage**: 60% for `Scripts/Gameplay/` and `Scripts/Core/`
- **Required Tests**: Balance formulas (must have unit tests), gameplay systems,
  networking (if applicable)

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->

- `System.Reflection.Emit.*` (JIT blocked on WeChat)
- `Regex.Compile` / `RegexOptions.Compiled`
- LINQ in `Update` / `FixedUpdate` / `LateUpdate` (allocation pressure)
- `Resources.Load` and `Resources/` folder pattern (use SubPackages — ADR-0003)
- `UnityWebRequest` loading large files into memory in one shot
- `AssetBundle.LoadFromMemory`
- `async/await` on hot paths
- `Unity.Entities.*` / `Unity.Burst.*` / `Unity.Jobs.*` (DOTS — WebGL incomplete)
- `Addressables.*` catalog size must be monitored — if > 5 MB, switch to AssetBundle (ADR-0003)
- `using WeChatWASM;` **outside** `Unity/Assets/Scripts/Core/Platform/` — all
  gameplay code must call the `Wx` Facade (ADR-0001), never the SDK directly.

**NOT forbidden**: URP (see ADR-0004), `Unity.Mathematics` (works in WebGL).

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->

- `minigame-tuanjie-transform-sdk` — WeChat Mini Game build pipeline (post-install)
- `com.unity.textmeshpro` — text rendering
- `com.unity.ugui` — UGUI canvas-based UI
- Unity Test Framework — required for CI gates

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->

- ADR-0001 — WX-SDK Facade Layer (Accepted)
- ADR-0002 — First-package Budget ≤ 4 MB (Accepted)
- ADR-0003 — Asset Loading via WeChat SubPackages (Addressables Allowed, Resources Forbidden) (Accepted)
- ADR-0004 — Render Pipeline: Built-in default, URP opt-in (Accepted)
- ADR-0005 — IL2CPP Strip High + `link.xml` (Accepted)
- ADR-0006 — Audio Strategy: Unity AudioSource primary, SDK auto-adapts (Accepted)

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: `unity-specialist`
- **Language/Code Specialist**: `unity-specialist`
- **Shader Specialist**: `unity-shader-specialist`
- **UI Specialist**: `unity-ui-specialist`
- **Additional Specialists**: (none — see Routing Notes for forbidden ones)
- **Routing Notes**:
  - REFUSE to spawn `unity-dots-specialist` — DOTS/Burst on WebGL is incomplete.
  - `unity-addressables-specialist` may be consulted for Addressables-specific
    decisions, with the catalog-size caveat (see ADR-0003).

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| `*.cs` (game code) | `unity-specialist` |
| `*.shader` / `*.shadergraph` / `*.hlsl` / `*.cginc` / `*.mat` | `unity-shader-specialist` |
| `*.uxml` / `*.uss` / UGUI prefabs under `UI/` | `unity-ui-specialist` |
| `*.unity` / `*.prefab` (scenes/prefabs) | `unity-specialist` |
| `*.jslib` / `Assets/Plugins/WeChat/*` | `unity-specialist` (escalate to user decision) |
| General architecture review | `unity-specialist` |
