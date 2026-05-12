# Unity Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Unity 2021.3.40f1 (or later 2021.3.x LTS) |
| **Release Date** | November 2024 (2021.3.40f1 specifically; 2021.3 LTS series spans 2022–2025) |
| **Project Pinned** | 2026-05-12 |
| **Last Docs Verified** | 2026-05-12 |
| **LLM Knowledge Cutoff** | August 2025 |

## Knowledge Gap Warning

Unity 2021.3 LTS is **within** the LLM's training data — **LOW** risk for Unity
API knowledge gaps. The real risk on this template is **HIGH for the WeChat
transform toolchain**: `minigame-tuanjie-transform-sdk` targets the **Tuanjie 团结**
engine (Unity China's Unity-fork, Unity 2022 LTS base) and its compatibility with
**pure Unity 2021.3** is a known integration gap — see ADR-0001 under
`CCGS/Docs/architecture/`.

Always cross-reference this directory and the 6 WeChat ADRs before suggesting
Unity APIs or platform features for the WeChat Mini Game target.

> **Note**: This template intentionally pins to **Unity 2021.3 LTS**, not Unity 6.
> The WeChat ecosystem (Tuanjie SDK, public docs, third-party guides) is still
> centered on the 2021/2022 LTS series as of early 2026. If you upgrade to Unity 6
> later, re-validate every ADR and the Tuanjie SDK integration.

## Target Platform

| Field | Value |
|-------|-------|
| **Build Target** | WebGL 2.0 → WeChat Mini Game (微信小游戏) |
| **Scripting Backend** | IL2CPP only |
| **Managed Stripping Level** | High (ADR-0005) |
| **.NET API Compatibility** | .NET Standard 2.1 |
| **Render Pipeline** | Built-in default (ADR-0004); URP Phase 2 opt-in |
| **Color Space** | Linear |
| **Memory Ceiling** | 256 MB |
| **First-Package Limit** | 4 MB (ADR-0002) |
| **Per-Subpackage Limit** | 4 MB |
| **Total Package Limit** | 20 MB |
| **Target Framerate** | 30 fps (33 ms frame budget) |

## WeChat Client Requirements

| Platform | Minimum |
|----------|---------|
| Android WeChat client | ≥ 8.0.24 (required for WebGL 2.0 support) |
| iOS "高性能 mode" | iOS ≥ 15 |
| iOS "高性能+ mode" | iOS ≥ 14 |

iOS high-perf mode WebGL 2.0 has documented compatibility gaps — verify
per-feature during integration testing.

## Verified Sources

- Unity 2021.3 manual: <https://docs.unity3d.com/2021.3/Documentation/Manual/index.html>
- Tuanjie SDK (active repo, replaces trademark-blocked `minigame-unity-webgl-transform`):
  <https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk>
- WeChat Mini Game Unity WebGL Transform guide:
  <https://developers.weixin.qq.com/minigame/dev/guide/game-engine/unity-webgl-transform.html>
- IL2CPP documentation:
  <https://docs.unity3d.com/2021.3/Documentation/Manual/IL2CPP.html>
- WeChat URP customization guide ("定制微信小游戏的 URP 管线") on the
  developers.weixin.qq.com portal.

## Engine Specialists Routing

- **Primary**: `unity-specialist`
- **Shader**: `unity-shader-specialist`
- **UI**: `unity-ui-specialist`
- **REFUSE**: `unity-dots-specialist` (DOTS/Burst on WebGL is incomplete)
- **REFUSE for asset loading**: `unity-addressables-specialist` (conflicts with
  WeChat SubPackages — see ADR-0003)

## Known Post-Cutoff Items to Verify

Per the August 2025 LLM cutoff, verify before recommending:

| Surface | Risk | Reason |
|---------|------|--------|
| Tuanjie SDK API surface | HIGH | Tuanjie engine is a post-cutoff Unity China fork; APIs may diverge from public Unity 2021.3 documentation. |
| WeChat WebGL 2.0 compatibility per iOS minor version | MEDIUM | iOS WebView capabilities change quarterly. |
| URP package version on WebGL | MEDIUM | The `CoreBlit invalid pass index 1` shader workaround is URP-version-dependent. |
