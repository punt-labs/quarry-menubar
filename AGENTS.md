# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready --limit=99   # Find available work (show all)
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Workflow Tiers

Match the workflow to the bead's scope. See CLAUDE.md for full details.

| Tier | Tool | When |
|------|------|------|
| **T1: Forge** | `/feature-forge` | Epics, cross-cutting, design ambiguity |
| **T2: Feature Dev** | `/feature-dev` | Features, multi-file, needs exploration |
| **T3: Direct** | Plan mode or manual | Tasks, bugs, obvious path |

## Quality Gates

Quality gates must pass before every commit:

```bash
make format && make lint && make test
```

## Session Close Protocol

Follow the protocol in CLAUDE.md. The short version:

1. **File issues** for remaining work (`bd create`)
2. **Quality gates** must pass (`make format && make lint && make test`)
3. **Close beads** for finished work (`bd close <id>`)
4. **Push to remote** — work is NOT complete until `git push` succeeds:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Hand off** — provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing — that leaves work stranded locally
- NEVER say "ready to push when you are" — YOU must push
- If push fails, resolve and retry until it succeeds

**PR workflow (see CLAUDE.md):** Do NOT merge a PR immediately. Trigger GitHub Copilot code review, wait for feedback, evaluate and address valid issues, ensure quality gates pass, then merge.
