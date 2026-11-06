# AGENTS.md

A Claude Code status line: bash that reads the JSON payload on stdin and prints ANSI text. No build step and no tests beyond the checks below.

## Files

- `statusline.sh` — the default: a two-row card (v2).
- `statusline-classic.sh` — the one-line v1. Same math. Keep fixes to the shared math in sync across both files.
- `statusline-herdr.sh` — one short line for Herdr users: model · effort, context, lines +/−, current folder (amber/red on drift). Also writes the Herdr usage feed. Shares the context-bar code with the card; keep that in sync.
- `demo.sh` — renders fake payloads with an isolated `$HOME`. `--classic`, `--herdr` and `--live` also work.
- `tools/make-images.sh` — rebuilds **every** README image from real script output (`ansi2html.py --grid` → headless Chrome → `autocrop.py`). `tools/infographic.py` lays out the annotated card.
- `CHANGELOG.md` — one entry per release.

## Rules

- **bash 3.2** (the macOS default): no `${var^^}`, no associative arrays, no `mapfile`. Use `tr` for case changes.
- **jq is the only hard dependency.** Anything else (`curl`, `git`, `python3`, `agy`) must be optional: check it with `command -v` and skip quietly if it is missing.
- **Never block a render.** Network or other slow calls run in the background and write a cache under `~/.claude/.cache/`; the render only reads that cache.
- **Widths are hand-tracked.** ANSI codes take no columns, an emoji takes 2, and `▰ ╳ ↻ ⌂` take 1. When you add or change a glyph, update the matching `…l` / `…len` counter, or the card's right border goes crooked.
- **Portability:** macOS (BSD) and Linux (GNU) both have to work. `date -v…` first, then `date -d …`. But `stat` is the other way round, `stat -c %Y` || `stat -f %m`: on GNU, `stat -f %m` fails *after* writing filesystem info to stdout, which ends up inside `$(…)`.
- **No personal data:** no home paths, hostnames or personal schedules. Put anything user-specific behind an `SL_*` variable with a sensible default, and document it in the README's Tweak table.

## Before you commit

```bash
bash -n statusline.sh && bash -n statusline-classic.sh && bash -n statusline-herdr.sh
./demo.sh && ./demo.sh --classic && ./demo.sh --herdr     # check the card's right border lines up
bash tools/make-images.sh             # only when the look changed (needs Chrome + Pillow)
```

README images are always rendered, never screenshots. Commit them with the change that altered the look.

## Releasing

Add a `CHANGELOG.md` entry, tag `vX.Y.Z`, and publish a GitHub release using that entry as the notes. The repo lives under the `Gui-Gou` account, so scope `gh` with `GH_TOKEN=$(gh auth token --user Gui-Gou)`.
