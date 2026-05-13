# ADR-0006: Audio Strategy — long via wx.createInnerAudioContext, short via Unity AudioSource

## Status

Proposed

## Date

2026-05-12

## Last Verified

2026-05-12

## Decision Makers

- `technical-director` (architecture authority)
- `unity-specialist` (Unity audio integration)
- `audio-director` (sonic palette + memory budget for audio)

## Summary

Long audio (BGM and voice lines > 3 s **or** > 100 KB compressed) routes through
`wx.createInnerAudioContext` exposed by the `Wx` Facade (ADR-0001) — WeChat
decodes the audio natively and streams it without holding the full PCM in
Unity's 256 MB memory ceiling. Short SFX (< 3 s and < 100 KB) play via Unity
`AudioSource` because WebAudio decode for sub-second clips is cheap and the
latency of `wx.createInnerAudioContext` first-play is too high for snappy SFX.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 2021.3 LTS |
| **Domain** | Audio |
| **Knowledge Risk** | MEDIUM — `wx.createInnerAudioContext` semantics are platform-level and post-cutoff for behavior nuances |
| **References Consulted** | `docs/engine-reference/unity/VERSION.md`, WeChat Mini Game audio docs |
| **Post-Cutoff APIs Used** | `wx.createInnerAudioContext` first-play latency / loop / stop semantics under Tuanjie SDK |
| **Verification Required** | Measure first-play latency of `wx.createInnerAudioContext` vs Unity `AudioSource` on target devices. Confirm the 3 s / 100 KB threshold is correct for the project's actual asset profile. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (the `Wx` Facade exposes `PlayBgm` / `PlayInnerAudio`), ADR-0003 (audio assets live in a subpackage) |
| **Enables** | Any audio-bearing feature |
| **Blocks** | Long voice / BGM stories that try to load the audio via `AudioSource.clip` (would blow memory) |
| **Ordering Note** | Accept after ADR-0001 and ADR-0003. |

## Context

### Problem Statement

Unity's `AudioSource` loads the entire decoded PCM into memory. A 60-second BGM
at 44.1 kHz / 16-bit stereo is roughly 10 MB of PCM — 4% of the 256 MB ceiling for
**one music track**. Mobile WebGL also has slow PCM decode for compressed
formats. Meanwhile, `wx.createInnerAudioContext` is WeChat's native audio API:
the WeChat client handles decoding and streaming, so the Unity heap doesn't pay
for it.

But `wx.createInnerAudioContext` has a per-call setup cost (HTTP fetch if cached
miss, decoder spin-up, native context allocation) that adds 50–200 ms of latency
on first play. That's fine for BGM that loops or for a 5-second voice clip — it's
unacceptable for a hit-confirm SFX that needs to fire on the same frame as the hit.

A naive single-path strategy ("always Unity AudioSource" or "always `wx.*`")
either blows the memory budget or makes SFX feel laggy.

### Current State

Greenfield. No audio routing decision yet.

### Constraints

- 256 MB memory ceiling (ADR-0002 implies sub-budget for audio: target ≤ 32 MB
  active audio in memory at any time).
- 4 MB first-package, 4 MB per subpackage — audio assets ship in
  `subpackage_audio` (ADR-0003).
- Unity 2021.3 + WebGL `AudioSource` has known decode-time hiccups on long
  compressed audio (LZMA/Vorbis cost on the main thread).
- WeChat client caches downloaded audio across mini-game launches.

### Requirements

- BGM and long voice lines do not consume Unity heap for their PCM.
- SFX play with < 1-frame latency from trigger.
- Audio assets respect the first-package budget (ship in `subpackage_audio`).
- Editor playmode plays all audio for iteration speed — the Tuanjie SDK's
  `wx-runtime-editor.dll` mock handles `wx.createInnerAudioContext` calls in
  Editor automatically, so `Wx.PlayBgm` works without a project-side mock.

## Decision

Route audio by length / size threshold:

