# ADR-0006: Audio Strategy — Unity AudioSource primary, SDK auto-adapts

## Status

Accepted

## Date

2026-05-12

## Last Verified

2026-05-13

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity audio integration)
- `audio-director` (sonic palette + memory budget)

## Summary

WeChat's Unity SDK plugin **automatically adapts Unity AudioSource** for the
Mini Game runtime — `AudioSource.PlayOneShot` / `AudioSource.Play` are the
**primary recommended path**. The SDK plugin automatically selects the
appropriate underlying WeChat audio API based on audio file size:

- **Long audio** (large file size) → `wx.createInnerAudioContext` (native
  decode + streaming, no Unity heap cost)
- **Short audio** (small file size) → `wx.createWebAudioContext` (fast decode,
  low latency)

This ADR mandates **Unity AudioSource as the default audio API** and defers to
the SDK's automatic adaptation. The `Wx` Facade (ADR-0001) exposes only
supplementary audio APIs (`PreDownloadAudios` for pre-caching) — it does NOT
wrap `wx.createInnerAudioContext` for playback, because the SDK already handles
that routing transparently.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Audio |
| **Knowledge Risk** | LOW — Unity AudioSource auto-adaptation is the official documented path |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat Mini Game audio docs (`AudioAndVideo.html`) |
| **Post-Cutoff APIs Used** | `wx.createInnerAudioContext` (called by SDK internally, not by project code) |
| **Verification Required** | Measure audio memory on real WeChat client to confirm the SDK correctly routes long BGM via innerAudioContext. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (the `Wx` Facade exposes `PreDownloadAudios`), ADR-0003 (audio assets live in a subpackage) |
| **Enables** | Any audio-bearing feature |
| **Blocks** | Nothing |
| **Ordering Note** | Accept after ADR-0001 and ADR-0003. |

## Context

### Problem Statement

Unity's `AudioSource` loads the entire decoded PCM into memory. A 60-second
BGM at 44.1 kHz / 16-bit stereo is roughly 10 MB of PCM — 4% of the 256 MB
ceiling for one track. Mobile WebGL also has slow PCM decode for compressed
formats.

The previous version of this ADR proposed manually routing long audio through
`wx.createInnerAudioContext` via the `Wx` Facade. **The official WeChat
documentation makes this unnecessary**: the SDK plugin already auto-adapts
Unity AudioSource, automatically choosing `innerAudioContext` for long audio
and `WebAudio` for short audio.

### Current State

Greenfield.

### Constraints

- 256 MB memory ceiling (target ≤ 32 MB for active audio at any time).
- 4 MB first-package, 4 MB per subpackage — audio assets ship in
  `subpackage_audio` (ADR-0003).
- Recommended audio format: mp3 or aac (best dual-platform compatibility).
- Known issues: iOS 17.5+ background audio stops on background (being fixed);
  Android loop playback issues fixed in client 8.0.51; too many simultaneous
  playback instances causes lag.
- WX SDK provides `WX.PreDownloadAudios` for audio pre-download.

### Requirements

- BGM and voice play without consuming excessive Unity heap.
- SFX play with snappy latency.
- Audio assets respect the first-package budget (ship in `subpackage_audio`).
- Editor playmode plays all audio for iteration speed — the Tuanjie SDK's
  Editor mock handles `AudioSource` calls automatically.

## Decision

1. **Unity AudioSource is the default audio API.** Use `AudioSource.PlayOneShot`
   for SFX and `AudioSource.Play` for BGM/voice — the same Unity audio code
   you'd write for any platform.
2. **The SDK auto-adapts.** No project-side routing logic. The SDK plugin
   detects audio file size and automatically selects `innerAudioContext`
   (long) or `WebAudio` (short).
3. **`Wx.PreDownloadAudios` for pre-caching.** The `Wx` Facade exposes
   `PreDownloadAudios(string[] urls, Action onSuccess, Action<string> onError)`
   to pre-cache audio files before playback. This is the only audio-related
   Facade method.
