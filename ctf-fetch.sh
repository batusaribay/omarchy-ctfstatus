#!/usr/bin/env bash
set -euo pipefail
umask 077

# Usage: ctf-fetch.sh <htbId|ProfileUrl> <thmUsername> <cylabUsername> <wantHtb 0|1> <wantThm 0|1> <wantCylab 0|1> <force 0|1>
htb_user="${1:-}"
thm_username="${2:-}"
cylab_username="${3:-}"
want_htb="${4:-1}"
want_thm="${5:-1}"
want_cylab="${6:-1}"
force="${7:-0}"

UA="omarchy-ctfstatus/0.5.0 (+https://omarchy.org)"
HTB_API="https://labs.hackthebox.com/api/v4"
CYLAB_API="https://learn.cylabacademy.org/api"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-ctfstatus"
CACHE_FILE="$CACHE_DIR/status.json"
TTL="${CTFSTATUS_TTL:-300}"

mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit() { printf '%s' "$1"; exit 0; }

# Serve a recent cache without touching the network unless the user forced a
# refresh. Keeps shell restarts cheap and keeps us clear of rate limits.
if [[ "$force" != "1" && -f "$CACHE_FILE" && "$TTL" =~ ^[0-9]+$ ]]; then
  age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if (( age < TTL )); then
    if cached="$(jq -c 'if .ok then . else empty end' "$CACHE_FILE" 2>/dev/null)" && [[ -n "$cached" ]]; then
      emit "$cached"
    fi
  fi
fi

# Previous snapshot, reused per-provider when a fetch fails.
prev="{}"
if [[ -f "$CACHE_FILE" ]]; then
  if cached="$(jq -c . "$CACHE_FILE" 2>/dev/null)"; then
    prev="$cached"
  fi
fi

htb_curl() {
  curl -sSL \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 \
    --max-time 20 --retry 2 --retry-delay 1 --retry-connrefused \
    -A "$UA" -H 'Accept: application/json' "$@"
}

cylab_curl() {
  curl -sSL \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 \
    --max-time 20 --retry 2 --retry-delay 1 --retry-connrefused \
    -A "$UA" -H 'Accept: application/json' "$@"
}

# HTB's public labs profile endpoint is keyed by numeric id. Accept a plain
# number or a profile URL such as https://app.hackthebox.com/users/123456.
parse_htb_id() {
  local needle="$1" m digits
  if [[ "$needle" =~ ^[0-9]+$ ]]; then
    printf '%s' "$needle"
    return 0
  fi
  m="$(printf '%s' "$needle" | grep -oE 'users/[0-9]+' | tail -n1 || true)"
  if [[ -n "$m" ]]; then
    digits="${m##*/}"
    if [[ -n "$digits" ]]; then
      printf '%s' "$digits"
      return 0
    fi
  fi
  digits="$(printf '%s' "$needle" | grep -oE '[0-9]{4,}' | tail -n1 || true)"
  if [[ -n "$digits" ]]; then
    printf '%s' "$digits"
    return 0
  fi
  return 1
}

THM_API="https://tryhackme.com/api/v2/public-profile"

# TryHackMe's edge sometimes routes everything through a no-JS-access API
# challenge. Plain curl gets a 429 then; a headless browser solves it once and
# keeps its cookies in the cache dir, making later refreshes cheap.
pick_thm_browser() {
  if [[ -n "${CTFSTATUS_THM_BROWSER:-}" ]]; then
    printf '%s' "$CTFSTATUS_THM_BROWSER"
    return 0
  fi
  for b in chromium google-chrome-stable chromium-browser chrome; do
    if command -v "$b" >/dev/null 2>&1; then
      printf '%s' "$b"
      return 0
    fi
  done
  return 1
}

fetch_thm() {
  curl -fsSL \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 \
    --max-time 20 --retry 2 --retry-delay 1 --retry-connrefused \
    -A "$UA" -H 'Accept: application/json' \
    --get --data-urlencode "username=${thm_username}" \
    "$THM_API"
}

fetch_thm_js() {
  local browser url out
  browser="$(pick_thm_browser)" || return 1
  url="$THM_API?username=$(printf '%s' "$thm_username" | jq -Rr '@uri')"
  out="$(timeout "${CTFSTATUS_BROWSER_TIMEOUT:-45}" \
    "$browser" --headless=new --disable-gpu \
    --user-data-dir="$CACHE_DIR/thm-chrome" \
    --no-first-run --no-default-browser-check --disable-extensions \
    --disable-sync --disable-default-apps --disable-background-networking \
    --disable-component-update --disable-breakpad \
    --disable-client-side-phishing-detection --disable-domain-reliability \
    --virtual-time-budget=8000 --dump-dom "$url" 2>/dev/null \
    | sed -n 's/.*<pre>\(.*\)<\/pre>.*/\1/p' \
    | sed -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#39;/'/g")"
  chmod -R go-rwx "$CACHE_DIR/thm-chrome" 2>/dev/null || true
  printf '%s' "$out"
}