| Audio category | Threshold | Path |
|---------------|-----------|------|
| BGM | always | `Wx.PlayBgm(url)` Facade → `wx.createInnerAudioContext` |
| Voice line | > 3 s OR > 100 KB compressed | `Wx.PlayInnerAudio(url)` Facade |
| Voice line | ≤ 3 s AND ≤ 100 KB | Unity `AudioSource` |
| SFX (hit, UI tick, footstep) | always | Unity `AudioSource` |
| Ambient loop | > 3 s OR > 100 KB | `Wx.PlayInnerAudio(url, loop=true)` Facade |

The threshold is enforced at asset-import time: an `AudioImportRule` in
`Unity/Assets/Scripts/Tools/AudioImportRule.cs` classifies each AudioClip and
either marks it for AudioSource use (loaded into PCM) or routes it via an
`AudioStreamReference` ScriptableObject for `Wx` Facade playback.

### Architecture

```
                ┌────────────────────────────┐
Audio asset ───►│  AudioImportRule           │
                │  (size + duration check)   │
                └─────────────┬──────────────┘
                              │
                ┌─────────────┴──────────────┐
                ▼                            ▼
   ≤ 3 s AND ≤ 100 KB              > 3 s OR > 100 KB
        │                                    │
        ▼                                    ▼
   AudioSource.PlayOneShot          Wx.PlayInnerAudio(url, loop)
   (PCM in Unity heap)              (decoded by WeChat, streamed)
```

### Key Interfaces

```csharp
namespace CCGS.Core.Platform
{
    public static partial class Wx
    {
        public static AudioHandle PlayInnerAudio(string url, bool loop = false);
        public static void StopInnerAudio(AudioHandle handle);
        public static void SetInnerAudioVolume(AudioHandle handle, float volume);

        // Convenience: BGM is the long-loop case of PlayInnerAudio.
        public static AudioHandle PlayBgm(string url) => PlayInnerAudio(url, loop: true);
    }

    public struct AudioHandle { internal int id; }
}

[CreateAssetMenu(fileName = "AudioStreamReference", menuName = "CCGS/Audio Stream Reference")]
public class AudioStreamReference : ScriptableObject
{
    public string subpackageUrl;
    public bool loop;
}
```

### Implementation Guidelines

- BGM assets live in `subpackage_audio` (ADR-0003) and are referenced via
  `AudioStreamReference`, never via `AudioClip`.
- SFX assets ship in their owning subpackage (e.g., combat SFX in
  `subpackage_core`), use `AudioClip` references, play through `AudioSource`.
- `Wx.PlayInnerAudio` returns an `AudioHandle` — store it to stop/volume.
- The Tuanjie SDK's `wx-runtime-editor.dll` handles `wx.createInnerAudioContext`
  in Editor — `Wx.PlayInnerAudio` works in Editor without a project-side mock.
  If a particular call returns a stub that breaks iteration (e.g., the mock
  returns immediately without firing `onEnded`), add a thin Editor-only branch
  inside the Facade method that calls Unity `AudioSource` instead.
- AudioImportRule runs on asset import; flag assets that don't match either
  category (e.g., 2.9 s / 105 KB borderline cases) and ask the audio-director
  to classify.
- Voice subtitles must be triggered from the audio callback, not from elapsed
  time — `wx.createInnerAudioContext` has its own playback clock.

## Alternatives Considered

### Alternative 1: All audio through Unity AudioSource

- **Description**: Default Unity workflow.
- **Pros**: Single code path, Editor and WebGL behave the same.
- **Cons**: BGM PCM alone consumes 10+ MB. With voice + ambient + multiple BGM
  tracks, the 32 MB audio sub-budget evaporates. Decode hiccups on WebGL.
- **Rejection Reason**: Memory-infeasible.

### Alternative 2: All audio through `wx.createInnerAudioContext`

- **Description**: Route every clip through WeChat's audio system.
- **Pros**: Memory-cheap.
- **Cons**: SFX latency unacceptable (50–200 ms per first-play). Tight game-feel
  suffers. Also forces an Editor mock for every SFX, slowing iteration.
- **Rejection Reason**: Latency-infeasible for SFX.

### Alternative 3: FMOD / Wwise

- **Description**: Use a middleware audio engine.
- **Pros**: Industrial-strength feature set.
- **Cons**: Neither has a sanctioned WeChat Mini Game integration. WebGL support
  is limited. Adds first-package bytes.
