# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 48 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Unity 2021.3 LTS (template — installer rewrites paths at deploy time)
- **Language**: C# (.NET Standard 2.1, IL2CPP backend)
- **Version Control**: Git with trunk-based development
- **Build System**: Unity Build Pipeline → WebGL 2.0 → `minigame-tuanjie-transform-sdk` → `wx.*` runtime
- **Asset Pipeline**: Unity AssetImporter (no Addressables — see ADR-0003) → WeChat SubPackages

> **Note**: This branch targets **WeChat Mini Game (微信小游戏)** via WebGL 2.0.
> Engine specialists used: `unity-specialist`, `unity-shader-specialist`,
> `unity-ui-specialist`. DOTS and Addressables specialists are forbidden on this
> target — see `.claude/docs/technical-preferences.md`.

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

---

> This is the **unity-2021-instant-game** template branch. Run
> `tools/install-template.ps1` to deploy into a target project. See
> `README-branch.md` for full deployment instructions and known caveats.
