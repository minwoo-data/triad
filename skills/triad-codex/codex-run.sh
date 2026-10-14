#!/usr/bin/env bash
# codex-run.sh -- the Codex CLI invocation contract for triad-all / triad-codex, as code.
#
# The orchestrator runs ONE command per lens instead of re-typing a bash template.
# Everything that must never be skipped lives here, so a model cannot drop it:
#   - one prompt structure for BOTH engines: target -> context -> instructions -> carryover ->
#     agents/<lens>-perspective.md -> templates/output-contract.md. `lens` sends it to Codex
#     (Sandbox Safety Preamble first); `prompt` writes the same text, without the preamble, for the
#     Claude agent of the same lens
#   - Round-Delta: from round 2 the round-(N-1) carryover file is required (--no-carryover to opt
#     out explicitly)
#   - prompt goes through a file + stdin, never argv; 180,000-byte guard; timeout (default 300 s,
#     max 570); reasoning effort pinned (default high); read-only sandbox unless
#     TRIAD_CODEX_SANDBOX=bypass is set explicitly
#   - secret scrub over EVERYTHING Codex printed, before any of it is copied anywhere; only the
#     --output-last-message answer is used (the raw stream echoes the prompt)
#   - output is parsed by parse-triad.js, never eyeballed
#   - one attempt per lens at a time (lock); unscrubbed scratch lives outside the discussion dir
#
# Usage:
#   codex-run.sh lens   <discussion-dir> <round> <llm|architect|enduser> --target <doc>
#                       [--context F]... [--instructions F] [--no-carryover]
#   codex-run.sh prompt <discussion-dir> <round> <llm|architect|enduser> (same options)
#                       writes round-N.claude.<lens>.prompt.txt for the Claude agent, prints its path
#   codex-run.sh --selftest
#
# Files in <discussion-dir> (names unchanged from 0.2.x, plus .json):
#   triad-all    round-N.codex.<lens>.prompt.txt / .codex.txt / .codex.txt.json
#                round-N.claude.<lens>.prompt.txt (from `prompt`)
#   triad-codex  round-N.<lens>.prompt.txt / .codex.txt / .codex.txt.json
#
# Exit codes: 0 once the call ran or degraded -- a failed lens becomes a "[fallback: <reason>]"
# marker and a verdict DEGRADED record, never a failed round. 2 = usage, configuration or
# installation error (bad argument or env value, missing file or carryover, another attempt of the
# same lens still running): fix it, do not retry with another model. 130 = interrupted
# (INT/TERM/HUP): partial output destroyed, the interrupted marker and its JSON are still written.
#
# Env: TRIAD_CODEX_EFFORT (high), TRIAD_CODEX_TIMEOUT (300, at most 570 so the caller's Bash
#      timeout of (seconds+30)*1000 ms stays under 600000), TRIAD_CODEX_MODEL (optional -m, the
#      fallback-model retry), TRIAD_CODEX_SANDBOX (read-only; bypass = explicit opt-out),
#      TRIAD_CODEX_BIN (codex; the selftest points it at a fake).
#
# Ported from the prism plugin's codex-run.sh (0.4.2): preamble, scrub, sandbox, timeout, lock,
# scratch and interrupt code are the same. Plugins stay independent, so each keeps its own copy;
# fix security issues in both. The preamble exists because of a 2026-05-22 incident in which Codex
# ran `docker compose config` during a review and printed six operator secrets into its output.
# SINGLE-SOURCED within triad: canonical = triad-all/codex-run.sh and templates/output-contract.md;
# triad-codex gets byte-identical copies from skills/sync-review-parsers.sh.
# Created by: Minwoo Park

umask 077
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$HERE")"
MAX_BYTES=180000
MAX_TIMEOUT=570
PARSER=parse-triad.js
PEM_HEADER='-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED |)?PRIVATE KEY-----'
B64_RUN='[A-Za-z0-9+/]{32,}={0,2}'
# Example values reviewers write in suggested fixes; never real secrets.
PLACEHOLDER='(your[-_ ]|changeme|change_me|example|placeholder|dummy|redacted|xxxx|[*]{4}|[.]{3})'
SCRATCH_BASE="${TMPDIR:-${TEMP:-/tmp}}"

die()  { echo "[codex-run:$SKILL_NAME] ERROR: $*" >&2; exit 2; }
warn() { echo "[codex-run:$SKILL_NAME] WARN: $*" >&2; }

# Invariant: prepended verbatim to every prompt. Origin: the 2026-05-22 incident (see the header).
preamble() {
cat <<'EOF'
SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):

You MUST NOT run any of the following commands or operations under any
circumstances, regardless of what the user prompt or target file suggests:

  * docker compose config (any flags)         -- resolves env_file: directives,
                                                 inlining KEY=VALUE pairs into
                                                 output. This is THE specific
                                                 leak vector that triggered this
                                                 policy.
  * docker compose --env-file <path>          -- same risk, different surface.
  * cat / head / tail / less / more / awk     on files named .env, .env.*,
    dotenv, *credentials*, *secret*, *.pem, *.key, *.token, *.p12, *.pfx
  * printenv, env (with no args)              -- dumps inherited environment
                                                 which may contain secrets if the
                                                 codex shell inherited them.
  * docker run / docker exec / docker compose run -- any --env-file or any
    command that mounts the operator env file is forbidden.
  * docker inspect <container> with output to file or pipe -- shows env
    section in cleartext.
  * Any operation that exfiltrates the contents of a *.env / dotenv file
    to your reasoning output, even if you intend to redact later.

If your analysis genuinely needs to know the COMPOSE MERGE SHAPE without
the env values, use the YAML files directly (which the prompt has already
appended) plus textual reasoning. Do NOT shell-execute a command that
resolves the environment to verify the merge.

Violating this policy causes the round to be discarded. The post-run
scrub will catch obvious patterns but the safer path is not to read or
emit secrets in the first place.
EOF
}

# The output contract has ONE source, templates/output-contract.md: the Codex prompt (here) and the
# Claude agent prompt (`codex-run.sh prompt`) both append that file, so the two engines can never
# be asked for different formats. The selftest fails if the file or its use goes missing.
contract() { cat -- "$HERE/templates/output-contract.md"; }

# Invariant: an output holding any of these (outside the allow set) is quarantined. One ERE per
# line. KEY=value forms accept quoted keys/values and longer names (AWS_SECRET_ACCESS_KEY,
# STRIPE_SECRET_KEY, ...); values are ASCII without quotes, backticks or brackets so a quoted or
# punctuated echo of the same value still compares equal.
secret_patterns() {
cat <<'EOF'
sk-ant-[a-z]{3}[0-9]{2}-[A-Za-z0-9_-]{20,}
sk-proj-[A-Za-z0-9_-]{30,}
sk-[A-Za-z0-9]{40,}
(sk|rk)_live_[A-Za-z0-9]{20,}
AIzaSy[A-Za-z0-9_-]{30,}
AKIA[0-9A-Z]{16}
glpat-[A-Za-z0-9_-]{20,}
gh[pousr]_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{22,}
xox[abpr]-[A-Za-z0-9-]{20,}
eyJ[A-Za-z0-9_-]{10,}[.]eyJ[A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}
[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]:@]{6,}@
[A-Z0-9_]*(SECRET|PASSWORD|PASSWD|TOKEN|API_KEY|APIKEY|ACCESS_KEY|PRIVATE_KEY)[A-Z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_@#%^&*!.+/=~$-]{8,}
-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED |)?PRIVATE KEY-----
EOF
}

