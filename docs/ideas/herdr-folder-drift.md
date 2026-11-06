# Folder drift segment for the Herdr line

Status: built 2026-11-05 (uncommitted). current_dir confirmed to follow `cd` from a live Herdr feed file; 100 renders take ~1.2 s in total.

## Problem Statement
How might we show, at a glance, which folder Claude is working in right now, and warn when it has drifted away from where the session started?

## Recommended Direction
Add one segment to the end of `statusline-herdr.sh`: the short path of `workspace.current_dir`, with `~` for home. It always shows, and its color says how far Claude has drifted from `workspace.project_dir` (the launch folder):

| State | Rule | Look |
|---|---|---|
| Home | current dir is the launch dir or a folder inside it | plain text |
| Drifted | outside the launch dir, but in the same git repo or in no repo | amber |
| Wrong repo | the nearest git root differs from the launch dir's git root | red |

Example: `FABLE 5 · HIGH │ CX ▰▰▱▱▱ 42% 120k │ +128 −43 │ ~/.claude` (red: launched in `skills`, now writing in another repo).

Why: Herdr shows the pane's launch folder, not where Claude went. Claude moves with Bash `cd` (one session went skills → `~/.claude` → the status line repo). The real risk is edits landing in the wrong repo. So that case gets the loud color, and the harmless case (a subfolder) stays plain. The path is the last segment, so a narrow pane clips it before the model or context.

Git root lookup walks up the tree looking for `.git` (a folder or a file) in pure bash. No `git` call, so the render never blocks. The "inside the launch dir" check runs first. Worktrees under `<repo>/.worktrees/` count as home, not as a wrong repo.

## Key Assumptions to Validate
- [x] `workspace.current_dir` follows Claude's Bash `cd` during a session. Test: log stdin to a file, `cd` elsewhere in a session, check the next payload.
- [ ] `workspace.project_dir` stays the launch folder (it does not follow `cd` or `/add-dir`). Test: same log.
- [ ] A short path fits typical Herdr pane widths without clipping the folder name. Test: `./demo.sh --herdr` with a long path at 80 and 100 columns.
- [x] The `.git` walk is fast enough on every render (about 10 `[ -e ]` checks). Test: `time` 100 renders.

## MVP Scope
In:
- Path segment, last in the line, `$HOME` shown as `~`.
- Three states: plain, amber, red, using the existing `tint()` helper.
- `SL_HERDR_DIR=0` turns the segment off (README Tweak table).
- Update the script header, README and CHANGELOG lines that say "Herdr already shows the folder".
- `demo.sh --herdr` gets a drifted and a wrong-repo case. Rebuild images with `tools/make-images.sh`.

Out: everything below.

## Not Doing (and Why)
- Card (`statusline.sh`) and classic line: they already show the folder name. Drift colors there can follow once this proves useful.
- Middle-truncating long paths: wait to see if clipping actually happens in Herdr panes.
- Showing the jump (`skills → ~/.claude`): twice the width for little gain; the color already says "you moved".
- Relative paths (`./docs`): a mixed format is harder to read at a glance than one plain path.
- Feeding the live dir into Herdr's sidebar: the usage JSON already carries `cwd`. Using it is Herdr-side work, a separate idea.
- Calling `git rev-parse`: a subprocess on every render, against the "never block a render" rule.

## Open Questions
- Launched in `~`: every folder counts as "inside", so it never warns. Fine, or should home launches always treat other repos as red?
- Should the amber state exist at all, or is plain vs red enough?
- `statusline-herdr.sh` and the Herdr README changes are still uncommitted. Land those first, then this as its own commit?
