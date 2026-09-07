#!/usr/bin/env sh
# Prove empty-index policy checks never enter prek's stash/restore path.
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$repo_root/Scripts/lib/repo_policy_checks.sh"
# A hook caller may route Git to a different index or repository through its
# environment. This fixture owns only its disposable repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS \
  GIT_CONFIG_COUNT GIT_PREFIX GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_NAMESPACE \
  GIT_QUARANTINE_PATH
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
fixture_repo="$scratch/repo"
mkdir -p "$fixture_repo" "$scratch/bin"
git init -q "$fixture_repo"
git -C "$fixture_repo" config core.hooksPath "$scratch/no-hooks"
printf 'original\n' > "$fixture_repo/tracked"
git -C "$fixture_repo" add tracked
git -C "$fixture_repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
  -c commit.gpgsign=false \
  commit -qm initial
printf 'unstaged\n' > "$fixture_repo/tracked"
cp "$fixture_repo/tracked" "$scratch/expected"
export PREK_FIXTURE_LOG="$scratch/prek.log"
export PREK_FIXTURE_STATUS=0
cat > "$scratch/bin/prek" <<'SH'
#!/usr/bin/env sh
printf '%s:%s\n' "$PWD" "$*" >> "$PREK_FIXTURE_LOG"
exit "$PREK_FIXTURE_STATUS"
SH
chmod +x "$scratch/bin/prek"
PATH="$scratch/bin:$PATH"
export PATH

run_staged_prek_hooks "$fixture_repo"
test ! -e "$PREK_FIXTURE_LOG"
cmp "$fixture_repo/tracked" "$scratch/expected"
git -C "$fixture_repo" diff --cached --quiet --exit-code --

git -C "$fixture_repo" add tracked
printf 'later unstaged\n' > "$fixture_repo/tracked"
cp "$fixture_repo/tracked" "$scratch/expected"
run_staged_prek_hooks "$fixture_repo"
test "$(cat "$PREK_FIXTURE_LOG")" = "$fixture_repo:run"
cmp "$fixture_repo/tracked" "$scratch/expected"
test "$(git -C "$fixture_repo" show :tracked)" = unstaged

PREK_FIXTURE_STATUS=23
export PREK_FIXTURE_STATUS
if run_staged_prek_hooks "$fixture_repo"; then
  echo 'expected prek failure' >&2
  exit 1
else
  test "$?" -eq 23
fi
cmp "$fixture_repo/tracked" "$scratch/expected"

# Mock only the index-inspection command; an error must not masquerade as an
# empty index or cause the hook runner to execute.
before=$(wc -l < "$PREK_FIXTURE_LOG")
git() { return 17; }
if run_staged_prek_hooks "$fixture_repo"; then
  echo 'expected index-inspection failure' >&2
  exit 1
else
  test "$?" -eq 17
fi
test "$(wc -l < "$PREK_FIXTURE_LOG")" -eq "$before"
cmp "$fixture_repo/tracked" "$scratch/expected"

git() { return 1; }
if run_staged_prek_hooks "$scratch/missing-directory" 2>/dev/null; then
  echo 'expected directory-entry failure' >&2
  exit 1
fi
test "$(wc -l < "$PREK_FIXTURE_LOG")" -eq "$before"
echo '[check_prek_scope] five cases passed; caller worktree and index untouched'
