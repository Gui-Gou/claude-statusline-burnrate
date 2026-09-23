#!/usr/bin/env bash
# claude-statusline-burnrate — a Claude Code status line that does the
# weekly-limit math: real rate_limits data, today's share of the week,
# sustainable burn rate, sleep-aware pacing. Every meter color-coded.
#
# Renders:  🦄 Model effort │ 🎯 wk% today%t pace%/d trend │ 🧠 ctx% +add/-rem │ 🔥 5h% reset │ pet
#   🦄/🎭/🪶/🌸 = model mascot: Fable unicorn, Opus theater, Sonnet quill, Haiku blossom
#   │        = dim group separators: model │ weekly │ session │ 5h │ pet
#   🎯 wk%   = REAL weekly plan usage, straight from rate_limits.seven_day
#   today%t  = % of TODAY'S share of the weekly glide still available. The
#             ideal burn is a line from 0% at the weekly reset to 100% at the
#             next, drawn over AWAKE hours only: "days" run day-start to
#             day-start (default 2am), and the first SL_SLEEP_HOURS after
#             day-start count for nothing (18h awake = 1 day by default).
#             Today's share = the line's rise between day-start and the coming
#             one (14.3 on a full day); %t = (line@tonight - wk%) / share.
#             100 = the whole share is ahead of you, 0 = you are exactly ON
#             tonight's checkpoint (done for today), negative red = past it,
#             eating tomorrow. Capped at 100 when running behind the line.
#             The weekly % arrives as an INTEGER (1 tick = 7 %t points), so a
#             sub-tick interpolator (see its section) smooths %t between ticks
#             using this session's live cost; re-anchored at every real tick.
#   pace%/d  = sustainable burn in weekly points: (100-wk%) / awake-days-left
#             (clamped >=1 so with <1 day left pace = all that remains). By
#             construction it is tomorrow's envelope if you stop now; constant
#             while you spend exactly at it. Fresh week = 100/7 = 14.3. One
#             decimal below 10, where rounding error starts to matter.
#   trend    = wk% vs the AWAKE-time burn target (% of the week's awake hours
#             elapsed — calendar time would fall ~3.6 pts "behind" every night
#             while asleep). Goal = land at 100% exactly when the week resets.
#             ▲+N red = ahead (will cap early), ▼-N cyan = behind (leaving
#             sub unused), ✓ = ±3.
#   🧠       = how full THIS chat's context window is (resets on /clear or compact)
#   +add/-rem= lines changed this session (.cost), shown only once edits exist
#   🔥       = REAL 5-hour plan usage + time until its reset
#   pet      = animated cat; mood = the worst of the three meters above
#
# NOTE on animation cadence: this script only runs when Claude Code re-renders
# the status line (event-driven: often while streaming, never while idle).
# Nothing here can self-animate between renders — frames advance per render.
#
# WHY read rate_limits directly: it is the true server-side plan usage. An
# earlier version estimated 5h burn with the `ccusage` npm tool against a p90
# "heavy-block" budget — a proxy that needed node + a background cache and read
# low because of outlier blocks. Once Claude Code exposed rate_limits (v2.1.x)
# that whole machinery was deleted: this script is now pure jq + awk, zero
# external deps beyond jq. Per-field gotchas are commented at their code sites.

# ---- tunables ---------------------------------------------------------------
SL_DAY_START="${SL_DAY_START:-2}"      # your "day" flips at this hour (2 = 2am)
SL_SLEEP_HOURS="${SL_SLEEP_HOURS:-6}"  # hours after day-start that count as sleep
slp=$(( SL_SLEEP_HOURS * 3600 ))       # sleep seconds per day
aday=$(( 86400 - slp ))                # awake seconds per day

input=$(cat)

