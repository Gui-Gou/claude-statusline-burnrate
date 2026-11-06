#!/usr/bin/env bash
# Preview the status line without touching your real quota or cache.
# Usage:  ./demo.sh             four moods, card edition
#         ./demo.sh --classic   the same four moods, one-line v1
#         ./demo.sh --herdr     the same four moods, Herdr edition
#         ./demo.sh --live      animated tour: meters sweep, models cycle
#                               (add --classic or --herdr; ctrl-c stops)
set -euo pipefail
cd "$(dirname "$0")"

SCRIPT="$PWD/statusline.sh"; LIVE=0
for a in "$@"; do
  case "$a" in
    --classic) SCRIPT="$PWD/statusline-classic.sh" ;;
    --herdr)   SCRIPT="$PWD/statusline-herdr.sh" ;;
    --live)    LIVE=1 ;;
  esac
done

export HOME="$(mktemp -d)"   # keep demo cache away from your real ~/.claude
export SL_STATUS=0           # no network calls from a demo
now=$(date +%s)

# a throwaway repo, last commit 12 minutes ago, for the ⌚ ⌂ cell
APP="$HOME/my-app"; mkdir -p "$APP"
git -C "$APP" init -q 2>/dev/null && \
  GIT_COMMITTER_DATE="@$(( now - 720 ))" git -C "$APP" -c user.name=demo -c user.email=demo@example.com \
    commit -q --allow-empty -m demo 2>/dev/null || true

payload() {  # model effort ctx% 5h% wk% cost [ctx-tokens] [5h-reset-in] [wk-reset-in]
  jq -n --arg m "$1" --arg e "$2" --arg dir "${CUR:-$APP}" --arg proj "$APP" \
        --argjson ctx "$3" --argjson r5 "$4" --argjson r7 "$5" --argjson cost "$6" \
        --argjson tok "${7:-60000}" \
        --argjson r5r "$(( now + ${8:-4920} ))" --argjson r7r "$(( now + ${9:-302400} ))" '
    { model: { display_name: $m },
      effort: { level: $e },
      context_window: { used_percentage: $ctx, total_input_tokens: $tok,
                        context_window_size: 1000000 },
      rate_limits: { five_hour: { used_percentage: $r5, resets_at: $r5r },
                     seven_day: { used_percentage: $r7, resets_at: $r7r } },
      cost: { total_cost_usd: $cost, total_duration_ms: 2040000,
              total_lines_added: 128, total_lines_removed: 43 },
      session_id: "demo", workspace: { current_dir: $dir, project_dir: $proj } }'
}

render() { payload "$@" | bash "$SCRIPT"; printf '\n'; }

if [ "$LIVE" = 1 ]; then
  MODELS=("Fable 5" "Opus 4.8" "Sonnet 5" "Haiku 4.5"); EFFORTS=(low medium high xhigh)
  printf '\e[?25l'; trap 'printf "\e[?25h\n"' EXIT
  rows=0; f=0
  while :; do
    # one slow sweep of every meter, offset so they never move in lockstep
    t=$(( f % 100 ))
    out=$(payload "${MODELS[$(( f / 25 % 4 ))]}" "${EFFORTS[$(( f / 10 % 4 ))]}" \
            $(( (t * 2 + 10) % 101 )) $(( (t * 3 + 55) % 101 )) "$t" 3.20 \
            $(( (f * 3400) % 340000 )) | bash "$SCRIPT")
    [ "$rows" -gt 1 ] && printf '\e[%dA' $(( rows - 1 ))
    printf '\r'
    while IFS= read -r line; do printf '\e[2K%s\n' "$line"; done <<<"$out"
    rows=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    printf '\e[1A'
    f=$(( f + 1 )); sleep 0.2
  done
fi

echo "fresh week, all quiet:"
render "Fable 5" medium 8 5 3 0.40 20000 16800 570000
echo
echo "cruising:"
render "Opus 4.8" high 24 41 22 3.20 60000 11000 440000
echo
echo "getting warm:"
render "Sonnet 5" medium 51 58 47 7.10 190000 6000 280000
echo
echo "over budget:"
render "Haiku 4.5" low 72 88 76 12.60 320000 4920 230000

if [ "$SCRIPT" = "$PWD/statusline-herdr.sh" ]; then
  # the folder segment: started in my-app, then Claude moved with cd
  mkdir -p "$HOME/notes" "$HOME/other-repo"; git -C "$HOME/other-repo" init -q 2>/dev/null || true
  echo; echo "drifted out of the launch folder (amber):"
  CUR="$HOME/notes" render "Opus 4.8" high 24 41 22 3.20 60000
  echo; echo "working in another repo (red):"
  CUR="$HOME/other-repo" render "Opus 4.8" high 24 41 22 3.20 60000
fi