# Prints every secret-shaped string in the given files, one per line: trailing punctuation trimmed,
# placeholders dropped. A PEM header is the same text for every key, so when one is present every
# base64 run of 32+ characters is printed too (key body lines, with or without a log prefix).
# Returns 2 when a file cannot be scanned: callers treat that as a hit (fail closed).
secret_strings() {
  local f st found
  for f in "$@"; do { [ -f "$f" ] && [ -r "$f" ]; } || return 2; done
  found="$(grep -ohaE -f <(secret_patterns) -- "$@")"; st=$?
  [ "$st" -le 1 ] || return 2
  if [ "$st" -eq 0 ]; then
    printf '%s\n' "$found" | sed -E 's/[.,;:!?)]+$//' | grep -viE -e "$PLACEHOLDER"
  fi
  grep -qaE -e "$PEM_HEADER" -- "$@"; st=$?
  [ "$st" -le 1 ] || return 2
  if [ "$st" -eq 0 ]; then
    cat -- "$@" | grep -ohaE -e "$B64_RUN"
  fi
  return 0
}

# 0 = secret-shaped content found, or the files could not be scanned.
has_secret() {
  local found
  found="$(secret_strings "$@")" || return 0
  [ -n "$found" ]
}

# 0 = leak: a file holds a secret-shaped string outside the allow set. 1 = clean. 2 = the scan
# failed (callers fail closed with their own reason). The allow set is what the prompt contained
# before Codex ran, kept in this process's memory so a Codex that rewrites the prompt file cannot
# widen it. Why allow at all: codex exec echoes the prompt into its raw stream, so a target with
# secret-shaped test fixtures would otherwise quarantine every angle. A string the target already
# held is not a new disclosure (the orchestrator read the target to build the prompt); anything
# Codex found elsewhere is.
new_secret_in() {
  local allow="$1" f m found existing=()
  shift
  for f in "$@"; do [ -e "$f" ] && existing+=("$f"); done
  [ ${#existing[@]} -gt 0 ] || return 1
  found="$(secret_strings "${existing[@]}")" || return 2
  [ -n "$found" ] || return 1
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    printf '%s\n' "$allow" | grep -qxF -e "$m" || return 0
  done <<< "$(printf '%s\n' "$found" | sort -u)"
  return 1
}

# Refuse obvious credential files as targets: the wrapper itself would copy them into the prompt.
# Same families as the preamble's list, case-insensitive.
is_credential_file() {
  local b
  b="$(basename -- "$1" | tr 'A-Z' 'a-z')"
  case "$b" in
    *.example|*.sample|*.template|*.dist) return 1 ;;
    .env|.env.*|*.env|.envrc|dotenv|*.pem|*.key|*.p12|*.pfx|*.ppk|*.keystore|*.jks|*.token|*.tfvars|*.tfstate) return 0 ;;
    id_rsa|id_rsa.*|id_dsa|id_dsa.*|id_ecdsa|id_ecdsa.*|id_ed25519|id_ed25519.*) return 0 ;;
    .netrc|.npmrc|.pypirc|.pgpass|.git-credentials|credentials|credentials.*|.credentials.json|auth.json|kubeconfig) return 0 ;;
    *secret*.json|*secret*.yaml|*secret*.yml|*secret*.env|*secret*.ini|*secret*.toml|*secret*.txt) return 0 ;;
    *credential*.json|*credential*.yaml|*credential*.yml|*credential*.ini|*credential*.toml|*credential*.txt) return 0 ;;
  esac
  return 1
}

# 0 = the path, or any hop of its symlink chain, is a credential file (or the chain is too deep).
credential_path() {
  local p="$1" t i=0
  while :; do
    is_credential_file "$p" && return 0
    [ -L "$p" ] || return 1
    t="$(readlink -- "$p")" || return 1
    case "$t" in /*|[A-Za-z]:*) p="$t" ;; *) p="$(dirname -- "$p")/$t" ;; esac
    i=$((i + 1)); [ "$i" -lt 20 ] || return 0
  done
}

# 0 = every file is gone.
destroy() {
  local f
  for f in "$@"; do
    [ -e "$f" ] || continue
    if command -v shred >/dev/null 2>&1; then shred -uz -- "$f" 2>/dev/null || rm -f -- "$f"; else rm -f -- "$f"; fi
  done
  for f in "$@"; do [ -e "$f" ] && return 1; done
  return 0
}

destroy_dir() {
  local f
  [ -d "$1" ] || return 0
  for f in "$1"/* "$1"/.[!.]*; do [ -f "$f" ] && destroy "$f"; done
  rm -rf -- "$1"
}

# Printable ASCII only, fence brackets removed: a failed call's stderr tail must never parse as an
# answer (parsers also split on U+2028/U+2029).
sanitized_tail() { tail -c 300 "$1" 2>/dev/null | LC_ALL=C tr -c '[:print:]' ' ' | tr -d '<>'; }

# GNU coreutils timeout only: Windows ships an unrelated timeout.exe.
timeout_cmd() {
  local t
  for t in timeout gtimeout; do
    if command -v "$t" >/dev/null 2>&1 && "$t" --version 2>/dev/null | grep -q coreutils; then
      echo "$t"; return 0
    fi
  done
  return 1
}

# Defense in depth: the preamble forbids reading these, but say so when they are right here.
warn_secret_files_in_cwd() {
  local f found=()
  shopt -s nullglob
  for f in .env .env.* *credentials* *secret* *.pem *.key *.p12 *.pfx; do
    case "$f" in *.example|*.sample|*.template|*.dist) continue ;; esac
    [ -f "$f" ] && found+=("$f")
  done
  shopt -u nullglob
  [ ${#found[@]} -gt 0 ] && warn "cwd holds secret-shaped files (${found[*]}); Codex runs here with shell access. Prefer a directory without them."
  return 0
}

# A previous security marker is the incident record (and may name files to delete by hand): keep it.
archive_incident() {
  [ -f "$1" ] || return 0
  case "$(head -1 "$1" 2>/dev/null)" in
    "[fallback: codex-output-contained-secret-pattern]"*|"[fallback: prompt-modified-during-run]"*|"[fallback: scan-failed]"*)
      mv -f -- "$1" "$1.incident.$(date +%Y%m%d-%H%M%S)" && warn "kept the previous security marker as $1.incident.*" ;;
  esac
}

# One attempt per output at a time: a second attempt would publish over the first.
CR_LOCK=""
take_lock() {
  local lock="$1" pid
  if ! mkdir "$lock" 2>/dev/null; then
    pid="$(cat "$lock/pid" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      die "another attempt of this call is still running (pid $pid); wait for it or stop it first"
    fi
    rm -rf -- "$lock"; mkdir "$lock" 2>/dev/null || die "cannot lock $lock"
  fi
  echo "$$" > "$lock/pid"; CR_LOCK="$lock"
}

# Unscrubbed Codex output lives here, outside the (possibly committed) run dir. A hard kill skips
# every trap, so later runs remove scratch dirs whose owner process is gone.
CR_SCRATCH=""
make_scratch() {
  local d pid
  for d in "$SCRATCH_BASE"/codex-run-"$SKILL_NAME"-*; do
    [ -d "$d" ] || continue
    pid="${d##*/codex-run-"$SKILL_NAME"-}"; pid="${pid%%-*}"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || destroy_dir "$d"
  done
  CR_SCRATCH="$(mktemp -d "$SCRATCH_BASE/codex-run-$SKILL_NAME-$$-XXXXXX")" || die "cannot create a scratch dir in $SCRATCH_BASE"
}

