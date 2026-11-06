#!/usr/bin/env bash
# claude-statusline-burnrate — Herdr edition: one short line for running
# Claude Code inside Herdr (https://herdr.dev).
#
#   FABLE 5 · HIGH │ CX ▰▰▱▱▱ 42% 120k │ +128 −43 │ ~/src/my-app
#
# Herdr already shows the plan usage (5H / WK), the git branch and the agent's
# status, so this line keeps only what Herdr can't know per pane:
#
#   model · effort = which model this pane runs, and at what effort
#   CX             = how full THIS chat's context window is, then the tokens
#                    left before the 200k line (╳ past it: time for a fresh
#                    session)
#   +N −N          = lines this session added and removed (not the repo's diff)
#   ~/path         = the folder Claude works in right now. Herdr shows where the
#                    pane started; Claude moves with `cd`. Plain while inside
#                    the launch folder, amber once outside it, red when it is in
#                    a different git repo (edits may land in the wrong repo).
#                    SL_HERDR_DIR=0 hides it.
#
# It still feeds Herdr: one small JSON per session in
# ~/.claude/.cache/herdr-usage/ (for a usage panel in Herdr's sidebar) and the
# sub-tick file sl-tick, both written in the background. The feed is on when
# the session runs in a Herdr terminal ($HC_TERMINAL_ID set); SL_HERDR_FEED=1
# forces it on, 0 turns it off.
#
# Color: only the context bar is colored. Model and effort get a faint tint;
# everything else is plain text.

SL_HERDR_FEED="${SL_HERDR_FEED:-auto}"
SL_HERDR_DIR="${SL_HERDR_DIR:-1}"
CACHE="$HOME/.claude/.cache"; mkdir -p "$CACHE" 2>/dev/null

input=$(cat)

# One jq pass, fields joined by US (0x1f). Not tab: tab is IFS-whitespace, so
# `read` would collapse empty fields and misalign everything after them.
IFS=$'\x1f' read -r model eff cpct ctok cwsz ladd lrem sid cost r7 cur proj < <(echo "$input" | jq -r '
  [ .model.display_name // "",
    (.effort.level // ""),
    (.context_window.used_percentage      // "" | tostring),
    (.context_window.total_input_tokens  // "" | tostring),
    (.context_window.context_window_size // "" | tostring),
    (.cost.total_lines_added   // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    (.session_id // ""),
    (.cost.total_cost_usd // "" | tostring),
    (.rate_limits.seven_day.used_percentage // "" | tostring),
    (.workspace.current_dir // .cwd // ""),
    (.workspace.project_dir // "") ] | join("\u001f")')

# ---- Herdr feed --------------------------------------------------------------
feed=0
case "$SL_HERDR_FEED" in
  1) feed=1 ;;
  0) feed=0 ;;
  *) [ -n "${HC_TERMINAL_ID:-}" ] && feed=1 ;;
esac

# One JSON per session for a Herdr usage panel. Background + atomic mv: no render cost.
if [ "$feed" = 1 ] && [ -n "$sid" ]; then
  ( SNAPD="$CACHE/herdr-usage"; mkdir -p "$SNAPD" 2>/dev/null
    echo "$input" | jq -c --argjson ts "$(date +%s)" --arg term "${HC_TERMINAL_ID:-}" '{term: $term, sid: .session_id, cwd: (.workspace.current_dir // .cwd),
      model: .model.display_name, ctx: .context_window.used_percentage, ctxTokens: .context_window.total_input_tokens,
      ctxSize: .context_window.context_window_size, five: .rate_limits.five_hour, week: .rate_limits.seven_day,
      cost: .cost.total_cost_usd, added: .cost.total_lines_added, removed: .cost.total_lines_removed,
      effort: .effort.level, ts: $ts}' > "$SNAPD/$sid.json.tmp" 2>/dev/null && mv -f "$SNAPD/$sid.json.tmp" "$SNAPD/$sid.json"
  ) >/dev/null 2>&1 &
fi

# Sub-tick anchor for the weekly %. Same file and math as statusline.sh (see
# its comments): the weekly % is an integer, so a reader smooths between ticks
# with this session's live cost. Only the anchor is written here; nothing on
# this line shows it.
if [ "$feed" = 1 ] && [ -n "$r7" ] && [ -n "$sid" ] && [ -n "$cost" ]; then
  TICKF="$CACHE/sl-tick"
  tu=""; tsid=""; tc=""; tk=""
  read -r tu tsid tc tk 2>/dev/null < "$TICKF"
  tick=$(awk -v u="$r7" -v c="$cost" -v sid="$sid" -v tu="$tu" -v tsid="$tsid" -v tc="$tc" -v tk="$tk" 'BEGIN{
    k = tk+0; if (k < 1 || k > 20) k = 4.5
    if (tu == "" || u+0 != tu+0 || sid != tsid) {
      if (tsid == sid && u+0 == tu+1 && c-tc > 0.5 && c-tc < 40) k = 0.5*k + 0.5*(c-tc)
      printf "ANCHOR %s %s %.4f %.2f", u, sid, c, k
    }
  }' 2>/dev/null)
  case "$tick" in ANCHOR\ *) printf '%s' "${tick#ANCHOR }" > "$TICKF" 2>/dev/null ;; esac
fi

# ---- colors ------------------------------------------------------------------
# Plain text everywhere except the context bar, plus a faint tint on the model
# and effort (gray with a hint of hue, so the line stays quiet).
RST=$'\e[0m'; esc=$'\e'
tint() { printf '%s[38;2;%sm' "$esc" "$1"; }

# ---- model · effort ------------------------------------------------------------
model="${model%% (*}"   # "Opus 4.8 (1M context)" -> "Opus 4.8"
case "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" in
  *opus*)   mc="186;164;150" ;;   # warm
  *sonnet*) mc="150;166;190" ;;   # blue
  *fable*)  mc="174;158;192" ;;   # violet
  *haiku*)  mc="154;180;160" ;;   # green
  *flash*)  mc="148;178;186" ;;   # cyan
  *gpt*)    mc="148;180;166" ;;   # emerald
  *pro*)    mc="158;160;194" ;;   # indigo
  *gemini*) mc="152;166;190" ;;
  *)        mc="166;166;166" ;;