# One jq pass extracts every field, joined by US (0x1f) and read with IFS=$'\x1f'.
# NOT tab: tab is IFS-whitespace, so `read` would collapse empty fields and
# misalign everything after a missing value (empty dir, or no rate_limits on older CC).
IFS=$'\x1f' read -r dir model cpct r5 r5reset r7 r7reset eff ladd lrem sid cost < <(echo "$input" | jq -r '
  [ .workspace.current_dir // .cwd // "",
    .model.display_name // "",
    (.context_window.used_percentage      // "" | tostring),
    (.rate_limits.five_hour.used_percentage // "" | tostring),
    (.rate_limits.five_hour.resets_at       // "" | tostring),
    (.rate_limits.seven_day.used_percentage // "" | tostring),
    (.rate_limits.seven_day.resets_at       // "" | tostring),
    (.effort.level // ""),
    (.cost.total_lines_added   // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    (.session_id // ""),
    (.cost.total_cost_usd // "" | tostring) ] | join("")')

# ---- Antigravity CLI (agy) fallback: quota from a cached `agy -p "/usage"` --
# agy runs this same script as its statusLine but its payload has no
# rate_limits. When they are missing and agy + python3 exist, parse agy's own
# /usage report instead. The call is slow, so it refreshes in the BACKGROUND
# at most every SL_AGY_TTL seconds; this render reads the last cached result.
# Gemini and Claude/GPT models have separate quotas: pick by model name.
AGY="${SL_AGY_BIN:-$(command -v agy 2>/dev/null || echo "$HOME/.local/bin/agy")}"
if { [ -z "$r5" ] || [ -z "$r7" ]; } && [ -x "$AGY" ] && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$HOME/.claude/.cache" 2>/dev/null
  QCACHE="$HOME/.claude/.cache/agy-quota.cache"
  now_ts=$(date +%s)
  last_mod=$(stat -f %m "$QCACHE" 2>/dev/null || stat -c %Y "$QCACHE" 2>/dev/null || echo 0)
  if [ $(( now_ts - last_mod )) -ge "${SL_AGY_TTL:-180}" ]; then
    touch "$QCACHE" 2>/dev/null  # claim this refresh: no stampede of parallel agy calls
    (
      out=$("$AGY" -p "/usage" 2>/dev/null)
      if [ -n "$out" ]; then
        python3 -c '
import sys, re, datetime
text = sys.stdin.read()
for is_gemini, tag in [(True, "gemini"), (False, "other")]:
    prefix = "Gemini Models" if is_gemini else "Claude and GPT models"
    r5 = ""; r5reset = ""; r7 = ""; r7reset = ""
    for line in text.splitlines():
        if not line.startswith(prefix): continue
        m_wk = re.search(r"Weekly Limit Remaining\s+(\d+)%\s+(\S+)", line)
        if m_wk:
            r7 = str(100 - int(m_wk.group(1)))
            r7reset = str(int(datetime.datetime.fromisoformat(m_wk.group(2).replace("Z", "+00:00")).timestamp()))
        m_5h = re.search(r"Five Hour Limit Remaining\s+(\d+)%\s+(\S+)", line)
        if m_5h:
            r5 = str(100 - int(m_5h.group(1)))
            r5reset = str(int(datetime.datetime.fromisoformat(m_5h.group(2).replace("Z", "+00:00")).timestamp()))
    print(f"{tag} {r5} {r5reset} {r7} {r7reset}")
' <<< "$out" > "$QCACHE.tmp" 2>/dev/null && mv -f "$QCACHE.tmp" "$QCACHE" 2>/dev/null
      fi
    ) >/dev/null 2>&1 &
  fi
  if [ -f "$QCACHE" ]; then
    model_type="other"
    case "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" in
      *gemini*) model_type="gemini" ;;
    esac
    while read -r tag qr5 qr5reset qr7 qr7reset; do
      if [ "$tag" = "$model_type" ]; then
        [ -z "$r5" ] && r5="$qr5"
        [ -z "$r5reset" ] && r5reset="$qr5reset"
        [ -z "$r7" ] && r7="$qr7"
        [ -z "$r7reset" ] && r7reset="$qr7reset"
      fi
    done < "$QCACHE"
  fi
fi

# agy has no .effort field: it lives in the name, e.g. "Gemini 3.8 Flash (High)"
if [ -z "$eff" ]; then
  case "$model" in
    *\(Low\)*|*\(low\)*)       eff="low" ;;
    *\(Medium\)*|*\(medium\)*) eff="medium" ;;
    *\(High\)*|*\(high\)*)     eff="high" ;;
    *\(XHigh\)*|*\(xhigh\)*|*\(Max\)*|*\(max\)*) eff="xhigh" ;;
  esac
fi
model="${model%% (*}"          # trim verbose suffixes e.g. "Opus 4.8 (1M context)" -> "Opus 4.8"

DIM=$'\e[2m'; GRN=$'\e[32m'; YEL=$'\e[33m'; ORG=$'\e[38;5;208m'; RED=$'\e[31m'; CYAN=$'\e[36m'; RST=$'\e[0m'; esc=$'\e'

# Meter icons — emoji, chosen for meaning: 🧠 context = the session's memory,
# 🔥 5h = short-term burn, 🎯 weekly plan + today's spend envelope.
# (A Nerd Font glyph experiment lost to plain emoji: zero font setup.)
I_CTX="🧠"; I_5H="🔥"; I_WK="🎯"

# ---- animation frame counter (advances once per status-line render) --------
# Drives the rainbow drift and the pet.
FRAMEF="$HOME/.claude/.cache/sl-frame"; mkdir -p "$HOME/.claude/.cache" 2>/dev/null
fn=$(cat "$FRAMEF" 2>/dev/null); case "$fn" in ''|*[!0-9]*) fn=0 ;; esac
fn=$(( fn + 1 )); printf '%s' "$fn" > "$FRAMEF" 2>/dev/null

# ---- per-model hue family + per-effort color --------------------------------
# Each model gets its own rainbow: Opus = warm reds/golds, Sonnet = blues,
# Fable = purples/magentas, Haiku = greens, Flash = electric cyan, Pro = deep royal indigo, GPT = emerald, unknown = full rainbow.
case "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" in
  *opus*)   MHUES=(196 202 208 214 220 226 214 208); memoji="🎭" ;;  # theater: the grand opus
  *sonnet*) MHUES=(21 27 33 39 45 51 45 39);         memoji="🪶" ;;  # quill: the poem
  *fable*)  MHUES=(93 99 135 141 177 201 171 135);   memoji="🦄" ;;  # unicorn: purple like its rainbow
  *haiku*)  MHUES=(22 28 34 40 46 82 118 46);        memoji="🌸" ;;  # cherry blossom
  *flash*)  MHUES=(39 45 51 81 117 123 51 45);       memoji="⚡" ;;  # lightning: Gemini Flash
  *pro*)    MHUES=(27 33 63 99 135 171 135 99);      memoji="✨" ;;  # sparkle: Gemini Pro
  *gemini*) MHUES=(27 33 39 69 75 99 135 141);       memoji="✨" ;;  # Google Gemini
  *gpt*)    MHUES=(34 40 46 82 118 82 46 40);        memoji="🪐" ;;  # GPT models
  *)        MHUES=(196 208 226 46 51 33 201 129);    memoji="🤖" ;;