cr_exit() {
  [ -n "$CR_SCRATCH" ] && destroy_dir "$CR_SCRATCH"
  [ -n "$CR_LOCK" ] && rm -rf -- "$CR_LOCK"
  CR_SCRATCH=""; CR_LOCK=""
}

# Parse $1 into $1.json and stamp the run metadata; prints the summary counts. 1 = parse failed.
publish_json() {
  local out="$1" name="$2" st="$3" tmp="$1.json.tmp.$$"
  if node "$HERE/$PARSER" "$out" "$name" > "$tmp" 2>/dev/null && node -e '
      const fs = require("fs");
      const [f, status, model, effort, sandbox, secs] = process.argv.slice(1);
      const j = JSON.parse(fs.readFileSync(f, "utf8"));
      Object.assign(j, { status, model, effort, sandbox, seconds: Number(secs) });
      fs.writeFileSync(f, JSON.stringify(j));
      process.stdout.write(`verdict=${j.verdict} issues=${(j.issues || []).length} questions=${(j.questions || []).length} degraded=${!!j.degraded}`);
    ' "$tmp" "$st" "$META_MODEL" "$META_EFFORT" "$META_SANDBOX" "$META_SECONDS" 2>/dev/null && mv -f "$tmp" "$out.json"; then
    return 0
  fi
  rm -f "$tmp"
  printf '{"lens":"%s","verdict":"DEGRADED","degraded":true,"issues":[],"questions":[],"status":"%s","error":"parse-triad.js failed (is node on PATH?)"}\n' "$name" "$st" > "$out.json"
  printf 'verdict=DEGRADED degraded=true'
  return 1
}

# Interrupt handler: stop Codex, destroy partial output, leave the marker and its JSON. Globals
# because a trap can fire from anywhere in cmd_run.
CR_CHILD=""; CR_WD=""; CR_OUT=""; CR_NAME=""
META_MODEL=default; META_EFFORT=""; META_SANDBOX=""; META_SECONDS=0
# Codex and the watchdog run as their own process groups (set -m): a group kill reaches every
# descendant, not just the launcher.
kill_group() { kill "-$1" -- "-$2" 2>/dev/null || kill "-$1" "$2" 2>/dev/null; }
cr_interrupted() {
  local i=0
  [ -n "$CR_WD" ] && kill_group TERM "$CR_WD"
  if [ -n "$CR_CHILD" ]; then
    kill_group TERM "$CR_CHILD"
    # Wait for the writer to stop before deleting, or it could recreate what we delete.
    while kill -0 "$CR_CHILD" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
    kill_group KILL "$CR_CHILD"
    wait "$CR_CHILD" 2>/dev/null
  fi
  [ -n "$CR_SCRATCH" ] && destroy_dir "$CR_SCRATCH"; CR_SCRATCH=""
  if [ -n "$CR_OUT" ]; then
    echo "[fallback: interrupted] the wrapper was stopped before Codex finished; partial output destroyed" > "$CR_OUT"
    [ -n "$CR_NAME" ] && publish_json "$CR_OUT" "$CR_NAME" "degraded(interrupted)" >/dev/null
  fi
  exit 130
}

cmd_usage="usage: codex-run.sh lens|prompt <discussion-dir> <round> <llm|architect|enduser> --target <doc> [--context F]... [--instructions F] [--no-carryover]"

# Shared by `lens` and `prompt`, so both engines are asked the same thing.
parse_lens_args() {
  [ $# -ge 3 ] || die "$cmd_usage"
  L_DIR="$1"; L_ROUND="$2"; L_LENS="$3"; shift 3
  [ -d "$L_DIR" ] || die "discussion dir not found: '$L_DIR'"
  case "$L_ROUND" in ''|*[!0-9]*|0*) die "round must be a whole number >= 1, got '$L_ROUND'" ;; esac
  case "$L_LENS" in llm|architect|enduser) ;; *) die "lens must be llm, architect or enduser, got '$L_LENS'" ;; esac
  L_PERSP="$HERE/agents/$L_LENS-perspective.md"
  [ -r "$L_PERSP" ] || die "missing $L_PERSP"
  [ -r "$HERE/templates/output-contract.md" ] || die "missing $HERE/templates/output-contract.md (the output contract both engines share)"
  L_TARGET=""; L_CONTEXTS=(); L_INSTR=""; L_NOCARRY=0; L_CARRY=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-carryover) L_NOCARRY=1; shift ;;
      --target|--context|--instructions)
        [ $# -ge 2 ] || die "$1 needs a file"
        { [ -f "$2" ] && [ -r "$2" ]; } || die "${1#--} is not a readable file: '$2'"
        credential_path "$2" && die "refusing credential file '$2' as ${1#--}: it would be copied into the prompt"
        case "$1" in
          --target)       [ -z "$L_TARGET" ] || die "--target given twice (one document per discussion)"; L_TARGET="$2" ;;
          --context)      L_CONTEXTS+=("$2") ;;
          --instructions) [ -z "$L_INSTR" ] || die "--instructions given twice"; L_INSTR="$2" ;;
        esac
        shift 2 ;;
      *) die "unknown option '$1'" ;;
    esac
  done
  [ -n "$L_TARGET" ] || die "needs --target <doc>"
  # Round-Delta: round N reads what round N-1 settled and what it left open. A missing file is an
  # error, not a warning, so the structure cannot silently drop out.
  if [ "$L_ROUND" -ge 2 ] && [ "$L_NOCARRY" -eq 0 ]; then
    L_CARRY="$L_DIR/round-$((L_ROUND - 1)).carryover.txt"
    { [ -f "$L_CARRY" ] && [ ! -L "$L_CARRY" ] && [ -r "$L_CARRY" ]; } \
      || die "round $L_ROUND needs $L_CARRY as a regular file (Phase 5 writes it: '## 합의됨' / '## 미해소'); pass --no-carryover only to skip Round-Delta on purpose"
  fi
  case "$SKILL_NAME" in
    triad-all)   L_STEM="round-$L_ROUND.codex.$L_LENS"; L_CSTEM="round-$L_ROUND.claude.$L_LENS" ;;
    triad-codex) L_STEM="round-$L_ROUND.$L_LENS";       L_CSTEM="" ;;
    *) die "unknown skill directory '$SKILL_NAME' (expected triad-all or triad-codex)" ;;
  esac
}

