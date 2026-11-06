#!/usr/bin/env bash
# Rebuild every README image from REAL script output — nothing is a capture:
#   assets/screenshot.png        hero: one card
#   assets/states.png            four usage states, card edition
#   assets/classic.png           the one-line v1 (statusline-classic.sh)
#   assets/herdr.png             the Herdr edition (statusline-herdr.sh)
#   assets/infographic.png       every stat explained + repo link (for sharing)
#   assets/infographic-clean.png the same without the link (used in the README)
# Needs: jq, python3 + Pillow, Google Chrome. Run from anywhere.
set -euo pipefail
TOOLS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$TOOLS/.." && pwd)"
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ---- deterministic inputs ----------------------------------------------------
# The budget math depends on the time of day, so pin "now" to 12h after waking
# (day-start 18h ago, 6h of sleep) whenever this runs — i.e. ~20:00 with the
# defaults, which is what the border clock is pinned to below. Cache, status
# polling and git all stay sandboxed.
export HOME="$WORK/home"; mkdir -p "$HOME"
export SL_STATUS=0 SL_SLEEP_HOURS=6
export SL_DAY_START=$(( ( $(date +%-H) - 18 + 24 ) % 24 ))
now=$(date +%s)
APP="$WORK/my-app"; mkdir -p "$APP"
git -C "$APP" init -q
GIT_COMMITTER_DATE="@$(( now - 720 ))" git -C "$APP" -c user.name=demo -c user.email=demo@example.com \
  commit -q --allow-empty -m demo

payload() {  # model effort ctx% ctx-tokens 5h% 5h-reset-in wk% wk-reset-in cost
  jq -nc --arg m "$1" --arg e "$2" --arg dir "$APP" \
    --argjson ctx "$3" --argjson tok "$4" --argjson r5 "$5" --argjson r5r "$(( now + $6 ))" \
    --argjson r7 "$7" --argjson r7r "$(( now + $8 ))" --argjson cost "$9" '
    { model: { display_name: $m }, effort: { level: $e },
      context_window: { used_percentage: $ctx, total_input_tokens: $tok, context_window_size: 1000000 },
      rate_limits: { five_hour: { used_percentage: $r5, resets_at: $r5r },
                     seven_day: { used_percentage: $r7, resets_at: $r7r } },
      cost: { total_cost_usd: $cost, total_duration_ms: 2040000 },
      session_id: "demo", workspace: { current_dir: $dir } }'
}
card() {  # same args as payload; the border clock pinned to 20:14
  rm -rf "$HOME/.claude"
  payload "$@" | bash "$REPO/statusline.sh" | sed -E '1s/[0-2][0-9]:[0-5][0-9]/20:14/'
  printf '\n'
}
classic() {
  rm -rf "$HOME/.claude"
  payload "$@" | bash "$REPO/statusline-classic.sh"
  printf '\n'
}

herdr() {  # same args as payload, plus this session's lines +/-
  rm -rf "$HOME/.claude"
  payload "$@" | jq -c --arg d "$HOME/src/my-app" '.cost += {total_lines_added: 128, total_lines_removed: 43}
    | .workspace = {current_dir: $d, project_dir: $d}' | bash "$REPO/statusline-herdr.sh"
  printf '\n'
}

HERO=("Fable 5" high 12 118000 27 13260 32 367000 4.80)