4. **No `Wx.PlayInnerAudio` / `Wx.PlayBgm` Facade methods.** They are
   unnecessary — the SDK routes through them automatically via Unity
   AudioSource.

### Architecture

```
AudioClip asset
     │
     ▼
Unity AudioSource.Play / PlayOneShot  (standard Unity API — single code path)
     │
     ▼
WX SDK plugin (internal, transparent)
     │
     ├─ Large file (> threshold) → wx.createInnerAudioContext (native decode, streamed)
     │
     └─ Small file (≤ threshold) → wx.createWebAudioContext (fast decode, low latency)

Supplementary:
  Wx.PreDownloadAudios(url[]) → pre-cache audio files before playback
```

### Key Interfaces

```csharp
// Standard Unity audio (primary — works everywhere, SDK auto-adapts on WeChat)
[SerializeField] AudioSource bgmSource;
[SerializeField] AudioClip bgmClip;

bgmSource.clip = bgmClip;
bgmSource.Play();

// SFX
[SerializeField] AudioSource sfxSource;
sfxSource.PlayOneShot(hitConfirmClip);

// Supplementary: pre-download audio via Wx Facade (optional optimization)
Wx.PreDownloadAudios(
    new[] { "subpackage_audio/bgm_main.mp3" },
    onSuccess: () => bgmSource.Play(),
    onError: msg => Debug.LogError($"Audio pre-download failed: {msg}")
);
```

### Implementation Guidelines

- BGM and voice assets ship in `subpackage_audio` (ADR-0003), referenced via
  `AudioClip` in the scene/prefab.
- SFX assets ship in their owning subpackage (e.g., combat SFX in
  `subpackage_core`), also via `AudioClip` references.
- Use mp3 or aac format for all audio — best dual-platform (Android/iOS)
  compatibility.
- Prefer a single long-running `AudioSource` for BGM, `PlayOneShot` for SFX.
- The SDK's Editor mock (`wx-runtime-editor.dll`) handles `AudioSource` calls
  in Editor — no project-side mock needed.
- **FMOD**: supported but uses WebAudio for ALL audio (no `innerAudioContext`).
  Not recommended for BGM (would put long audio PCM in memory). Use only if
  the project has a non-negotiable FMOD dependency and the audio budget
  accounts for it.

## Alternatives Considered

### Alternative 1: Manual routing via `Wx.PlayInnerAudio` / `Wx.PlayBgm` (previous v1 position)

- **Description**: Write custom Facade methods that call
  `wx.createInnerAudioContext` from C#, with a threshold to decide Unity
  AudioSource vs Wx Facade.
- **Pros**: Explicit control of which audio path is used.
- **Cons**: Duplicates what the SDK already does automatically. Two playback
  paths for the same asset type. Requires custom AudioImportRule, custom
  `AudioStreamReference` ScriptableObject, and per-asset classification.
  Editor behavior diverges from WebGL.
- **Rejection Reason**: The SDK already auto-adapts Unity AudioSource. Adding
  a manual routing layer is unnecessary complexity.

### Alternative 2: All audio through `wx.createInnerAudioContext`

- **Description**: Route every clip through WeChat's native audio API via the
  Wx Facade.
- **Pros**: Memory-cheap for long audio.
- **Cons**: SFX latency unacceptable (50–200 ms per first-play). Editor mock
  divergence. Extra Facade surface.
- **Rejection Reason**: Latency-infeasible for SFX.

### Alternative 3: FMOD / Wwise

- **Description**: Use a middleware audio engine.
- **Pros**: Industrial-strength feature set.
- **Cons**: FMOD uses WebAudio for ALL audio (no `innerAudioContext`), so BGM
  burns memory. Neither has a sanctioned WeChat Mini Game integration. Wwise
  WebGL support is limited.
- **Rejection Reason**: No platform support advantage over Unity AudioSource.

