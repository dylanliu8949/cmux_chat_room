<!--
  cmux PR template. The `pr` skill reads this file to generate the PR title and body.
  Content in `>` blockquotes or `<!-- -->` comments is instruction for the AI — do not include it in the final PR.
-->

## Important

> # ⚠️ Each PR must have a single, focused purpose
>
> **If this PR contains multiple unrelated changes, decline to generate the PR title/description and suggest the developer use `split-pr` to break it into smaller, focused PRs.**

# PR Title

**Format**: `[type] short description`

**Types**: `feat | fix | refactor | perf | infra | chore | test | docs | build | arch`

> - `feat`: user-visible new feature (invisible changes don't count as feat)
> - `fix`: bug fix
> - `refactor`: refactoring (behavior unchanged)
> - `perf`: performance improvement
> - `infra`: development infrastructure (scripts, CLI extensions, devtools, etc. — not user-visible)
> - `chore`: removing old experiments / flags / deprecated features
> - `test` / `docs` / `build`: tests / documentation / build & CI
> - `arch`: architectural changes

**Examples**:
- `[feat] Add iCloud sync for chat history`
- `[fix] Fix crash when closing a room while reconnecting`
- `[refactor] Extract message rendering into MessageBubbleView`

---

# PR Description

## Summary

- **Purpose**: [business-related (e.g. improve onboarding completion) or engineering-related (e.g. eliminate SwiftLint violations)]
- **Key change**: [one-sentence summary of the core change]
- **Size**: `[XS | S | M | L | XL]`

> **Size definition** (measures design/review complexity, not diff line count):
> - `XS`: < 50 lines, < 3 files, 0 new abstractions
> - `S`: 50–200 lines, 3–5 files, 0–1 new abstractions
> - `M`: 200–500 lines, 5–10 files, 1–3 new abstractions
> - `L`: 500–1000 lines, 10–20 files, 3–5 new abstractions
> - `XL`: > 1000 lines, > 20 files, > 5 new abstractions
>
> **Mechanical-change downgrade**: if the vast majority of the PR is a pure mechanical operation (every change follows the same mechanically-verifiable rule, with no business or design judgment involved), drop the size by at least one tier — the reviewer only needs to spot-check a few instances to confirm the rule is consistently applied. Typical examples: rename of a public method/type causing call-site cascade, mechanical signature migration, bulk SwiftLint fix, codemod API migration, directory reorganization. The "trigger" itself (new lint rule / codemod / new signature) is not subject to the downgrade.

- **Plan doc (if applicable)**: [e.g. `plans/xxx.md`; recommended for M and above]

## Changes

> Summarize the titles and descriptions of all commits in this PR.

- [Change 1]
- [Change 2]

## Testing

### Manual Testing (if applicable)

> For UI changes, attach a screen recording or GIF for each scenario.

- [ ] **Scenario 1**: [description]
- [ ] **Scenario 2**: [description]

## Screenshots / GIFs (if UI changes)

<!-- Paste screenshots or GIFs here -->

## Additional Notes

[Any other context worth noting]