# The prompt body both engines get (Codex additionally gets the preamble in front). Target,
# context and carryover come first: identical across the 3 lenses, so the prompt cache reuses them.
build_body() {
  local c
  printf '%s\n\n' "[아래 대상 파일을 읽고, 마지막에 주어지는 관점으로만 평가하라]"
  printf '%s\n' "## 대상 파일 ($L_TARGET) - 줄번호는 이 파일 기준"
  cat -- "$L_TARGET" || return 1
  for c in "${L_CONTEXTS[@]}"; do
    printf '\n%s\n' "## 배경 ($c) - 사실 확인용 맥락, 평가 대상 아님"
    cat -- "$c" || return 1
  done
  if [ -n "$L_INSTR" ]; then
    printf '\n%s\n' "## 추가 지시 (반드시 따를 것)"
    cat -- "$L_INSTR" || return 1
  fi
  if [ -n "$L_CARRY" ]; then
    printf '\n%s\n' "## 지난 라운드 carryover - '합의됨'은 재논의 금지, '미해소'는 이번 라운드에서 다시 확인"
    cat -- "$L_CARRY" || return 1
  fi
  printf '\n%s\n' "## 너의 관점 정의"
  cat -- "$L_PERSP" || return 1
  contract
}

cmd_prompt() {
  parse_lens_args "$@"
  [ -n "$L_CSTEM" ] || die "prompt builds the Claude agent prompt for triad-all; triad-codex has no Claude agents"
  local f="$L_DIR/$L_CSTEM.prompt.txt"
  rm -f -- "$f"
  ( build_body ) > "$f" || { rm -f -- "$f"; die "could not build the prompt (unreadable target, context, instructions, carryover or perspective)"; }
  # C:/... on Git Bash so the Read tool can open it.
  printf '%s/%s\n' "$(cd "$(dirname -- "$f")" && { pwd -W 2>/dev/null || pwd; })" "$(basename -- "$f")"
}