## Consequences

### Positive

- Single audio code path (`AudioSource`) works in Editor and on WeChat.
- No custom audio routing logic to maintain.
- No `AudioImportRule` or `AudioStreamReference` needed — standard Unity
  `AudioClip` references work.
- The SDK's own performance team maintains the audio adaptation layer.

### Negative

- Audio memory behavior is opaque — the SDK decides the threshold, and it may
  change across SDK versions. A BGM that streams today could decode to PCM
  tomorrow after an SDK update. Mitigation: measure audio memory on each SDK
  upgrade.
- The SDK's auto-adaptation threshold is not publicly documented. We cannot
  predict exactly which clips route to `innerAudioContext` vs `WebAudio`.

### Neutral

- `Wx.PreDownloadAudios` is available for projects that want deterministic
  pre-caching behavior.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| SDK changes the auto-adaptation threshold and a BGM suddenly loads as PCM | LOW | HIGH | Measure audio memory in CI after every SDK upgrade. |
| iOS high-perf mode audio issues (known platform gap) | MEDIUM | MEDIUM | Test on iOS 高性能+ and 高性能 modes before release. |
| Too many simultaneous AudioSource instances cause lag | MEDIUM | MEDIUM | Cap concurrent SFX voices; use an AudioMixer or manual voice management. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Active audio memory (BGM) | ~ 10 MB PCM | ~ 0 MB (innerAudioContext streams) | ≤ 0 MB for long audio |
| Active audio memory (SFX) | unknown | ~ 10 MB PCM for concurrent SFX | ≤ 32 MB total audio |
| SFX trigger latency | unknown | < 1 frame (WebAudio via SDK) | < 1 frame |
| Code complexity | n/a | 0 custom audio routing lines | n/a |

## Migration Plan

Greenfield. Implementation order:

1. Use standard Unity AudioSource for all audio.
2. Place first BGM and SFX in `subpackage_audio` (ADR-0003).
3. Verify audio plays in Editor (SDK Editor mock).
4. WebGL smoke test on real WeChat client — confirm BGM streams via
   `innerAudioContext` (check memory via Unity Profiler or WeChat DevTools).
5. If pre-caching is needed, add `Wx.PreDownloadAudios` Facade method.
6. If FMOD is required later, re-open this ADR with measured memory impact.

**Rollback plan**: If the SDK's auto-adaptation proves insufficient (e.g., a
long clip is incorrectly routed to WebAudio and causes a memory spike), fall
back to manual `wx.createInnerAudioContext` calls via a `Wx.PlayInnerAudio`
Facade method. Track this as a documented escape hatch, not the default.

## Validation Criteria

- [ ] BGM plays via `AudioSource.Play` on WeChat client; memory measurement
      confirms it uses `innerAudioContext` (no PCM in Unity heap).
- [ ] SFX plays via `AudioSource.PlayOneShot` with < 1-frame latency.
- [ ] Editor playmode plays all audio without crashing.
- [ ] Active audio memory ≤ 32 MB measured on real WeChat client.
- [ ] `Wx.PreDownloadAudios` Facade method exists and SDK Editor mock returns
      sensibly (if pre-caching is adopted).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Audio | BGM and voice must play without consuming Unity heap memory | SDK auto-adapts AudioSource to `innerAudioContext` for long audio — zero heap cost. |
| Foundational | Audio | SFX must play with snappy latency | SDK auto-adapts short audio to `WebAudio` — fast decode. |

> Foundational — no GDD requirement. Enables: every audio-bearing feature within
> the memory ceiling.

## Related

- ADR-0001 (the `Wx` Facade exposes `PreDownloadAudios` — the only audio Facade method)
- ADR-0003 (`subpackage_audio` is where audio assets live)
- ADR-0002 (memory budget)
- WeChat official docs: `AudioAndVideo.html` — "优先建议使用 UnityAudio 来播放音频"