- **Rejection Reason**: Out of scope; no platform support.

## Consequences

### Positive

- BGM doesn't burn the memory budget.
- SFX feel snappy.
- Audio category is visible in asset metadata (`AudioStreamReference` vs `AudioClip`).
- Audio iteration in Editor remains fast.

### Negative

- Two playback paths means two places audio bugs can hide. Subtitles must hook
  the right clock.
- Borderline-duration clips need a human decision.
- Editor and WebGL behavior diverge slightly (Editor uses AudioSource for both
  paths; WebGL uses `wx.*` for one).

### Neutral

- The `subpackage_audio` (ADR-0003) becomes a load-bearing concept.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| `wx.createInnerAudioContext` instance leak (handles not freed) | MEDIUM | HIGH | `AudioHandle` is `IDisposable`; static analyzer in CI flags unfreed handles. |
| Subtitle drift from BGM clock | MEDIUM | MEDIUM | Subtitles hook the `onTimeUpdate` callback from `wx.createInnerAudioContext`, not Unity's `Time.time`. |
| SFX accidentally routed via the `Wx` Facade (wrong import classification) | MEDIUM | MEDIUM | AudioImportRule emits a warning for borderline cases; audio-director reviews. |
| Editor / WebGL behavior diverges enough to mask a real bug | LOW | HIGH | Mandatory WebGL smoke test of every audio-bearing feature before release. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Active audio memory | ~ 30+ MB (all PCM) | ~ 10 MB (PCM for SFX only) | ≤ 32 MB |
| SFX trigger latency | unknown | < 1 frame (Unity AudioSource native) | < 1 frame |
| BGM start latency | n/a | 50–200 ms (acceptable for BGM) | ≤ 250 ms |
| First-package audio contribution | n/a | 0 (audio in subpackage_audio) | 0 MB |

## Migration Plan

Greenfield. Implementation order:

1. Define `AudioStreamReference` ScriptableObject.
2. Implement `Wx.PlayInnerAudio` / `StopInnerAudio` / `SetInnerAudioVolume`
   Facade methods (depends on ADR-0001).
3. Verify the Tuanjie SDK's `wx-runtime-editor.dll` returns sensibly from
   `wx.createInnerAudioContext` in Editor; if not, add an Editor-only fallback
   inside the Facade that routes to Unity AudioSource for iteration.
4. Implement `AudioImportRule` (asset post-processor) that classifies clips.
5. Audio-director places first BGM and one long voice line in
   `subpackage_audio`, classifies all SFX as AudioSource.
6. PlayMode test verifies both paths trigger correctly.
7. WebGL smoke test verifies BGM streams and SFX play without hitch.

**Rollback plan**: Route all audio through AudioSource (Alternative 1) and
accept the memory cost. Document as Risk for ADR-0002 re-baseline.

## Validation Criteria

- [ ] `AudioStreamReference` ScriptableObject exists.
- [ ] `Wx.PlayInnerAudio`/`StopInnerAudio`/`SetInnerAudioVolume` Facade methods exist;
      Editor playmode confirms they do not crash and the SDK Editor mock returns sensibly.
- [ ] `AudioImportRule` runs on import and emits classification log.
- [ ] First BGM in `subpackage_audio` plays via `wx.createInnerAudioContext` on real WeChat client.
- [ ] First SFX plays via AudioSource with < 1-frame latency on target device.
- [ ] Active audio memory ≤ 32 MB measured via Unity Profiler (Editor).
- [ ] Subtitle text stays synchronized with `onTimeUpdate` callback, not `Time.time`.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| Foundational | Audio | BGM and voice must play without consuming Unity heap memory | Long audio routes through native WeChat audio; only SFX hold PCM in heap. |
| Foundational | Audio | SFX must play with < 1 frame latency | SFX route through Unity AudioSource for snappy feedback. |

> Foundational — no GDD requirement. Enables: every audio-bearing feature within
> the memory ceiling.

## Related

- ADR-0001 (the `Wx` Facade is the only path to `wx.createInnerAudioContext`)
- ADR-0003 (`subpackage_audio` is where long audio assets live)
- ADR-0002 (memory budget that drives the routing)