esac
case "$eff" in  # effort tier gets its own color, cool -> hot
  low)       effc=$'\e[38;5;245m' ;;  # grey
  medium)    effc=$'\e[38;5;39m'  ;;  # blue
  high)      effc=$'\e[38;5;214m' ;;  # amber
  xhigh|max) effc=$'\e[38;5;196m' ;;  # red
  *)         effc="$DIM" ;;
esac

rainbow() {  # color each char of $1 with the model's hue family, drifting per frame
  local s="$1" o="" i h n=${#MHUES[@]}
  for (( i=0; i<${#s}; i++ )); do
    h=${MHUES[$(( (i + fn) % n ))]}
    o="${o}${esc}[38;5;${h}m${s:$i:1}"
  done
  printf '%s%s' "$o" "$RST"
}

ctxcol() {  # context %: green<20, yellow<40, orange<60, red>=60
  if   [ "$1" -ge 60 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 40 ]; then printf '%s' "$ORG"
  elif [ "$1" -ge 20 ]; then printf '%s' "$YEL"
  else                       printf '%s' "$GRN"; fi
}
plancol() { # 5h & weekly plan %: green<30, yellow<50, orange<70, red>=70
  if   [ "$1" -ge 70 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 50 ]; then printf '%s' "$ORG"
  elif [ "$1" -ge 30 ]; then printf '%s' "$YEL"
  else                       printf '%s' "$GRN"; fi
}
todaycol() { # today's envelope: the displayed value IS the fraction of today's
  # allowance still unspent (100 -> 0), so color thresholds read off it directly.
  if   [ "$1" -ge 50 ]; then printf '%s' "$GRN"   # most of today still ahead
  elif [ "$1" -ge 25 ]; then printf '%s' "$YEL"   # over half spent
  elif [ "$1" -ge 10 ]; then printf '%s' "$ORG"   # nearly tapped
  else                       printf '%s' "$RED"; fi # envelope spent/overdrawn
}
pacecol() { # sustainable %/day vs the ~14%/day even-burn baseline (100%÷7d).
  # Higher pace = more runway left per day = cooler; a low pace means you've
  # overspent and are forced to slow down, so it warms toward red.
  if   [ "$1" -ge 12 ]; then printf '%s' "$GRN"   # at/above even burn: healthy
  elif [ "$1" -ge 8  ]; then printf '%s' "$YEL"   # rationing needed
  elif [ "$1" -ge 5  ]; then printf '%s' "$ORG"   # tight
  else                       printf '%s' "$RED"; fi # forced hard slowdown
}
reset_str() {  # unix ts -> "1h41m" / "12m" time remaining
  [ -z "$1" ] && return
  rem=$(( ($1 - $(date +%s)) / 60 )); [ "$rem" -lt 0 ] && rem=0
  if [ "$rem" -ge 60 ]; then printf '%dh%dm' "$(( rem/60 ))" "$(( rem%60 ))"; else printf '%dm' "$rem"; fi
}

# ---- context % ------------------------------------------------------------
ctx=""
if [ -n "$cpct" ]; then
  p=$(printf '%.0f' "$cpct")
  ctx="$(ctxcol "$p")${I_CTX} ${p}%${RST}"
fi

# ---- 5-hour plan usage (real, from rate_limits) ---------------------------
burn=""
if [ -n "$r5" ]; then
  p5=$(printf '%.0f' "$r5")
  burn="$(plancol "$p5")${I_5H} ${p5}%${RST}"
  rs=$(reset_str "$r5reset"); [ -n "$rs" ] && burn="${burn} ${DIM}${rs}${RST}"
fi

# ---- sub-tick interpolation for the weekly % -------------------------------
# The payload's weekly used% is an INTEGER, so %t would only move in 7-point
# jumps (1 wk-pt = 7% of a 14.3-pt daily share). Between ticks, estimate the
# fraction of the next point already burned from THIS session's live cost
# (total_cost_usd, penny precision), divided by a dollars-per-weekly-point
# rate that self-calibrates: each tick landing inside one session yields a
# measured $-delta sample, folded in by EMA (seeded $4.50, clamped 1..20).
# Anchored to ground truth at EVERY tick, so drift is bounded by one point.
# Blind spots (parallel sessions, other machines, claude.ai) only make it
# UNDER-estimate — shows a touch more left than reality until the next tick.
# A session switch just re-anchors (frac restarts at 0: graceful degradation
# back to integer steps, never wrong direction).
frac=0
TICKF="$HOME/.claude/.cache/sl-tick"
if [ -n "$r7" ] && [ -n "$sid" ] && [ -n "$cost" ]; then
  tu=""; tsid=""; tc=""; tk=""
  read -r tu tsid tc tk 2>/dev/null < "$TICKF"
  tick=$(awk -v u="$r7" -v c="$cost" -v sid="$sid" -v tu="$tu" -v tsid="$tsid" -v tc="$tc" -v tk="$tk" 'BEGIN{
    k = tk+0; if (k < 1 || k > 20) k = 4.5
    if (tu == "" || u+0 != tu+0 || sid != tsid) {
      # tick / first run / weekly reset / session switch: re-anchor here.
      # Calibrate only on a clean +1 tick within one session, sane $ range.
      if (tsid == sid && u+0 == tu+1 && c-tc > 0.5 && c-tc < 40) k = 0.5*k + 0.5*(c-tc)
      printf "ANCHOR %s %s %.4f %.2f", u, sid, c, k
    } else {
      f = (c - tc) / k; if (f < 0) f = 0; if (f > 0.95) f = 0.95
      printf "FRAC %.3f", f
    }
  }' 2>/dev/null)
  case "$tick" in
    ANCHOR\ *) printf '%s' "${tick#ANCHOR }" > "$TICKF" 2>/dev/null ;;
    FRAC\ *)   frac="${tick#FRAC }" ;;
  esac
fi

# ---- weekly (7-day) plan: used% + today's glide gauge + pace + trend -------
# Awake-time model: the day runs day-start->day-start and the first
# SL_SLEEP_HOURS after day-start are sleep, so ALL the budget math counts
# AWAKE seconds only. awake(a,b) walks day by day; sleep = the first `slp`
# seconds of each such day.
# Today gauge %t: the ideal burn is a LINE over the week's awake hours, 0% at
# the last reset -> 100% at the next (a reset that lands inside sleep => the
# line really ends at the surrounding day-start). Tonight's checkpoint = the
# line's value at the coming day-start; today's share = its rise since the
# last one (14.3 on a full day).
#   %t = (checkpoint - used) / share * 100
# 100 = the whole share ahead, 0 = exactly ON tonight's checkpoint, negative
# red = past it (eating tomorrow); capped at 100 when behind the line.
# Everything derives from the live payload: no cache, no day-start snapshot,
# so every machine shows the identical number.
# pace = (100-used) / awake-days-left = sustainable %/day from this moment
# (clamped >=1 day: with <1 day left, spendable = all that remains).
# trend = used% minus the same line at NOW: ahead/behind in weekly points.
# Positive = burning faster than the even awake-glide (caps early);
# negative = slower (would end the week with unused credits).
week=""; today=""; pace=""; trend=""
if [ -n "$r7" ]; then
  p7=$(printf '%.0f' "$r7")
  week="$(plancol "$p7")${I_WK} ${p7}%${RST}"
  if [ -n "$r7reset" ]; then
    now=$(date +%s)
    # anchor = today's day-start local (only matters mod 24h); BSD date first,
    # GNU date fallback.
    anchor=$(date -v"${SL_DAY_START}"H -v0M -v0S +%s 2>/dev/null || date -d "${SL_DAY_START}:00" +%s 2>/dev/null)
    # start of the current day (anchor is today-calendar day-start, which
    # before day-start lies in the future -> step back one day)
    ds=$anchor; [ "$now" -lt "$anchor" ] 2>/dev/null && ds=$(( anchor - 86400 ))
    tv=$(awk -v used="$r7" -v fr="$frac" -v ds="$ds" -v reset="$r7reset" -v now="$now" -v A="$anchor" -v slp="$slp" -v aday="$aday" '
      function awake(a, b,   s, t, x, de, se, as) {  # awake seconds in [a,b)
        s = 0; t = a
        while (t < b) {
          x = (t - A) % 86400; if (x < 0) x += 86400  # position in the day
          de = t + (86400 - x)                        # next day-start
          se = (b < de) ? b : de                      # end of this segment
          as = t + ((x < slp) ? slp - x : 0)          # asleep? skip to wake
          if (as < se) s += se - as
          t = de
        }
        return s
      }
      BEGIN{
        if (reset <= now || A <= 0) exit 1
        rem = 100 - used; if (rem < 0) rem = 0
        d = awake(now, reset) / aday; if (d < 1) d = 1  # awake-days left
        pr = rem / d
        pv = (pr < 10) ? sprintf("%.1f", pr) : sprintf("%.0f", pr)
        # the even-burn line: % of the weeks awake hours elapsed by time t
        ws = reset - 604800
        aw = awake(ws, reset)
        if (aw <= 0) exit 1
        fv = "NA"
        de = ds + 86400; if (de > reset) de = reset   # day ends: next day-start/reset
        d0 = ds; if (d0 < ws) d0 = ws                 # day start clamped to week
        ckpt  = awake(ws, de) / aw * 100              # the line at tonight
        share = ckpt - awake(ws, d0) / aw * 100       # todays slice of the line
        if (share > 0.1) {
          # used + fr: integer weekly % plus the sub-tick interpolation, so
          # %t moves ~1 point per ~$0.65 instead of 7-point jumps per tick
          f = (ckpt - (used + fr)) / share * 100
          if (f > 100) f = 100                        # behind the line: capped
          fv = sprintf("%.0f", f)
        }
        # trend: same line evaluated at NOW (awake-aware — calendar time would
        # fall ~3.6 pts "behind" every night while asleep)
        e = awake(ws, now) / aw * 100
        if (e < 0) e = 0; if (e > 100) e = 100
        dfv = sprintf("%.0f", used - e)
        print fv, pv, dfv
      }' 2>/dev/null)
    df=""
    if [ -n "$tv" ]; then
      read -r tfrac pv df <<< "$tv"
      [ "$tfrac" != "NA" ] && today="$(todaycol "$tfrac")${tfrac}%t${RST}"
      # pacecol needs an integer: strip any decimal before comparing
      case "$pv" in *[0-9]*) pace="$(pacecol "${pv%.*}")${pv}%/d${RST}" ;; esac
    fi
    case "$df" in ''|*[!0-9-]*) df="" ;; esac
    if [ -n "$df" ]; then
      if   [ "$df" -ge 3 ];  then trend="${RED}▲+${df}${RST}"   # overspending
      elif [ "$df" -le -3 ]; then trend="${CYAN}▼${df}${RST}"   # underspending
      else                        trend="${GRN}✓${RST}"          # on track ±3
      fi
    fi
  fi
fi

# ---- lines changed this session (only if there were edits) ----------------
lines=""
if [ "${ladd:-0}" -gt 0 ] 2>/dev/null || [ "${lrem:-0}" -gt 0 ] 2>/dev/null; then
  lines="${GRN}+${ladd}${RST}/${RED}-${lrem}${RST}"
fi

# ---- companion pet (animated; reacts to the worst meter) ------------------
# Frames advance once per status-line render, so the pet is lively while Claude
# is working and rests when idle. Mood = worst of context / 5h / weekly usage.
pet=""; stress=0
for v in "$p" "$p5" "$p7"; do
  case "$v" in ''|*[!0-9]*) : ;; *) [ "$v" -gt "$stress" ] && stress="$v" ;; esac