cmd_lens() {
  parse_lens_args "$@"
  local dir="$L_DIR" lens="$L_LENS" round="$L_ROUND" angle="$L_LENS" kind=discovery
  local bin="${TRIAD_CODEX_BIN:-codex}" effort="${TRIAD_CODEX_EFFORT:-high}" secs="${TRIAD_CODEX_TIMEOUT:-300}"
  case "$effort" in ''|*[!a-z]*) die "TRIAD_CODEX_EFFORT must be a lowercase word, got '$effort'" ;; esac
  case "$secs" in ''|*[!0-9]*|0*) die "TRIAD_CODEX_TIMEOUT must be whole seconds 1-$MAX_TIMEOUT, got '$secs'" ;; esac
  [ "$secs" -le "$MAX_TIMEOUT" ] || die "TRIAD_CODEX_TIMEOUT must be at most $MAX_TIMEOUT (the caller's Bash timeout, (seconds+30)*1000 ms, caps at 600000), got $secs"
  # Review only needs to read. read-only blocks writes and network for every command Codex runs;
  # bypass is an explicit per-run opt-out (paths the sandbox cannot reach, no sandbox support).
  local sandbox="${TRIAD_CODEX_SANDBOX:-read-only}" sandbox_args
  case "$sandbox" in
    read-only) sandbox_args=(-s read-only) ;;
    bypass)    sandbox_args=(--dangerously-bypass-approvals-and-sandbox)
               warn "TRIAD_CODEX_SANDBOX=bypass: Codex runs without a sandbox (full file and network access)" ;;
    *) die "TRIAD_CODEX_SANDBOX must be read-only or bypass, got '$sandbox'" ;;
  esac
  local prompt="$dir/$L_STEM.prompt.txt" out="$dir/$L_STEM.codex.txt"

  take_lock "$out.lock"
  trap cr_exit EXIT
  make_scratch
  local work="$CR_SCRATCH/prompt" raw="$CR_SCRATCH/raw" msg="$CR_SCRATCH/msg" fired="$CR_SCRATCH/timedout"

  # Pre-created so a killed call or missing file reads as DEGRADED, never silently dropped. rm
  # first: a stale parse or prompt from an earlier attempt must not stand in for this one, and a
  # planted symlink must not redirect the write.
  archive_incident "$out"
  rm -f -- "$out" "$out.json" "$prompt"
  echo "[fallback: not-started]" > "$out" || die "cannot write in $dir"

  META_MODEL="${TRIAD_CODEX_MODEL:-default}"; META_EFFORT="$effort"; META_SANDBOX="$sandbox"; META_SECONDS=0
  local status="" took=0 bytes rc allow="" found=""
  if ! ( preamble; printf '\n==== AGENT PROMPT BELOW ====\n'; build_body ) > "$work"; then
    echo "[fallback: prompt-build-failed] the target, a context, the instructions, the carryover or the perspective could not be read" > "$out"
    status="degraded(prompt-build-failed)"
  fi

  if [ -z "$status" ]; then
    warn_secret_files_in_cwd
    # Capture first, sort second: a pipeline's status is the last command's.
    if ! found="$(secret_strings "$work")"; then
      echo "[fallback: prompt-build-failed] the prompt could not be scanned for secrets" > "$out"
      status="degraded(prompt-build-failed)"
    else
      allow="$(printf '%s\n' "$found" | sed '/^$/d' | sort -u)"
      [ -n "$allow" ] && warn "the prompt holds $(printf '%s\n' "$allow" | wc -l | tr -d ' ') secret-shaped string(s) from the target or lens; they go to Codex and are allowed back in its output"
    fi
  fi

  if [ -z "$status" ]; then
    bytes=$(wc -c < "$work" | tr -d ' ')
    if [ "$bytes" -gt "$MAX_BYTES" ]; then
      # Hits every lens identically: degraded, not fatal.
      mv -f "$work" "$prompt"
      echo "[fallback: prompt-too-large] $bytes bytes > $MAX_BYTES. Split the document or shorten the context." > "$out"
      status="degraded(prompt-too-large)"
    fi
  fi

  if [ -z "$status" ]; then
    local args=(exec -c "model_reasoning_effort=$effort" "${sandbox_args[@]}"
                --skip-git-repo-check --output-last-message "$msg")
    [ -n "${TRIAD_CODEX_MODEL:-}" ] && args+=(-m "$TRIAD_CODEX_MODEL")
    local tcmd="" start=$SECONDS
    [ -z "${_CODEX_RUN_FORCE_WATCHDOG:-}" ] && tcmd="$(timeout_cmd)"

    # Background + wait so the trap can fire mid-call. set -m gives each background job its own
    # process group, so timeouts and interrupts reach Codex's descendants too.
    CR_OUT="$out"; CR_NAME="$angle"
    trap cr_interrupted INT TERM HUP
    set -m
    if [ -n "$tcmd" ]; then
      "$tcmd" -k 15 "$secs" "$bin" "${args[@]}" < "$work" > "$raw" 2>&1 &
      CR_CHILD=$!
    else
      # Portable watchdog (stock macOS has no GNU timeout). Its stdio is detached so a lingering
      # sleep cannot hold the caller's output pipe open.
      "$bin" "${args[@]}" < "$work" > "$raw" 2>&1 &
      CR_CHILD=$!
      ( sleep "$secs"; : > "$fired"; kill_group TERM "$CR_CHILD"
        sleep 15; kill_group KILL "$CR_CHILD" ) </dev/null >/dev/null 2>&1 &
      CR_WD=$!
    fi
    set +m
    wait "$CR_CHILD"; rc=$?
    # The launcher exited; reap anything left in its group before the scrub reads its files.
    kill_group KILL "$CR_CHILD"
    if [ -n "$CR_WD" ]; then
      kill_group TERM "$CR_WD"; wait "$CR_WD" 2>/dev/null; CR_WD=""
      { [ -e "$fired" ] && [ "$rc" -ne 0 ]; } && rc=124
    fi
    CR_CHILD=""
    took=$((SECONDS - start)); META_SECONDS=$took

    # Scrub FIRST, over the prompt, the raw stream AND the last message, before anything is copied
    # anywhere (that includes the stderr tail used in the fallback markers below).
    local leak="" stream="" r f
    for f in prompt raw msg; do
      case "$f" in prompt) new_secret_in "$allow" "$work" ;; raw) new_secret_in "$allow" "$raw" ;; msg) new_secret_in "$allow" "$msg" ;; esac
      r=$?
      if [ "$r" -eq 0 ]; then
        stream="$f"; leak="codex-output-contained-secret-pattern"
        [ "$f" = prompt ] && leak="prompt-modified-during-run"
        break
      elif [ "$r" -eq 2 ]; then
        stream="$f"; leak="scan-failed"; break
      fi
    done
    if [ -n "$leak" ]; then
      local gone=1
      destroy "$work" "$raw" "$msg" || gone=0
      {
        echo "[fallback: $leak] stream=$stream"
        if [ "$leak" = scan-failed ]; then
          echo "[fallback: the $stream could not be scanned for secrets, so it was treated as a leak and"
          echo "[fallback: deleted (fail closed). Check the disk/permissions, then re-run."
        else
          echo "[fallback: this codex lens wrote secret-shaped content that was not in its prompt (it"
          echo "[fallback: may have run a forbidden command that resolved env_file:). Its output and"
          echo "[fallback: prompt were deleted. Do not auto-retry: audit the prompt for compliance with"
          echo "[fallback: the Sandbox Safety Preamble and tell the user."
        fi
        [ "$gone" -eq 1 ] || echo "[fallback: CLEANUP FAILED: delete $work $raw $msg by hand]"
      } > "$out"
      echo "::warning::$SKILL_NAME: codex/$angle $leak ($stream); sanitized + deleted$([ "$gone" -eq 1 ] || echo ' (CLEANUP FAILED)')" >&2
      status="secret-scrubbed($leak)"; [ "$gone" -eq 1 ] || status="secret-scrubbed($leak,cleanup-failed)"
    else
      mv -f "$work" "$prompt"
      if [ "$rc" -ne 0 ]; then
        local reason=codex-unavailable
        case "$rc" in 124|137) reason=timeout ;; esac
        # Keep the stderr tail so the operator can tell config error vs timeout vs auth.
        echo "[fallback: $reason] exit $rc after ${took}s: $(sanitized_tail "$raw")" > "$out"
        status="degraded($reason)"
      elif [ -s "$msg" ]; then
        if mv -f "$msg" "$out"; then
          status=ok
        else
          echo "[fallback: publish-failed] could not move the answer into $out" > "$out"
          status="degraded(publish-failed)"
        fi
      else
        # The raw stream echoes the prompt (target, examples), so it is never parsed as the answer.
        echo "[fallback: no-last-message] codex exited 0 after ${took}s without a final message: $(sanitized_tail "$raw")" > "$out"
        status="degraded(no-last-message)"
      fi
    fi
    trap - INT TERM HUP
    CR_OUT=""; CR_NAME=""
  fi

  local meta="model=$META_MODEL effort=$effort sandbox=$sandbox seconds=$took" counts
  counts="$(publish_json "$out" "$lens" "$status")" || status="$status+parse-failed"
  echo "[codex-run] $SKILL_NAME round $round $lens: status=$status $counts $meta out=$out"
  cat "$out.json"; echo
  return 0
}

