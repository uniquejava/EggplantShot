# 01: Introduce Matt Pocock engineering skills

**What to build:** Configure this repo so Matt Pocock's engineering skills (`to-spec`, `to-tickets`, `implement`, `wayfinder`, `grill-with-docs`, `tdd`, `code-review`, `triage`, …) know where tickets, triage labels, and domain docs live.

**Blocked by:** None (can start immediately)

**Status:** resolved

## Scope

- Record the issue tracker as local markdown under `.scratch/`
- Install default triage label vocabulary
- Declare single-context domain docs (`GLOSSARY.md` + `docs/adr/`)
- Wire an `## Agent skills` section in `AGENTS.md` that points at `docs/agents/`

## Acceptance

- [x] `docs/agents/issue-tracker.md` exists and describes the local-markdown conventions
- [x] `docs/agents/triage-labels.md` exists with the five default roles
- [x] `docs/agents/domain.md` exists for single-context layout
- [x] `AGENTS.md` has an `## Agent skills` block linking those docs
- [x] This ticket is published at `.scratch/matt-pocock-skills/issues/01-introduce-matt-pocock-skills.md`

## Notes

Skills themselves are installed globally via `npx skills` (`mattpocock/skills`); this ticket is only the per-repo configuration those skills read.
