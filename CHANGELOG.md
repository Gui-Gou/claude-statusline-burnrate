# Changelog

## 2.1.0 — 2026-10-31

### Added
- **Herdr edition** (`statusline-herdr.sh`): one short line for running Claude Code inside [Herdr](https://herdr.dev). Herdr already shows usage, branch and agent status, so the line keeps only the model and effort, the context bar with tokens left before 200k, this session's lines +/−, and the folder Claude works in now. Only the bar is colored; model and effort get a faint tint.
- **Folder drift** on the Herdr line: the short path of the current folder, last on the line. Plain inside the launch folder, amber outside it, red in a different git repo. The repo check walks up for `.git` in pure bash (no `git` call). `SL_HERDR_DIR=0` hides it.
- It feeds Herdr: one JSON per session in `~/.claude/.cache/herdr-usage/` plus the weekly sub-tick file, written in the background. `SL_HERDR_FEED` (`auto` / `1` / `0`) controls it.
- `./demo.sh --herdr` (with an amber and a red folder case), and `assets/herdr.png` rendered by `tools/make-images.sh`.

## 2.0.0 — 2026-09-24

The status line is now a two-row **card**. The one-liner lives on as `statusline-classic.sh`.

**Upgrading:** re-running the install command gives you the card. To keep the one-line layout, download `statusline-classic.sh` instead (see the README).

### Added
- **Card layout** (`statusline.sh`): a rounded frame with the model and effort in the top border, WK / CX / 5H meters as bars, and each meter's detail aligned under it.
- **Gray until it matters:** healthy values stay gray. Only a meter that is warming up turns yellow → orange → red.
- **5-hour trend:** `↻` countdown plus ▲/▼/✓ against an even burn of the window.
- **Tokens left before 200k:** a countdown, then a yellow ╳ from 200k and a red ╳ from 300k — your cue to start a fresh session.
- **Session time**, **time since the last commit** in this folder, and the folder name.
- **Claude service status:** a 🔥 with severity bars appears only during a status.claude.com incident. It is checked in the background, so it never slows a render. `SL_STATUS=0` turns it off.
- **Task counts** (opt-in, `SL_TASKS=1`): open / in-progress / blocked items from `project-management/TASKS.md`, shown in place of the cost.
- **Antigravity CLI (`agy`) support** in both scripts: quota read from `agy -p "/usage"` in the background, effort taken from the model name, own colors for Gemini and GPT models. Thanks @basedpolymer (#1).
- `./demo.sh --classic`; `./demo.sh --live` is now an animated tour that sweeps every meter.

### Fixed
- agy: when `/usage` lists no 5-hour limit for a model family, the weekly figure no longer shifts into the 5-hour slot.
- A long model name now widens the card instead of overflowing its frame.
- Linux: cache ages are read with GNU `stat` first. Before this, the agy quota cache always looked stale there, so it refreshed on every render.

## 1.0.0 — 2026-08-01

First release: the one-line status line with real `rate_limits` data, today's share of the week, sustainable pace, the sleep-aware trend, and the cat.
