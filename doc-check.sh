#!/usr/bin/env bash
# doc-check.sh — regenerate stale repo-expert docs before committing
# Usage: ./doc-check.sh ["commit message"]
# Requires: claude CLI (Claude Code), git

set -euo pipefail

# ── config ──────────────────────────────────────────────────────────────────
DOCS_DIR="${DOCS_DIR:-docs/expert}"
KNOWLEDGE_FILE="${KNOWLEDGE_FILE:-KNOWLEDGE.md}"
SKILL_DIR="${SKILL_DIR:-.claude/skills/repo-expert}"
COMMIT_MSG="${1:-}"

# ── colours ──────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${B}→${NC} $*"; }
ok()    { echo -e "${G}✓${NC} $*"; }
warn()  { echo -e "${Y}⚠${NC} $*"; }
err()   { echo -e "${R}✗${NC} $*" >&2; }
hr()    { echo "────────────────────────────────────────────────"; }

# ── prereqs ──────────────────────────────────────────────────────────────────
check_prereqs() {
  if ! command -v claude >/dev/null 2>&1; then
    err "claude CLI not found — install Claude Code: https://claude.ai/code"
    exit 1
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    err "Not inside a git repository"
    exit 1
  fi
}

check_staged() {
  if git diff --cached --quiet; then
    warn "No staged changes found."
    echo "  Stage your files first:  git add <files>"
    echo "  Then re-run:             ./doc-check.sh"
    exit 1
  fi
}

# ── frontmatter helpers ───────────────────────────────────────────────────────
# Extract a scalar frontmatter field value (e.g. git_sha: abc123)
frontmatter_scalar() {
  local file="$1" field="$2"
  awk -v f="$field" '
    /^---$/ { block++; next }
    block == 1 && $0 ~ "^" f ":" { sub("^" f ":[[:space:]]*", ""); print; exit }
  ' "$file"
}

# Extract the source_files list from frontmatter
frontmatter_sources() {
  local file="$1"
  awk '
    /^---$/ { block++; next }
    block == 1 && /^source_files:/ { in_list=1; next }
    block == 1 && in_list && /^  - / { print substr($0, 5); next }
    block == 1 && in_list { exit }
    block == 2 { exit }
  ' "$file"
}

# ── staleness detection ───────────────────────────────────────────────────────
is_stale() {
  local doc="$1"
  local sha
  sha=$(frontmatter_scalar "$doc" "git_sha")
  [[ -z "$sha" ]] && return 1                       # no sha → skip

  local changed
  changed=$(git diff "${sha}..HEAD" --name-only 2>/dev/null || true)
  [[ -z "$changed" ]] && return 1                   # nothing changed

  local src
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    if echo "$changed" | grep -qF "$src"; then
      return 0                                       # stale
    fi
  done < <(frontmatter_sources "$doc")

  return 1
}

collect_stale() {
  local -a stale=()

  # Check KNOWLEDGE.md
  if [[ -f "$KNOWLEDGE_FILE" ]] && is_stale "$KNOWLEDGE_FILE"; then
    stale+=("$KNOWLEDGE_FILE")
  fi

  # Check flow docs
  if [[ -d "$DOCS_DIR" ]]; then
    while IFS= read -r doc; do
      is_stale "$doc" && stale+=("$doc")
    done < <(find "$DOCS_DIR" -name "*.md" -type f | sort)
  fi

  printf '%s\n' "${stale[@]+"${stale[@]}"}"
}

# ── regeneration ─────────────────────────────────────────────────────────────
build_prompt() {
  local doc="$1"
  local sources
  sources=$(frontmatter_sources "$doc")
  local current_sha
  current_sha=$(git rev-parse HEAD)
  local today
  today=$(date +%Y-%m-%d)

  cat <<PROMPT
You are running in repo-expert refresh mode.
Follow the instructions in ${SKILL_DIR}/modes/refresh.md.
Use the doc templates from ${SKILL_DIR}/references/doc-templates.md.

Task: Regenerate the documentation file at path: ${doc}

Steps:
1. Read the current doc to understand its structure and frontmatter
2. Read each of the following source files that changed since last generation:
${sources}
3. Regenerate the doc using the same template structure — preserve all sections
4. In the frontmatter set:
   git_sha: ${current_sha}
   generated: ${today}
5. Output ONLY the complete updated doc content — no explanation, no markdown fences
PROMPT
}

regenerate_doc() {
  local doc="$1"
  local tmp
  tmp=$(mktemp /tmp/doc-check-XXXXXX.md)

  info "Regenerating: $doc"
  local prompt
  prompt=$(build_prompt "$doc")

  if claude --print "$prompt" > "$tmp" 2>/dev/null; then
    echo "$tmp"
  else
    err "Claude failed to regenerate $doc — skipping"
    rm -f "$tmp"
    echo ""
  fi
}

# ── approval UI ──────────────────────────────────────────────────────────────
approve_doc() {
  local original="$1" regenerated="$2"

  echo ""
  hr
  warn "Review changes for: $original"
  hr
  diff --color=always -u "$original" "$regenerated" || true
  hr
  echo ""

  while true; do
    read -rp "  Approve? [y]es / [n]o / [e]dit  → " choice </dev/tty
    case "$choice" in
      y|Y|yes) return 0 ;;
      n|N|no)  return 1 ;;
      e|E|edit)
        "${EDITOR:-vi}" "$regenerated" </dev/tty
        ;;
      *) warn "Enter y, n, or e" ;;
    esac
  done
}

# ── commit + push ─────────────────────────────────────────────────────────────
get_commit_msg() {
  if [[ -n "$COMMIT_MSG" ]]; then
    echo "$COMMIT_MSG"
    return
  fi
  read -rp "Commit message: " msg </dev/tty
  echo "$msg"
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  check_prereqs
  check_staged

  echo ""
  info "Scanning for stale docs..."

  local -a stale=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && stale+=("$line")
  done < <(collect_stale)

  local docs_refreshed=0

  if [[ ${#stale[@]} -eq 0 ]]; then
    ok "All docs are up to date"
  else
    warn "${#stale[@]} stale doc(s) found: ${stale[*]}"
    echo ""

    for doc in "${stale[@]}"; do
      local tmp
      tmp=$(regenerate_doc "$doc")
      [[ -z "$tmp" ]] && continue

      if approve_doc "$doc" "$tmp"; then
        cp "$tmp" "$doc"
        git add "$doc"
        ok "Staged updated doc: $doc"
        (( docs_refreshed++ )) || true
      else
        warn "Skipped: $doc"
      fi
      rm -f "$tmp"
    done

    echo ""
    if (( docs_refreshed > 0 )); then
      ok "$docs_refreshed doc(s) included in commit"
    else
      info "No docs added — committing original staged changes only"
    fi
  fi

  echo ""
  local msg
  msg=$(get_commit_msg)
  [[ -z "$msg" ]] && { err "Commit message cannot be empty"; exit 1; }

  (( docs_refreshed > 0 )) && msg="${msg} [docs refreshed]"

  info "Committing: $msg"
  git commit -m "$msg"
  echo ""

  read -rp "Push now? [Y/n] " push_choice </dev/tty
  if [[ "${push_choice:-Y}" =~ ^[Yy]$ ]]; then
    info "Pushing..."
    git push
    echo ""
    ok "Done — committed and pushed"
  else
    ok "Committed locally. Run 'git push' when ready."
  fi
}

main "$@"
