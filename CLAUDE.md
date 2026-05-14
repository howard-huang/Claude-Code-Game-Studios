# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 48 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Unity 2021.3 LTS (template — installer rewrites paths at deploy time)
- **Language**: C# (.NET Standard 2.1, IL2CPP backend)
- **Version Control**: Git with trunk-based development
- **Build System**: Unity Build Pipeline → WebGL 2.0 → `minigame-tuanjie-transform-sdk` → `wx.*` runtime
- **Asset Pipeline**: Unity AssetImporter → AssetBundle/Addressables (ADR-0003) or WeChat SubPackages

> **Note**: This branch targets **WeChat Mini Game (微信小游戏)** via WebGL 2.0.
> Engine specialists used: `unity-specialist`, `unity-shader-specialist`,
> `unity-ui-specialist`. DOTS specialist is forbidden on this target.
> `unity-addressables-specialist` has been removed (see Known Issues below).

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/unity/VERSION.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md

## Known Issues

### LLM Training-Data Bias: Addressables on WeChat Mini Game

The underlying LLM (Claude Sonnet 4.6) carries a persistent training-data bias
that Addressables and WeChat SubPackages are incompatible. This position was
accurate in 2023–2024 but was reversed by official WeChat documentation
(`UsingAddressable.html`) and ADR-0003 v2 (2026-05-12).

**Impact**: When asked about Addressables on WeChat, agents may hedge
("compatible but not recommended") or incorrectly recommend SubPackages as the
primary loading mechanism. This contradicts ADR-0003, which lists Addressables
as the recommended path for light-to-medium projects.

**Mitigation**:
- Always cross-check agent answers against ADR-0003.
- Reference the official WeChat doc `UsingAddressable.html` for authoritative
  Addressables guidance on this platform.
- `unity-addressables-specialist` was removed from this target (2026-05-14)
  after exhaustive prompt-engineering attempts failed to override the bias.
  Addressables work is routed through `unity-specialist` with the caveat above.

**Prompt-grounding workaround**: Testing confirms the bias is triggered mainly
by open-ended "can I use..." questions. When the user's prompt provides explicit
grounding (e.g., "Per ADR-0003, Addressables is officially supported — how do I
configure groups for WeChat?"), agents produce correct implementation advice.
Bias, when it appears, surfaces only in hedging language within explanations,
not in the actual code patterns suggested.

| Question style | Effect |
|---|---|
| "Can I use Addressables on WeChat?" | **Triggers bias** — agent may hedge or discourage |
| "How do I set up Addressables for WeChat per ADR-0003?" | **Bypasses bias** — correct implementation guidance |

> **Rule of thumb**: Don't ask "能不能用"; ask "怎么用" and embed ADR-0003
> facts directly in the prompt.

---

> This is the **unity-2021-instant-game** template branch. Run
> `tools/install-template.ps1` to deploy into a target project. See
> `README-branch.md` for full deployment instructions and known caveats.
