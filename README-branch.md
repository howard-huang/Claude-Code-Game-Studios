# `unity-2021-instant-game` — CCGS Template for Unity 2021 + WeChat Mini Game

This branch of [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)
is a **pre-baked Unity 2021.3 LTS template that ships to WeChat Mini Game**
(微信小游戏) via WebGL 2.0. Run `tools/install-template.ps1` to deploy it into
any project directory; you'll get a Unity project skeleton, the CCGS agent
framework, and six WeChat-specific architecture decisions ready to start coding
against.

---

## Quickstart

```powershell
# From a checkout of this branch:
pwsh .\tools\install-template.ps1 -TargetPath C:\projects\my-wx-game

# Optional flags:
#   -ProjectName "Pretty Name"   sets the H1 in the deployed CLAUDE.md
#   -Force                       allow deployment into a non-empty target
#   -Mode existing-unity         NOT IMPLEMENTED — coming later
```

After deployment, the target looks like this:

```
my-wx-game/
├── .claude/                 # 47 agents, 72 skills, 12 hooks (paths rewritten)
├── CLAUDE.md                # Project manifest (H1 rebranded to project name)
├── CCGS/                    # All framework-managed project content
│   ├── Design/{gdd,narrative,levels,balance,registry,concepts}/
│   ├── Docs/{architecture,engine-reference,api,postmortems}/
│   ├── Production/{session-state,sprints,milestones,releases,qa}/
│   ├── Prototypes/
│   ├── Tests/{unit,integration,performance,playtest}/
│   └── Tools/{ci,build,asset-pipeline}/
└── Unity/                   # Unity 2021.3 project root
    ├── Assets/Scripts/{Core,Gameplay,AI,UI,Networking,Data,Tools}/
    ├── Assets/{Art,Audio,Data,Shaders,VFX,Prefabs,Scenes}/
    ├── Assets/Plugins/WeChat/   (clone Tuanjie SDK here)
    ├── Assets/Tests/{EditMode,PlayMode}/  (NUnit asmdefs)
    ├── Packages/manifest.json
    └── ProjectSettings/{ProjectVersion.txt, README.md}
```

---

## What the installer does

1. Copies `.claude/` (framework files) to the target as-is.
2. Copies `CLAUDE.md`, rewrites its H1 to your project name.
3. Copies `Unity/` (the skeleton) to the target as-is.
4. Copies `docs/architecture/` (6 ADRs) to `CCGS/Docs/architecture/`.
5. Copies `docs/engine-reference/unity/` to `CCGS/Docs/engine-reference/unity/`.
6. Creates the `CCGS/` directory tree with `.gitkeep` markers.
7. **Rewrites paths inside `.claude/**` and `CLAUDE.md`** so framework
   references like `design/gdd/` become `CCGS/Design/gdd/` and `src/gameplay/`
   becomes `Unity/Assets/Scripts/Gameplay/`. The source repo keeps the
   engine-agnostic root paths — only the deployed copies are rewritten.
8. Prints a "Next Steps" block with the manual Player Settings checklist and
   the WeChat SDK clone URL.

**Out of scope:** the installer does NOT initialise git, does NOT install Unity,
does NOT install the Tuanjie SDK, and does NOT modify any binary
`ProjectSettings/*.asset` files. Unity regenerates those on first open.

---

## Architecture Decision Records (all `Proposed`)

The template ships six ADRs in `CCGS/Docs/architecture/`. Review and update
their Status from `Proposed` to `Accepted` (or rework them) before relying on
the template for production work.

| # | Title | Core decision |
|---|---|---|
| 0001 | WX-SDK Adapter Layer | All `wx.*` calls funnel through `WxBridge` (`Unity/Assets/Scripts/Core/Platform/WxBridge.cs`); `.jslib` at `Unity/Assets/Plugins/WeChat/`. |
| 0002 | First-package Budget ≤ 4 MB | Main package ≤ 4 MB, each subpackage ≤ 4 MB, total ≤ 20 MB. CI gate enforces. |
| 0003 | Asset Loading via WeChat SubPackages | Addressables forbidden; `Resources/` forbidden; only `wx.loadSubpackage` via `WxBridge`. |
| 0004 | Render Pipeline — Built-in default, URP opt-in | Phase 1 Built-in; URP is supported by WeChat (WebGL 2.0) but reserved for Phase 2 via a successor ADR. HDRP forbidden. |
| 0005 | IL2CPP Strip Level High + `link.xml` | Strip High is the only level that fits the 4 MB budget. Reflection-used types live in `Unity/Assets/link.xml`. |
| 0006 | Audio Strategy — long via `wx.createInnerAudioContext`, short via Unity AudioSource | > 3 s OR > 100 KB → native WeChat audio (memory cheap); shorter → Unity AudioSource (latency cheap). |