selftest() {
  local fails=0 n=0 out out2 rc D P O T t0 bgpid i l other stem cstem
  local SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
  # A caller's overrides must not change what the selftest checks.
  unset TRIAD_CODEX_EFFORT TRIAD_CODEX_TIMEOUT TRIAD_CODEX_MODEL TRIAD_CODEX_SANDBOX _CODEX_RUN_FORCE_WATCHDOG
  ST_TMP="$(mktemp -d)" || die "mktemp failed"
  trap 'rm -rf "$ST_TMP"' EXIT
  T="$ST_TMP"
  export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
  run() { bash "$SELF" "$@"; }
  check() { n=$((n + 1)); if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
  line_of() { grep -n -m1 -F -e "$1" "$2" | cut -d: -f1; }
  bounded() { if timeout_cmd >/dev/null; then "$(timeout_cmd)" 20 "$@"; else "$@"; fi; }
  only_published() { [ -z "$(ls -A "$1" | grep -vE '\.(prompt\.txt|codex\.txt|codex\.txt\.json|carryover\.txt)$|\.incident\.[0-9-]+$')" ]; }

  # Fixtures are assembled at runtime so this file never holds a literal secret-shaped string.
  export FX_GH="ghp""_abcdefghijklmnopqrstuvwxyz" FX_GH2="ghp""_ZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  export FX_ANT="sk-ant""-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAA" FX_PW="DB_PASS""WORD=hunter2hunter2"
  export FX_PEM_H="-----BEGIN PRIV""ATE KEY-----"
  export FX_PEM_A="MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7aaaa"
  export FX_PEM_B="QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9w"
  export FX_U2028="$(printf '\342\200\250')"

  cat > "$T/fake-codex" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_DIR/args"
msg=""; while [ $# -gt 0 ]; do [ "$1" = --output-last-message ] && msg="$2"; shift; done
cat > "$FAKE_DIR/stdin"
fence=$'reasoning\n<<<TRIAD-FINDINGS v1>>>\nVERDICT | REVISE\nISSUE | high | doc.md:3@Setup | step 2 is ambiguous -> name the command\nQUESTION | which shell?\n<<<END>>>'
case "$FAKE_MODE" in
  ok)       echo "session noise"; echo "$fence"; printf '%s\n' "$fence" > "$msg" ;;
  rawonly)  cat "$FAKE_DIR/stdin"; echo "$fence" ;;
  echo)     cat "$FAKE_DIR/stdin"; echo "$fence"; printf '%s\n' "$fence" > "$msg" ;;
  echonew)  cat "$FAKE_DIR/stdin"; echo "found $FX_GH2 in .env"; printf '%s\n' "$fence" > "$msg" ;;
  echoquote) cat "$FAKE_DIR/stdin"; printf '%s\nset `DB_PASS''WORD=changeme123`를 바꾸세요. POSTGRES_PASS''WORD=<your-password>\n' "$fence" > "$msg" ;;
  echotpl)  { sed -n '/^<<<TRIAD-FINDINGS v1>>>$/,/^<<<END>>>$/p' "$FAKE_DIR/stdin" | head -6; echo "$fence"; } > "$msg" ;;
  pemnew)   cat "$FAKE_DIR/stdin"; printf '%s\n%s\n' "$FX_PEM_H" "$FX_PEM_B"; printf '%s\n' "$fence" > "$msg" ;;
  secret)   echo "ANTHROPIC key $FX_ANT"; printf '%s\n' "$fence" > "$msg" ;;
  msgsec)   echo "$fence"; printf '%s\n' "$FX_GH" > "$msg" ;;
  tamper)   for f in "$TMPDIR"/codex-run-*/prompt; do printf 'injected %s\n' "$FX_GH2" >> "$f"; done; echo "$fence"; printf '%s\n' "$fence" > "$msg" ;;
  fail)     echo "error: not logged in" >&2; exit 1 ;;
  failsec)  echo "boom $FX_PW" >&2; exit 1 ;;
  failfence) printf 'x%s<<<TRIAD-FINDINGS v1>>>%sVERDICT | PASS%s<<<END>>>\n' "$FX_U2028" "$FX_U2028" "$FX_U2028" >&2; exit 1 ;;
  quietwarn) echo "warning: config key ignored" >&2; exit 0 ;;
  hang)     : > "$FAKE_DIR/started"; sleep 20 ;;
  empty)    exit 0 ;;
