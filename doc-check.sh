#!/usr/bin/env bash
# doc-check.sh — regenerate stale repo-expert docs before committing
#
# Modes:
#   --prepare            non-interactive: detect stale docs + regenerate (Claude runs this)
#   --commit [msg]       interactive: approve diffs, commit, push (opened in terminal)
#   [msg]                run both phases in one terminal session (default)
#
# Requires: claude CLI (Claude Code), git

set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
DOCS_DIR="${DOCS_DIR:-docs/expert}"
KNOWLEDGE_FILE="${KNOWLEDGE_FILE:-KNOWLEDGE.md}"
SKILL_DIR="${SKILL_DIR:-.claude/skills/repo-expert}"

# ── arg parsing ───────────────────────────────────────────────────────────────
MODE="full"
COMMIT_MSG=""
case "${1:-}" in
  --prepare) MODE="prepare" ;;
  --commit)  MODE="commit"; COMMIT_MSG="${2:-}" ;;
  *)         MODE="full";   COMMIT_MSG="${1:-}" ;;
esac

# ── manifest path (per-repo, in /tmp) ────────────────────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
REPO_SLUG=$(basename "$REPO_ROOT")
MANIFEST="/tmp/doc-check-${REPO_SLUG}.manifest"

# ── colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${B}→${NC} $*"; }
ok()    { echo -e "${G}✓${NC} $*"; }
warn()  { echo -e "${Y}⚠${NC} $*"; }
err()   { echo -e "${R}✗${NC} $*" >&2; }
hr()    { echo "────────────────────────────────────────────────"; }

# ── prereqs ───────────────────────────────────────────────────────────────────
check_prereqs() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    err "Not inside a git repository"; exit 1
  fi
}

check_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    err "claude CLI not found — install Claude Code: https://claude.ai/code"; exit 1
  fi
}

check_staged() {
  if git diff --cached --quiet; then
    warn "No staged changes found."
    echo "  Stage your files first:  git add <files>"
    exit 1
  fi
}

# ── frontmatter helpers ───────────────────────────────────────────────────────
frontmatter_scalar() {
  local file="$1" field="$2"
  awk -v f="$field" '
    /^---$/ { block++; next }
    block == 1 && $0 ~ "^" f ":" { sub("^" f ":[[:space:]]*", ""); print; exit }
  ' "$file"
}

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
  [[ -z "$sha" ]] && return 1

  local changed
  changed=$(git diff "${sha}..HEAD" --name-only 2>/dev/null || true)
  [[ -z "$changed" ]] && return 1

  local src
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    echo "$changed" | grep -qF "$src" && return 0
  done < <(frontmatter_sources "$doc")

  return 1
}

collect_stale() {
  [[ -f "$KNOWLEDGE_FILE" ]] && is_stale "$KNOWLEDGE_FILE" && echo "$KNOWLEDGE_FILE"

  if [[ -d "$DOCS_DIR" ]]; then
    while IFS= read -r doc; do
      is_stale "$doc" && echo "$doc"
    done < <(find "$DOCS_DIR" -name "*.md" -type f | sort)
  fi
}

# ── regeneration (non-interactive) ───────────────────────────────────────────
build_prompt() {
  local doc="$1"
  local sources current_sha today
  sources=$(frontmatter_sources "$doc")
  current_sha=$(git rev-parse --short HEAD)
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
  if claude --print "$(build_prompt "$doc")" > "$tmp" 2>/dev/null; then
    echo "$tmp"
  else
    err "Claude failed to regenerate $doc — skipping"
    rm -f "$tmp"
    echo ""
  fi
}