esac
model=$(printf '%s' "$model" | tr '[:lower:]' '[:upper:]')
case "$eff" in   # effort, cool -> warm
  low)       ec="160;166;172" ;;
  medium)    ec="186;178;146" ;;
  high)      ec="190;166;144" ;;
  xhigh|max) ec="194;154;150" ;;
  *)         ec="166;166;166" ;;
esac
eff=$(printf '%s' "$eff" | tr '[:lower:]' '[:upper:]')

# ---- context bar (same ramp as statusline.sh) ---------------------------------
SUN5=("148;155;168" "197;168;123" "234;179;8" "237;138;48" "239;68;68")
bar() {  # $1 = pct 0-100, 5 cells
  local v=$1 n=5 lit i out=""
  [ "$v" -gt 100 ] && v=100; [ "$v" -lt 0 ] && v=0
  lit=$(( (v * n + 50) / 100 ))
  [ "$v" -gt 0 ] && [ "$lit" -eq 0 ] && lit=1
  for (( i=0; i<n; i++ )); do
    if [ "$i" -lt "$lit" ]; then out="${out}${esc}[38;2;${SUN5[$i]}m▰"
    else out="${out}${esc}[38;2;55;60;70m▱"; fi
  done
  printf '%s%s' "$out" "$RST"
}

cx=""
if [ -n "$cpct" ]; then
  p=$(printf '%.0f' "$cpct" 2>/dev/null); case "$p" in ''|*[!0-9-]*) p=0 ;; esac
  cx="CX $(bar "$p") ${p}%"
fi

# Headroom before the 200k line: past it recall drops and tokens cost more.
# total_input_tokens is the whole prompt; fall back to used% x window size.
tk="$ctok"; case "$tk" in ''|*[!0-9]*) tk="" ;; esac
if [ -z "$tk" ] && [ -n "$cpct" ]; then
  case "$cwsz" in ''|*[!0-9]*) : ;;
    *) tk=$(awk -v p="$cpct" -v w="$cwsz" 'BEGIN{printf "%d", p*w/100}' 2>/dev/null) ;;
  esac
  case "$tk" in ''|*[!0-9]*) tk="" ;; esac
fi
if [ -n "$tk" ] && [ "$tk" -gt 0 ]; then
  if [ "$tk" -ge 200000 ]; then hr="╳"
  else
    left=$(( 200000 - tk ))
    if [ "$left" -ge 1000 ]; then hr="$(( left / 1000 ))k"; else hr="<1k"; fi
  fi
  cx="${cx:+$cx }$hr"
fi

# ---- lines this session -------------------------------------------------------
case "$ladd" in ''|*[!0-9]*) ladd=0 ;; esac
case "$lrem" in ''|*[!0-9]*) lrem=0 ;; esac
lines=""
[ "$(( ladd + lrem ))" -gt 0 ] && lines="+${ladd} −${lrem}"

# ---- folder: where Claude works now, colored by drift from the launch folder --
# Nearest folder holding .git (a folder, or a file in worktrees and submodules).
# Pure bash, no git call, so the render never waits. Result in $GR.
gitroot() {
  local d=$1; GR=""
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { GR=$d; return; }
    d=${d%/*}
  done
}

dir=""
if [ "$SL_HERDR_DIR" != 0 ] && [ -n "$cur" ]; then
  cur=${cur%/}; proj=${proj%/}
  case "$cur" in
    "$HOME")   short="~" ;;
    "$HOME"/*) short="~${cur#"$HOME"}" ;;
    *)         short=${cur:-/} ;;
  esac
  dc=""   # plain: no launch folder known, or still inside it
  if [ -n "$proj" ]; then
    case "$cur/" in
      "$proj"/*) ;;
      *) gitroot "$cur"; cr=$GR; gitroot "$proj"
         if [ -n "$cr" ] && [ "$cr" != "$GR" ]; then dc="239;68;68"   # red: other repo
         else dc="234;179;8"; fi ;;                                    # amber: outside
    esac
  fi
  if [ -n "$dc" ]; then dir="$(tint "$dc")${short}${RST}"; else dir=$short; fi
fi

# ---- assemble -----------------------------------------------------------------
SEP=" │ "
out=""
[ -n "$model" ] && out="$(tint "$mc")${model}${RST}"
[ -n "$eff" ]   && out="${out:+$out · }$(tint "$ec")${eff}${RST}"
[ -n "$cx" ]    && out="${out:+$out$SEP}$cx"
[ -n "$lines" ] && out="${out:+$out$SEP}$lines"
[ -n "$dir" ]   && out="${out:+$out$SEP}$dir"
printf '%s' "$out"