# ---- page shell: a dark terminal window around a fragment --------------------
page() {  # $1 = body html file, $2 = out png, $3 = window WxH, $4 = font px
  cat > "$WORK/_page.html" <<HTML
<!doctype html><meta charset="utf-8">
<style>
  * { margin:0; padding:0; }
  body { zoom:2; background:#0d1117; height:100vh; padding-top:10px; display:flex;
         align-items:flex-start; justify-content:center; font-family:-apple-system,"Helvetica Neue",sans-serif; }
  .win { background:#161b22; border:1px solid #30363d; border-radius:14px; overflow:hidden;
         box-shadow:0 24px 70px rgba(0,0,0,.6); }
  .bar { display:flex; align-items:center; gap:8px; padding:13px 16px; background:#1c2129;
         border-bottom:1px solid #30363d; }
  .dot { width:13px; height:13px; border-radius:50%; }
  .title { flex:1; text-align:center; color:#767f8b; font-size:13px; }
  .body { padding:22px 28px; font-size:${4}px; color:#e6edf3;
          font-family:"JetBrainsMonoNL Nerd Font","JetBrainsMono Nerd Font","SF Mono",Menlo,monospace; }
  .row { white-space:nowrap; height:1.32em; line-height:1.32em; }
  .gap { height:.9em; }
  .c { display:inline-block; width:.6em; text-align:center; font-style:normal; }
  .w { width:1.2em; }
  .lbl { font-family:-apple-system,"Helvetica Neue",sans-serif; color:#586069; font-size:.5em;
         font-weight:600; letter-spacing:.1em; text-transform:uppercase; margin:0 0 6px 2px; }
  .row + .lbl { margin-top:30px; }
  .classic .row { height:auto; line-height:1.8; }
</style>
<div class="win"><div class="bar">
  <div class="dot" style="background:#ff5f57"></div>
  <div class="dot" style="background:#febc2e"></div>
  <div class="dot" style="background:#28c840"></div>
  <div class="title">claude — statusline</div>
</div><div class="body">
$(cat "$1")
</div></div>
HTML
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size="$3" --screenshot="$2" "file://$WORK/_page.html" 2>/dev/null
  python3 "$TOOLS/autocrop.py" "$2" "$2" 30
}

# ---- hero ----------------------------------------------------------------------
card "${HERO[@]}" > "$WORK/hero.ansi"
python3 "$TOOLS/ansi2html.py" --grid < "$WORK/hero.ansi" > "$WORK/hero.frag"
page "$WORK/hero.frag" "$REPO/assets/screenshot.png" "2400,700" 22

# ---- four states ---------------------------------------------------------------
{
  printf '<div class="lbl">fresh week</div>\n'
  card "Fable 5" medium 8 80000 5 16800 3 570000 0.40 | python3 "$TOOLS/ansi2html.py" --grid
  printf '<div class="lbl">cruising</div>\n'
  card "Opus 4.8" high 24 60000 41 11000 22 440000 3.20 | python3 "$TOOLS/ansi2html.py" --grid
  printf '<div class="lbl">getting warm</div>\n'
  card "Sonnet 5" medium 51 190000 58 6000 47 280000 7.10 | python3 "$TOOLS/ansi2html.py" --grid
  printf '<div class="lbl">over budget</div>\n'
  card "Haiku 4.5" low 72 320000 88 4920 76 230000 12.60 | python3 "$TOOLS/ansi2html.py" --grid
} > "$WORK/states.frag"
page "$WORK/states.frag" "$REPO/assets/states.png" "2400,2400" 18

# ---- classic one-liner -----------------------------------------------------------
{ printf '<div class="classic">'; classic "${HERO[@]}" | python3 "$TOOLS/ansi2html.py"; printf '</div>'; } > "$WORK/classic.frag"
page "$WORK/classic.frag" "$REPO/assets/classic.png" "2400,500" 20

# ---- Herdr edition ---------------------------------------------------------------
{ printf '<div class="classic">'; herdr "${HERO[@]}" | python3 "$TOOLS/ansi2html.py"; printf '</div>'; } > "$WORK/herdr.frag"
page "$WORK/herdr.frag" "$REPO/assets/herdr.png" "2400,500" 20

# ---- infographic -----------------------------------------------------------------
for v in clean linked; do
  python3 "$TOOLS/infographic.py" "$WORK/hero.ansi" $([ $v = linked ] && echo --link) > "$WORK/info.html"
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size="2800,1400" --screenshot="$WORK/info.png" "file://$WORK/info.html" 2>/dev/null
  out="$REPO/assets/infographic.png"; [ $v = clean ] && out="$REPO/assets/infographic-clean.png"
  python3 "$TOOLS/autocrop.py" "$WORK/info.png" "$out" 40
done