done
# 8 frames; the face itself animates (blinks / changes) and the effect char is
# always present, so every single render visibly moves.
i=$(( fn % 8 ))
if   [ "$stress" -ge 70 ]; then                                    # panic
  faces=("😾" "🙀" "😾" "😿" "😾" "🙀" "😾" "🙀"); a=("🔥" "💢" "💥" "🔥" "💢" "💥" "🔥" "💢")
elif [ "$stress" -ge 50 ]; then                                    # nervous
  faces=("🙀" "😿" "🙀" "😿" "🙀" "😾" "🙀" "😿"); a=("💦" "°" "💦" "∘" "💦" "°" "💦" "∘")
elif [ "$stress" -ge 30 ]; then                                    # alert
  faces=("😼" "🐱" "😼" "😽" "😼" "🐱" "😼" "🐱"); a=("·" "‥" "…" "‥" "·" "‥" "…" "‥")
else                                                                # happy
  faces=("😺" "😸" "😺" "😹" "😺" "😸" "😻" "😸"); a=("♪" "♫" "♬" "♪" "♫" "♬" "♫" "♪")
fi
pet="${faces[$i]}${DIM}${a[$i]}${RST}"

# ---- assemble: logical groups joined by dim │ separators -------------------
#   🦄 Model effort │ 🎯 wk today pace trend │ 🧠 ctx +/-lines │ 🔥 5h reset │ pet
# Group 1 = model, 2 = weekly plan, 3 = this session, 4 = 5h window.
# Empty groups vanish along with their separator, so the line never shows a
# dangling │ when a data source is missing (old CC version, no edits yet...).
SEP=" ${DIM}│${RST} "
g1=""
[ -n "$model" ] && g1="${memoji} $(rainbow "$model")${eff:+ ${effc}${eff}${RST}}"
g2="${week}"
[ -n "$today" ] && g2="${g2:+${g2} }${today}"
[ -n "$pace" ]  && g2="${g2:+${g2} }${pace}"
[ -n "$trend" ] && g2="${g2:+${g2} }${trend}"
g3="${ctx}"
[ -n "$lines" ] && g3="${g3:+${g3} }${lines}"
g4="${burn}"
out=""
for g in "$g1" "$g2" "$g3" "$g4" "$pet"; do
  [ -n "$g" ] && out="${out:+${out}${SEP}}${g}"
done
printf '%s' "$out"