NORM_HTB='def num: if type=="number" then . elif type=="string" then (tonumber? // 0) else 0 end;
def str: if .==null then "" else tostring end;
.profile | {
  username: (.name|str),
  rank: (.rank|str),
  ranking: ((.ranking // 0)|num),
  points: ((.points // 0)|num),
  userOwns: ((.user_owns // 0)|num),
  systemOwns: ((.system_owns // 0)|num)
}'

NORM_THM='def num: if type=="number" then . elif type=="string" then (tonumber? // 0) else 0 end;
def str: if .==null then "" else tostring end;
select(.status == "success" and (.data != null)) | .data | {
  username: (.username|str),
  level: ((.level // 0)|num),
  rank: (.rank|str),
  topPercentage: ((.topPercentage // 0)|num),
  points: ((.totalPoints // 0)|num),
  badges: ((.badgesNumber // 0)|num),
  rooms: ((.completedRoomsNumber // 0)|num),
  streak: ((.streak // 0)|num),
  maxStreak: ((.largestStreak // 0)|num)
}'

NORM_CYLAB='def num: if type=="number" then . elif type=="string" then (tonumber? // 0) else 0 end;
def str: if .==null then "" else tostring end;
{
  username: (.profile.username|str),
  solved: ((.gym.overall.solved // 0)|num),
  available: ((.gym.overall.available // 0)|num),
  easySolved: ((.gym.by_difficulty["1"].solved // 0)|num),
  easyTotal: ((.gym.by_difficulty["1"].available // 0)|num),
  mediumSolved: ((.gym.by_difficulty["2"].solved // 0)|num),
  mediumTotal: ((.gym.by_difficulty["2"].available // 0)|num),
  hardSolved: ((.gym.by_difficulty["3"].solved // 0)|num),
  hardTotal: ((.gym.by_difficulty["3"].available // 0)|num),
  playlists: ((.profile.completed_playlists // 0)|length)
}'

# ---------------------------------------------------------------- Hack The Box
htb_status="missing"; htb_data="null"; htb_error=""
if [[ "$want_htb" == "1" && -n "$htb_user" ]]; then
  if htb_id="$(parse_htb_id "$htb_user")" && [[ -n "$htb_id" ]]; then
    raw="$(htb_curl "$HTB_API/profile/$htb_id" 2>/dev/null || true)"
    if [[ -z "$raw" ]]; then
      htb_status="error"; htb_error="HTB is unreachable"
    elif message="$(printf '%s' "$raw" | jq -r '(.message // "" | tostring)' 2>/dev/null)" && [[ -n "$message" && "$message" != "null" ]]; then
      htb_status="error"; htb_error="$message — check the id and enable the public profile in your HTB Labs settings"
    elif data="$(printf '%s' "$raw" | jq -c "$NORM_HTB" 2>/dev/null)" && [[ -n "$data" && "$data" != "null" ]]; then
      htb_status="fresh"; htb_data="$data"
    else
      htb_status="error"; htb_error="could not read the profile"
    fi
  else
    htb_status="error"; htb_error="enter your numeric HTB profile id"
  fi
fi
if [[ "$htb_status" == "error" ]]; then
  fallback="$(printf '%s' "$prev" | jq -c '.htb' 2>/dev/null || true)"
  if [[ -n "$fallback" && "$fallback" != "null" ]]; then
    htb_status="stale"; htb_data="$fallback"; htb_error="offline — showing last saved"
  fi
fi

# ---------------------------------------------------------------- TryHackMe
thm_status="missing"; thm_data="null"; thm_error=""
if [[ "$want_thm" == "1" && -n "$thm_username" ]]; then
  raw="$(fetch_thm 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    raw="$(fetch_thm_js 2>/dev/null || true)"
  fi
  if data="$(printf '%s' "$raw" | jq -c "$NORM_THM" 2>/dev/null)" && [[ -n "$data" && "$data" != "null" ]]; then
    thm_status="fresh"; thm_data="$data"
  else
    thm_status="error"; thm_error="unreachable or unknown user"
  fi
fi
if [[ "$thm_status" == "error" ]]; then
  fallback="$(printf '%s' "$prev" | jq -c '.thm' 2>/dev/null || true)"
  if [[ -n "$fallback" && "$fallback" != "null" ]]; then
    thm_status="stale"; thm_data="$fallback"; thm_error="offline — showing last saved"
  fi
fi

# ------------------------------------------------------- CyLab Security Academy
# CyLab (the successor to picoCTF) exposes a public profile keyed by username and
# a challenge ("gym") breakdown keyed by the numeric id from that profile.
cylab_status="missing"; cylab_data="null"; cylab_error=""
if [[ "$want_cylab" == "1" && -n "$cylab_username" ]]; then
  prof="$(cylab_curl "$CYLAB_API/users/$(printf '%s' "$cylab_username" | jq -Rr '@uri')/" 2>/dev/null || true)"
  if [[ -z "$prof" ]]; then
    cylab_status="error"; cylab_error="CyLab is unreachable"
  elif [[ "$(printf '%s' "$prof" | jq -r 'has("detail")' 2>/dev/null)" == "true" ]]; then
    cylab_status="error"; cylab_error="unknown user — check the username"
  elif [[ "$(printf '%s' "$prof" | jq -r '.is_private' 2>/dev/null)" == "true" ]]; then
    cylab_status="error"; cylab_error="this profile is private"
  else
    uid="$(printf '%s' "$prof" | jq -r '(.id // "")|tostring' 2>/dev/null)"
    gym="$(cylab_curl "$CYLAB_API/users/${uid}/gym_stats/" 2>/dev/null || true)"
    [[ -z "$gym" || "$gym" == "null" ]] && gym="{}"
    if data="$(jq -cn --argjson p "$prof" --argjson g "$gym" '{profile:$p, gym:$g}' | jq -c "$NORM_CYLAB" 2>/dev/null)" && [[ -n "$data" && "$data" != "null" ]]; then
      cylab_status="fresh"; cylab_data="$data"
    else
      cylab_status="error"; cylab_error="could not read the profile"
    fi
  fi
fi
if [[ "$cylab_status" == "error" ]]; then
  fallback="$(printf '%s' "$prev" | jq -c '.cylab' 2>/dev/null || true)"
  if [[ -n "$fallback" && "$fallback" != "null" ]]; then
    cylab_status="stale"; cylab_data="$fallback"; cylab_error="offline — showing last saved"
  fi
fi

provider_obj() {
  local status="$1" data="$2" err="$3" empty="$4"
  case "$status" in
    fresh)
      jq -cn --argjson d "$data" '$d + {ok:true, stale:false, error:""}'
      ;;
    stale)
      jq -cn --argjson d "$data" --arg e "$err" '$d + {ok:false, stale:true, error:$e}'
      ;;
    error)
      jq -cn --arg e "$err" --argjson empty "$empty" '$empty + {ok:false, stale:false, error:$e}'
      ;;
    *)
      printf '%s' 'null'
      ;;
  esac
}

htb_obj="$(provider_obj "$htb_status" "$htb_data" "$htb_error" \
  '{"username":"","rank":"","ranking":0,"points":0,"userOwns":0,"systemOwns":0}')"
thm_obj="$(provider_obj "$thm_status" "$thm_data" "$thm_error" \
  '{"username":"","level":0,"rank":"","topPercentage":0,"points":0,"badges":0,"rooms":0,"streak":0,"maxStreak":0}')"
cylab_obj="$(provider_obj "$cylab_status" "$cylab_data" "$cylab_error" \
  '{"username":"","solved":0,"available":0,"easySolved":0,"easyTotal":0,"mediumSolved":0,"mediumTotal":0,"hardSolved":0,"hardTotal":0,"playlists":0}')"

result="$(jq -cn \
  --arg now "$now" \
  --argjson htb "$htb_obj" \
  --argjson thm "$thm_obj" \
  --argjson cylab "$cylab_obj" \
  '{
    ok: (($htb != null and $htb.ok) or ($thm != null and $thm.ok) or ($cylab != null and $cylab.ok)),
    stale: (($htb != null and $htb.stale) or ($thm != null and $thm.stale) or ($cylab != null and $cylab.stale)),
    source: "CTF Status",
    updated: $now,
    htb: $htb,
    thm: $thm,
    cylab: $cylab
  }')"

if [[ "$(printf '%s' "$result" | jq -r '.ok')" == "true" ]]; then
  tmp="$CACHE_FILE.$$.tmp"
  if printf '%s' "$result" > "$tmp"; then
    mv -f "$tmp" "$CACHE_FILE"
  else
    rm -f "$tmp"
  fi
fi

emit "$result"