ADR-0001, 0003, and 0006 collectively require an actual `WxBridge.cs`
implementation. The ADRs define the API surface; you write the bridge against
the SDK version you ultimately use.

---

## Known caveats — read before your first build

### Tuanjie SDK ↔ pure Unity 2021.3 compatibility

The active WeChat Mini Game transform SDK is
[`wechat-miniprogram/minigame-tuanjie-transform-sdk`][sdk]. The SDK is built
for **Tuanjie 团结 engine** — Unity China's Unity-fork, with a Unity 2022 LTS
base. Compatibility with **pure Unity 2021.3 LTS** is a documented integration
gap. ADR-0001 captures this and recommends verifying before your first WebGL
build. If the SDK refuses to load on pure Unity 2021, you have two paths:

1. Switch the project to Tuanjie engine (the documented happy path).
2. Pin to an older `minigame-unity-webgl-transform` release that supported
   pure Unity 2021 (the older repo returns a GitHub trademark 404 at the time
   of writing — check git history or community mirrors).

[sdk]: https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk

### iOS WebGL 2.0 mode requirements

WeChat enforces a per-iOS-version rendering mode:

- **高性能 mode** requires iOS ≥ 15. Known to have WebGL 2.0 compatibility
  gaps for specific features — verify per-feature on a real device.
- **高性能+ mode** requires iOS ≥ 14. Better compatibility but narrower
  device coverage.

Plan your minimum-iOS commitment around this.

### Android WebGL 2.0 minimum

WeChat client ≥ 8.0.24 is required for WebGL 2.0 on Android. Older clients
fall back to WebGL 1.0, which the template does NOT support (Auto Graphics
API is OFF in the Player Settings checklist).

### URP `CoreBlit` shader workaround (Phase 2 only)

ADR-0004 keeps the template on Built-in RP for v1, but URP **is** supported
by WeChat. When you adopt URP via a successor ADR (e.g., ADR-0007), you'll
likely hit `Hidden/Universal/CoreBlit: invalid pass index 1 in DrawProcedural`.
Fix: upgrade URP to a version that includes the patch, or patch the local URP
package per WeChat's URP customization guide ("定制微信小游戏的 URP 管线").

---

## Verification

A clean end-to-end install should produce, in the target:

- `.claude/`, `CLAUDE.md`, `Unity/`, `CCGS/` all present at root.
- `CLAUDE.md` H1 mentions your project name; `Engine` line mentions Unity 2021.3.
- `.claude/docs/technical-preferences.md` is fully filled in (no `[TO BE
  CONFIGURED]` placeholders).
- `CCGS/Docs/architecture/adr-0001..0006-*.md` all present.
- `Unity/Packages/manifest.json` does NOT contain `addressables`, `entities`,
  or `render-pipelines.universal`.
- Spot-check rewrites: any `.claude/**/*.md` file referencing `design/gdd/`
  now reads `CCGS/Design/gdd/`; references to `src/gameplay/` now read
  `Unity/Assets/Scripts/Gameplay/`.

Then:

- Unity Hub opens `Unity/` and recognises 2021.3.40f1.
- Test Runner shows EditMode and PlayMode tabs.
- Claude Code launches from the project root and `session-start` reports no
  active sprint.

---

## Source-repo layout vs deployed layout

The source repo (this branch) keeps the engine-agnostic root paths:

| Source repo | Deployed target |
|---|---|
| `design/` (engine-agnostic) | `CCGS/Design/` |
| `docs/` (engine-agnostic) | `CCGS/Docs/` |
| `production/` (engine-agnostic) | `CCGS/Production/` |
| `tests/` (engine-agnostic) | `CCGS/Tests/` |
| `tools/` (engine-agnostic) | `CCGS/Tools/` (installer rewrites references) |
| `prototypes/` (engine-agnostic) | `CCGS/Prototypes/` |
| `src/` (not present in source) | `Unity/Assets/Scripts/` |
| `assets/` (not present in source) | `Unity/Assets/` |
| `.claude/` | `.claude/` (paths rewritten in-place) |
| `CLAUDE.md` | `CLAUDE.md` (H1 rewritten, references rewritten) |
| `Unity/` | `Unity/` (copied verbatim) |
| `tools/install-template.ps1` | (not copied — installer is source-only) |

This split lets the main-line CCGS framework remain engine-agnostic while the
deployed template gets a Unity-specific shape.

---

## License & feedback

This template lives on the `unity-2021-instant-game` branch of the parent CCGS
project. File issues or PRs against the parent repo. The 6 ADRs are starting
points — your project's actual decisions belong in a fresh ADR series in your
deployed `CCGS/Docs/architecture/`.