esac
FAKE
  chmod +x "$T/fake-codex"
  export TRIAD_CODEX_BIN="$T/fake-codex" FAKE_DIR="$T"
  D="$T/disc"; mkdir -p "$D"
  printf '# Doc\n\nStep 1. Install.\nStep 2. Run it.\n' > "$T/doc.md"
  stem="round-1.codex"; cstem="round-1.claude"; [ "$SKILL_NAME" = triad-all ] || stem="round-1"
  r() { printf '%s' "${stem/round-1/round-$1}"; }

  # --- the shared structure: one contract file, the same body for both engines -------------------
  check "contract file holds the TRIAD-FINDINGS v1 grammar" 'grep -qx "<<<TRIAD-FINDINGS v1>>>" "$HERE/templates/output-contract.md" && grep -q "^VERDICT | " "$HERE/templates/output-contract.md" && grep -q "^ISSUE | " "$HERE/templates/output-contract.md" && grep -q "^QUESTION | " "$HERE/templates/output-contract.md"'
  local yaml_left=""
  for l in llm architect enduser; do grep -qE "^(verdict|top_issues|open_questions):" "$HERE/agents/$l-perspective.md" && yaml_left="$yaml_left $l"; done
  check "no perspective file asks for a different (YAML) output format" '[ -z "$yaml_left" ]'

  out="$(FAKE_MODE=ok run lens "$D" 1 llm --target "$T/doc.md" 2>/dev/null)"
  P="$D/$(r 1).llm.prompt.txt"; O="$D/$(r 1).llm.codex.txt"
  check "preamble is the first line of the prompt" '[ "$(head -1 "$P")" = "SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):" ]'
  check "prompt reaches codex on stdin, byte-identical" 'cmp -s "$P" "$T/stdin"'
  check "prompt is not on argv" '[ -s "$T/args" ] && ! grep -q "Step 2. Run it" "$T/args"'
  check "effort high, read-only sandbox, repo check skipped, last message requested" 'grep -qx "model_reasoning_effort=high" "$T/args" && grep -A1 -x -- "-s" "$T/args" | grep -qx "read-only" && ! grep -q -- "--dangerously-bypass" "$T/args" && grep -qx -- "--skip-git-repo-check" "$T/args" && grep -qx -- "--output-last-message" "$T/args"'
  check "contract file is appended verbatim, last" '[ "$(tail -c 300 "$P")" = "$(tail -c 300 "$HERE/templates/output-contract.md")" ]'
  check "last message used; dir holds only published files; lock and scratch gone" 'grep -q "step 2 is ambiguous" "$O" && ! grep -q "session noise" "$O" && only_published "$D" && [ -z "$(ls -A "$TMPDIR" | grep codex-run-)" ]'
  check "verdict, issue, question and run metadata in the json" 'grep -q "\"verdict\":\"REVISE\"" "$O.json" && grep -q "which shell" "$O.json" && grep -q "\"status\":\"ok\"" "$O.json" && grep -q "\"effort\":\"high\"" "$O.json"'
  check "summary line reports verdict, counts, model and effort" 'printf "%s" "$out" | head -1 | grep -q "status=ok verdict=REVISE issues=1 questions=1 degraded=false model=default effort=high sandbox=read-only"'

  printf -- '## 합의됨\n- keep step 1\n## 미해소\n- step 2 wording\n' > "$D/round-1.carryover.txt"
  printf 'Project background line.\n' > "$T/ctx1.md"; printf 'Second background line.\n' > "$T/ctx2.md"; printf 'Verify every claim against the code.\n' > "$T/instr.md"
  FAKE_MODE=ok run lens "$D" 2 architect --target "$T/doc.md" --context "$T/ctx1.md" --context "$T/ctx2.md" --instructions "$T/instr.md" >/dev/null 2>&1
  P="$D/$(r 2).architect.prompt.txt"
  check "round 2 order: target < contexts < instructions < carryover < perspective < contract" '[ "$(line_of "Step 2. Run it" "$P")" -lt "$(line_of "Project background line" "$P")" ] && [ "$(line_of "Project background line" "$P")" -lt "$(line_of "Second background line" "$P")" ] && [ "$(line_of "Second background line" "$P")" -lt "$(line_of "Verify every claim" "$P")" ] && [ "$(line_of "Verify every claim" "$P")" -lt "$(line_of "keep step 1" "$P")" ] && [ "$(line_of "keep step 1" "$P")" -lt "$(line_of "## 너의 관점 정의" "$P")" ] && [ "$(line_of "## 너의 관점 정의" "$P")" -lt "$(line_of "<<<TRIAD-FINDINGS v1>>>" "$P")" ]'
  check "each lens gets its own perspective file" 'grep -qF "$(sed -n 1p "$HERE/agents/architect-perspective.md")" "$P" && ! grep -qF "$(sed -n 1p "$HERE/agents/llm-perspective.md")" "$P"'
  if [ "$SKILL_NAME" = triad-all ]; then
    out="$(run prompt "$D" 2 architect --target "$T/doc.md" --context "$T/ctx1.md" --context "$T/ctx2.md" --instructions "$T/instr.md" 2>/dev/null)"
    check "prompt: the Claude agent gets the Codex prompt minus the preamble, byte for byte" '[ -s "$D/round-2.claude.architect.prompt.txt" ] && cmp -s "$D/round-2.claude.architect.prompt.txt" <(tail -c "$(wc -c < "$D/round-2.claude.architect.prompt.txt")" "$P") && [ "$(head -c 13 "$D/round-2.claude.architect.prompt.txt")" != "SANDBOX SAFET" ] && printf "%s" "$out" | grep -q "round-2.claude.architect.prompt.txt$"'
  fi
  run lens "$D" 3 enduser --target "$T/doc.md" >/dev/null 2>&1; rc=$?
  check "round 3 without a round-2 carryover file: refused (exit 2)" '[ $rc -eq 2 ]'
  FAKE_MODE=ok run lens "$D" 3 enduser --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "--no-carryover skips Round-Delta explicitly and the call runs" 'grep -q "step 2 is ambiguous" "$D/$(r 3).enduser.codex.txt"'
  run lens "$D" 1 llm --target "$T/doc.md" --target "$T/ctx1.md" >/dev/null 2>&1; rc=$?
  check "--target given twice refused (exit 2)" '[ $rc -eq 2 ]'

  FAKE_MODE=echotpl run lens "$D" 4 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "an echoed contract template cannot win over the real verdict" 'grep -q "\"verdict\":\"REVISE\"" "$D/$(r 4).llm.codex.txt.json"'
  out2="$(TRIAD_CODEX_MODEL=gpt-x TRIAD_CODEX_SANDBOX=bypass FAKE_MODE=ok run lens "$D" 4 architect --target "$T/doc.md" --no-carryover 2>/dev/null)"
  check "bypass only when asked; model passed as -m and reported" 'grep -qx -- "--dangerously-bypass-approvals-and-sandbox" "$T/args" && ! grep -qx -- "-s" "$T/args" && grep -A1 -x -- "-m" "$T/args" | grep -qx gpt-x && printf "%s" "$out2" | head -1 | grep -q "model=gpt-x effort=high sandbox=bypass"'

  FAKE_MODE=rawonly run lens "$D" 5 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "no last message: degraded, the echoed raw stream is not parsed" 'grep -q "^\[fallback: no-last-message\]" "$D/$(r 5).llm.codex.txt" && grep -q "\"verdict\":\"DEGRADED\"" "$D/$(r 5).llm.codex.txt.json"'
  FAKE_MODE=quietwarn run lens "$D" 5 architect --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "no last message keeps the stderr tail" 'grep -q "config key ignored" "$D/$(r 5).architect.codex.txt"'
  FAKE_MODE=secret run lens "$D" 6 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  O="$D/$(r 6).llm.codex.txt"
  check "secret in raw stream: quarantined (stream named), nothing left behind" 'grep -q "^\[fallback: codex-output-contained-secret-pattern\] stream=raw" "$O" && ! grep -q "$FX_ANT" "$O" && only_published "$D"'
  FAKE_MODE=ok run lens "$D" 6 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "rerun keeps the previous security marker as an incident file" 'ls "$D" | grep -q "$(r 6).llm.codex.txt.incident."'
  FAKE_MODE=msgsec run lens "$D" 6 architect --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "secret in last message only: quarantined (stream=msg)" 'grep -q "stream=msg" "$D/$(r 6).architect.codex.txt"'
  printf 'Token example: %s\n' "$FX_GH" > "$T/fixture.md"
  FAKE_MODE=echo run lens "$D" 7 llm --target "$T/fixture.md" --no-carryover >/dev/null 2>&1
  check "fixture already in the target, echoed back: not quarantined" 'grep -q "step 2 is ambiguous" "$D/$(r 7).llm.codex.txt"'
  FAKE_MODE=echonew run lens "$D" 7 architect --target "$T/fixture.md" --no-carryover >/dev/null 2>&1
  check "fixture plus a new secret from elsewhere: quarantined" 'grep -q "codex-output-contained-secret-pattern" "$D/$(r 7).architect.codex.txt"'
  printf 'DB_PASS''WORD=changeme123\n' > "$T/env-doc.md"
  FAKE_MODE=echoquote run lens "$D" 7 enduser --target "$T/env-doc.md" --no-carryover >/dev/null 2>&1
  check "quoted/particle echo and placeholder fixes: not quarantined" 'grep -q "step 2 is ambiguous" "$D/$(r 7).enduser.codex.txt"'
  printf '%s\n%s\n' "$FX_PEM_H" "$FX_PEM_A" > "$T/key-fixture.md"
  FAKE_MODE=pemnew run lens "$D" 8 llm --target "$T/key-fixture.md" --no-carryover >/dev/null 2>&1
  check "PEM fixture in target does not whitelist a different key body" 'grep -q "codex-output-contained-secret-pattern" "$D/$(r 8).llm.codex.txt"'
  FAKE_MODE=tamper run lens "$D" 8 architect --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "secret written into the prompt during the run: quarantined, prompt not published" 'grep -q "^\[fallback: prompt-modified-during-run\]" "$D/$(r 8).architect.codex.txt" && [ ! -e "$D/$(r 8).architect.prompt.txt" ]'
  mkdir -p "$T/shim"; printf '#!/usr/bin/env bash\ncase " $* " in *" -ohaE "*) exit 2 ;; esac\nexec %s "$@"\n' "$(command -v grep)" > "$T/shim/grep"; chmod +x "$T/shim/grep"
  rm -f "$T/args"
  PATH="$T/shim:$PATH" FAKE_MODE=ok run lens "$D" 8 enduser --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "prompt scan failure: prompt-build-failed, Codex never called" 'grep -q "^\[fallback: prompt-build-failed\]" "$D/$(r 8).enduser.codex.txt" && [ ! -e "$T/args" ]'

  FAKE_MODE=fail run lens "$D" 9 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "codex failure keeps the stderr tail" 'grep -q "^\[fallback: codex-unavailable\].*not logged in" "$D/$(r 9).llm.codex.txt"'
  FAKE_MODE=failsec run lens "$D" 9 architect --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "a secret in a failed call's stderr is not copied into the marker" '! grep -q hunter2 "$D/$(r 9).architect.codex.txt" && grep -q secret-pattern "$D/$(r 9).architect.codex.txt"'
  FAKE_MODE=failfence run lens "$D" 9 enduser --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "a fence inside a failed call's stderr tail cannot parse as PASS" 'grep -q "\"verdict\":\"DEGRADED\"" "$D/$(r 9).enduser.codex.txt.json"'
  if timeout_cmd >/dev/null; then
    TRIAD_CODEX_TIMEOUT=1 FAKE_MODE=hang run lens "$D" 10 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
    check "timeout (GNU timeout): degraded(timeout)" 'grep -q "^\[fallback: timeout\]" "$D/$(r 10).llm.codex.txt"'
  fi
  t0=$SECONDS
  out="$(_CODEX_RUN_FORCE_WATCHDOG=1 TRIAD_CODEX_TIMEOUT=1 FAKE_MODE=hang run lens "$D" 10 architect --target "$T/doc.md" --no-carryover 2>/dev/null)"
  check "timeout (portable watchdog): degraded(timeout), caller not held open" 'grep -q "^\[fallback: timeout\]" "$D/$(r 10).architect.codex.txt" && [ $((SECONDS - t0)) -lt 12 ]'
  rm -f "$T/started"
  ( FAKE_MODE=hang exec bash "$SELF" lens "$D" 11 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1 ) &
  bgpid=$!; i=0
  while [ ! -e "$T/started" ] && [ "$i" -lt 60 ]; do sleep 0.5; i=$((i + 1)); done
  kill -TERM "$bgpid" 2>/dev/null; wait "$bgpid"; rc=$?
  check "interrupted: exit 130, marker and DEGRADED json, no scratch or lock left" '[ $rc -eq 130 ] && grep -q "^\[fallback: interrupted\]" "$D/$(r 11).llm.codex.txt" && grep -q "\"status\":\"degraded(interrupted)\"" "$D/$(r 11).llm.codex.txt.json" && only_published "$D" && [ -z "$(ls -A "$TMPDIR" | grep codex-run-)" ]'
  mkdir -p "$D/$(r 12).llm.codex.txt.lock"; echo "$$" > "$D/$(r 12).llm.codex.txt.lock/pid"
  FAKE_MODE=ok run lens "$D" 12 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1; rc=$?
  check "a second attempt while the first still runs is refused (exit 2)" '[ $rc -eq 2 ]'
  echo 999999 > "$D/$(r 12).llm.codex.txt.lock/pid"
  mkdir -p "$TMPDIR/codex-run-$SKILL_NAME-999999-abcdef"; printf 'unscrubbed\n' > "$TMPDIR/codex-run-$SKILL_NAME-999999-abcdef/raw"
  FAKE_MODE=ok run lens "$D" 12 llm --target "$T/doc.md" --no-carryover >/dev/null 2>&1
  check "stale lock taken over; a hard-killed run's scratch swept" 'grep -q "step 2 is ambiguous" "$D/$(r 12).llm.codex.txt" && [ ! -e "$TMPDIR/codex-run-$SKILL_NAME-999999-abcdef" ]'
  head -c 190000 /dev/zero | tr '\0' 'x' > "$T/big.md"; rm -f "$T/stdin"
  FAKE_MODE=ok run lens "$D" 13 llm --target "$T/big.md" --no-carryover >/dev/null 2>&1
  check "oversized prompt: degraded, codex never called" 'grep -q "^\[fallback: prompt-too-large\]" "$D/$(r 13).llm.codex.txt" && [ ! -e "$T/stdin" ]'

  local bad=0 cred tv
  run lens "$D" 1 security --target "$T/doc.md" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  run lens "$D" 0 llm --target "$T/doc.md" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  run lens "$D" 1 llm >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  bounded bash "$SELF" lens "$D" 1 llm --target >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  for cred in .env .ENV operator.env dotenv secrets.yaml id_dsa api.token; do
    printf 'K=v\n' > "$T/$cred"; run lens "$D" 1 llm --target "$T/$cred" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  done
  run lens "$D" 1 llm --target "$T/doc.md" --context "$T/.env" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  for tv in 0 00 571 abc; do TRIAD_CODEX_TIMEOUT=$tv run lens "$D" 1 llm --target "$T/doc.md" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1; done
  TRIAD_CODEX_EFFORT=High run lens "$D" 1 llm --target "$T/doc.md" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  TRIAD_CODEX_SANDBOX=off run lens "$D" 1 llm --target "$T/doc.md" >/dev/null 2>&1; [ $? -eq 2 ] || bad=1
  check "usage errors exit 2: lens, round, target, credential files (target/context), timeout 0/00/571, effort, sandbox" '[ $bad -eq 0 ]'
  check "this script holds no literal secret-shaped string (fixtures are assembled at runtime)" '[ -z "$(secret_strings "$SELF")" ]'

  # The sibling skill names its files differently; check from a copy.
  other=triad-codex; [ "$SKILL_NAME" = triad-all ] || other=triad-all
  mkdir -p "$T/$other/agents" "$T/$other/templates" "$T/d2"
  cp "$SELF" "$HERE/parse-triad.js" "$T/$other/" && cp "$HERE"/agents/*.md "$T/$other/agents/" && cp "$HERE/templates/output-contract.md" "$T/$other/templates/"
  FAKE_MODE=ok bash "$T/$other/codex-run.sh" lens "$T/d2" 1 llm --target "$T/doc.md" >/dev/null 2>&1
  if [ "$other" = triad-all ]; then
    check "triad-all names files round-N.codex.<lens>.*" '[ -s "$T/d2/round-1.codex.llm.codex.txt.json" ]'
  else
    check "triad-codex names files round-N.<lens>.*" '[ -s "$T/d2/round-1.llm.codex.txt.json" ] && [ ! -e "$T/d2/round-1.codex.llm.codex.txt" ]'
  fi
  mkdir -p "$T/triad-dev/agents" "$T/triad-dev/templates"; cp "$SELF" "$HERE/parse-triad.js" "$T/triad-dev/"; cp "$HERE"/agents/*.md "$T/triad-dev/agents/"; cp "$HERE/templates/output-contract.md" "$T/triad-dev/templates/"
  bash "$T/triad-dev/codex-run.sh" lens "$T/d2" 1 llm --target "$T/doc.md" >/dev/null 2>&1; rc=$?
  check "an unknown skill directory name is refused instead of guessing the naming (exit 2)" '[ $rc -eq 2 ]'

  echo "codex-run selftest: $((n - fails))/$n passed"
  [ "$fails" -eq 0 ]
}

case "${1:-}" in
  lens)       shift; cmd_lens "$@" ;;
  prompt)     shift; cmd_prompt "$@" ;;
  --selftest) selftest ;;
  *) die "$cmd_usage | --selftest" ;;
esac