# ── PHASE 1: prepare (non-interactive, Claude runs this) ─────────────────────
cmd_prepare() {
  check_prereqs
  check_claude
  check_staged

  rm -f "$MANIFEST"
  echo ""
  info "Scanning for stale docs..."

  local -a stale=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && stale+=("$line")
  done < <(collect_stale)

  if [[ ${#stale[@]} -eq 0 ]]; then
    ok "All docs are up to date — nothing to regenerate"
    echo "NONE" > "$MANIFEST"
    return
  fi

  warn "${#stale[@]} stale doc(s) found"
  local count=0

  for doc in "${stale[@]}"; do
    local tmp
    tmp=$(regenerate_doc "$doc")
    if [[ -n "$tmp" ]]; then
      printf '%s\t%s\n' "$doc" "$tmp" >> "$MANIFEST"
      (( count++ )) || true
    fi
  done

  echo ""
  ok "$count doc(s) regenerated → manifest saved to $MANIFEST"
  info "Now run:  ./doc-check.sh --commit"
}

# ── diff helpers ─────────────────────────────────────────────────────────────
# Strip YAML frontmatter block (between first two ---), output body only
strip_frontmatter() {
  awk '/^---$/{c++; if(c==2){found=1; next}} found{print}' "$1"
}

# Show compact frontmatter summary + content-only diff
show_diff() {
  local original="$1" regenerated="$2"

  local old_sha new_sha old_date new_date
  old_sha=$(frontmatter_scalar "$original"   "git_sha")
  new_sha=$(frontmatter_scalar "$regenerated" "git_sha")
  old_date=$(frontmatter_scalar "$original"   "generated")
  new_date=$(frontmatter_scalar "$regenerated" "generated")

  echo -e "  ${Y}metadata${NC}  generated: ${old_date} → ${new_date}   git_sha: ${old_sha} → ${new_sha}"
  echo ""

  local tmp_a tmp_b
  tmp_a=$(mktemp); tmp_b=$(mktemp)
  strip_frontmatter "$original"    > "$tmp_a"
  strip_frontmatter "$regenerated" > "$tmp_b"
  diff --color=always -u "$tmp_a" "$tmp_b" || true
  rm -f "$tmp_a" "$tmp_b"
}

# ── PHASE 2: commit (interactive, runs in terminal) ──────────────────────────
cmd_commit() {
  check_prereqs
  check_staged

  local docs_refreshed=0

  if [[ ! -f "$MANIFEST" ]]; then
    warn "No manifest found at $MANIFEST"
    info "Run './doc-check.sh --prepare' first, or use './doc-check.sh' to run both phases"
    exit 1
  fi

  local first_line
  first_line=$(head -1 "$MANIFEST")

  if [[ "$first_line" != "NONE" ]]; then
    while IFS=$'\t' read -r original tmp; do
      [[ -z "$original" || -z "$tmp" ]] && continue
      [[ ! -f "$tmp" ]] && { warn "Temp file missing for $original — skipping"; continue; }

      echo ""
      hr
      warn "Review: $original"
      hr
      show_diff "$original" "$tmp"
      hr
      echo ""

      while true; do
        read -rp "  Approve? [y]es / [n]o / [e]dit  → " choice </dev/tty
        case "$choice" in
          y|Y|yes)
            cp "$tmp" "$original"
            git add "$original"
            ok "Staged: $original"
            (( docs_refreshed++ )) || true
            break ;;
          n|N|no)
            warn "Skipped: $original"
            break ;;
          e|E|edit)
            "${EDITOR:-vi}" "$tmp" </dev/tty ;;
          *) warn "Enter y, n, or e" ;;
        esac
      done
      rm -f "$tmp"
    done < "$MANIFEST"
  fi

  rm -f "$MANIFEST"

  echo ""
  if [[ -z "$COMMIT_MSG" ]]; then
    read -rp "Commit message: " COMMIT_MSG </dev/tty
  fi
  [[ -z "$COMMIT_MSG" ]] && { err "Commit message cannot be empty"; exit 1; }

  (( docs_refreshed > 0 )) && COMMIT_MSG="${COMMIT_MSG} [docs refreshed]"

  info "Committing: $COMMIT_MSG"
  git commit -m "$COMMIT_MSG"
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

# ── full (single terminal, both phases) ──────────────────────────────────────
cmd_full() {
  cmd_prepare
  echo ""
  cmd_commit
}

# ── dispatch ──────────────────────────────────────────────────────────────────
case "$MODE" in
  prepare) cmd_prepare ;;
  commit)  cmd_commit  ;;
  full)    cmd_full    ;;
esac
