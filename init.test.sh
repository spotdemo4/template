#!/usr/bin/env bash
# The tests often single-quote text containing $
# shellcheck disable=SC2016

# Tests init.sh. The init flake check runs it from a copy of the template.

set -euo pipefail

# shellcheck source=init.sh
source ./init.sh

template=$PWD
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config GIT_CONFIG_NOSYSTEM=1
mkdir "$HOME"

fail() {
  printf 'not ok: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local actual=$1 expected=$2 name=$3
  if [[ $actual != "$expected" ]]; then
    fail "$name: expected '$expected', got '$actual'"
  fi
}

# Runs a command that must fail with the expected output.
assert_fails() {
  local expected=$1 output
  shift
  if output=$("$@" 2>&1); then
    fail "$* succeeded"
  fi
  assert_eq "$output" "$expected" "$*"
}

assert_contains() {
  local file=$1 text
  shift
  for text in "$@"; do
    grep -qF -- "$text" "$file" || fail "$file does not contain '$text'"
  done
}

assert_lacks() {
  local file=$1 text
  shift
  for text in "$@"; do
    if grep -qF -- "$text" "$file"; then
      fail "$file contains '$text'"
    fi
  done
}

assert_missing() {
  local path
  for path in "$@"; do
    if [[ -e $path ]]; then
      fail "$path exists"
    fi
  done
}

test_parse_remote() {
  local url expected
  while read -r url expected; do
    parse_remote 'Origin URL' "$url"
    assert_eq "$remote_host $remote_repo_path $remote_web_url" "$expected" "parse_remote $url"
  done <<'EOF'
https://github.com/octo/hello.git github.com octo/hello https://github.com/octo/hello
http://user@git.example.com:3000/octo/hello git.example.com:3000 octo/hello http://git.example.com:3000/octo/hello
git@github.com:octo/hello.git github.com octo/hello https://github.com/octo/hello
ssh://git@git.example.com:2222/group/sub/hello.git git.example.com group/sub/hello https://git.example.com/group/sub/hello
EOF

  assert_fails 'Origin URL cannot contain a query string or fragment.' parse_remote 'Origin URL' 'https://github.com/octo/hello?tab=readme'
  assert_fails 'Unsupported repository URL.' parse_remote 'Repository URL' 'ftp://github.com/octo/hello'
  assert_fails 'Origin URL must identify an owner and repository.' parse_remote 'Origin URL' 'git@github.com:hello.git'
  assert_fails 'Origin URL contains unsupported host or path characters.' parse_remote 'Origin URL' 'https://github.com/octo/hello world'
}

test_nix_string() {
  assert_eq "$(nix_string 'Say "hi" to ${USER} \o/')" 'Say \"hi\" to \${USER} \\o/' nix_string
}

# Creates the template's upstream repository, which init.sh fetches to find the
# template commit.
create_upstream() {
  git init --quiet "$tmp/upstream"
  cp -a "$template/." "$tmp/upstream"
  git -C "$tmp/upstream" add -A
  git -C "$tmp/upstream" commit --quiet --message 'feat: template'
  git config --global url."$tmp/upstream".insteadOf "$old_url"
  upstream_commit=$(git -C "$tmp/upstream" rev-parse HEAD)
}

# Copies the template into a new repository with an origin remote.
new_project() {
  local dir=$1 origin=$2
  git init --quiet "$dir"
  cp -a "$template/." "$dir"
  git -C "$dir" remote add origin "$origin"
}

# Checks what init.sh does for every project in the current directory.
assert_initialized() {
  local email=$1
  assert_missing init.sh init.test.sh template.schema.json
  assert_eq "$(git log --format='%an <%ae> %s')" "Test User <$email> chore: initialize project" 'commits'
  assert_eq "$(git status --porcelain --untracked-files=all)" '' 'worktree status'
  assert_eq "$(jq -r .commit .template.json)" "$upstream_commit" '.template.json commit'
  assert_eq "$(git grep -n -e spotdemo4/template -e trev.zip/template -e template/default -e 'default template' -e init.sh -e init.test.sh -- ':!.template.json' ':!AGENTS.md' || true)" '' 'template references'
  assert_contains LICENSE "Copyright (c) $(date +%Y) Test User"
}

test_application() (
  local project=$tmp/hello-world description='Says "hi" to ${USER} \o/'
  new_project "$project" git@github.com:octo/hello-world.git
  cd "$project"
  # "use this template" creates a new commit with the template's tree
  git add -A
  git commit --quiet --message 'Initial commit'
  # The build sandbox has no /usr/bin/env for the shebang
  # GitHub (detected), no Gitea, Forgejo mirror, Zed, VS Code
  printf '%s\n' '' n y https://git.example.com/octo/hello-world '' '' | bash ./init.sh 'Hello World' "$description"

  assert_initialized test@example.com
  assert_eq "$(git remote)" $'forgejo\norigin' remotes
  assert_eq "$(head -n 1 README.md)" '# Hello World' 'README title'
  assert_contains README.md "$description" \
    'https://github.com/octo/hello-world/actions/workflows/check.yaml' \
    '## contributing'
  assert_contains flake.nix \
    'description = "Says \"hi\" to \${USER} \\o/";' \
    'actions-gh = {' 'actions-fj = {'
  assert_lacks flake.nix 'init = {' 'templates = {' 'actions-gt = {' 'renovate-gt = {'
  assert_missing .gitea
  assert_lacks .gitattributes 'Linguist: exclude template'
  assert_contains .github/renovate.jsonc '"repositories": ["octo/hello-world"]'
  assert_contains .forgejo/renovate.jsonc \
    '"endpoint": "https://git.example.com/api/v1"' \
    '"repositories": ["octo/hello-world"]'
  [[ -d .zed && -d .vscode ]] || fail 'editor settings are missing'
)

test_flake_init() (
  local project=$tmp/hello-forgejo
  new_project "$project" https://git.example.com/octo/hello-forgejo.git
  cd "$project"
  # nix flake init leaves the template uncommitted and init.sh not executable
  chmod -x init.sh
  # Forgejo (detected), no GitHub, no Gitea, no Zed, no VS Code
  printf '%s\n' '' n n n n | bash init.sh 'Hello Forgejo' 'Says hello'

  assert_initialized test@example.com
  assert_eq "$(git remote)" origin remotes
  assert_missing .github .gitea .zed .vscode
  assert_contains README.md \
    'https://git.example.com/octo/hello-forgejo/actions?workflow=check.yaml' \
    'logo=forgejo'
  assert_contains flake.nix 'description = "Says hello";' 'actions-fj = {'
  assert_lacks flake.nix 'actions-gh = {' 'renovate-gh = {' 'actions-gt = {' 'renovate-gt = {'
  assert_contains .forgejo/renovate.jsonc '"repositories": ["octo/hello-forgejo"]'
)

test_gitea() (
  local project=$tmp/hello-gitea
  new_project "$project" https://gitea.example.com/octo/hello-gitea.git
  cd "$project"
  git add -A
  git commit --quiet --message 'Initial commit'
  # Gitea, GitHub mirror, no Forgejo, no Zed, no VS Code
  printf '%s\n' Gitea y git@github.com:octo/hello-mirror.git n n n | bash ./init.sh 'Hello Gitea' 'Says hello'

  assert_initialized test@example.com
  assert_eq "$(git remote)" $'github\norigin' remotes
  assert_eq "$(git remote get-url github)" git@github.com:octo/hello-mirror.git 'github remote'
  assert_missing .forgejo .zed .vscode
  assert_contains README.md \
    'https://gitea.example.com/octo/hello-gitea/actions?workflow=check.yaml' \
    'logo=gitea'
  assert_contains flake.nix 'actions-gt = {' 'renovate-gt = {' 'actions-gh = {' 'renovate-gh = {'
  assert_lacks flake.nix 'actions-fj = {' 'renovate-fj = {'
  assert_contains .gitea/renovate.jsonc \
    '"platform": "gitea"' \
    '"endpoint": "https://gitea.example.com/api/v1"' \
    '"repositories": ["octo/hello-gitea"]'
  assert_contains .github/renovate.jsonc '"repositories": ["octo/hello-mirror"]'
)

test_rollback() (
  local project=$tmp/rollback head
  new_project "$project" git@github.com:octo/rollback.git
  cd "$project"
  git add -A
  git commit --quiet --message 'Initial commit'
  head=$(git rev-parse HEAD)

  touch untracked
  assert_fails 'Commit or discard all existing worktree changes before running the initializer.' \
    bash ./init.sh Rollback Rollback </dev/null
  rm untracked

  # The forge is checked before the template is changed
  assert_fails 'Forge must be github, gitea or forgejo.' \
    bash ./init.sh Rollback Rollback < <(printf '%s\n' gitlab)
  assert_fails 'Gitea origin URL cannot use github.com.' \
    bash ./init.sh Rollback Rollback < <(printf '%s\n' gitea)

  # Mirror URLs are read after the template has been changed
  assert_fails 'Unsupported repository URL.' \
    bash ./init.sh Rollback Rollback < <(printf '%s\n' '' n y ftp://git.example.com/octo/rollback)
  assert_fails 'Gitea repository URL cannot use github.com.' \
    bash ./init.sh Rollback Rollback < <(printf '%s\n' github y https://github.com/octo/rollback)
  assert_eq "$(git rev-parse HEAD)" "$head" HEAD
  assert_eq "$(git status --porcelain --untracked-files=all)" '' 'worktree status'
  assert_missing "$tmp"/.rollback.git-*
)

git config --global user.name 'Test User'
git config --global user.email test@example.com
git config --global init.defaultBranch main

# nix fmt can't evaluate the flake in the build sandbox, so run its formatter
mkdir "$tmp/bin"
printf '#!%s\n[[ $* == fmt ]] && TREEFMT_TREE_ROOT=$PWD exec treefmt\nexit 1\n' "$BASH" >"$tmp/bin/nix"
chmod +x "$tmp/bin/nix"
PATH=$tmp/bin:$PATH

create_upstream
for test in test_parse_remote test_nix_string test_application test_flake_init test_gitea test_rollback; do
  "$test"
  printf 'ok: %s\n' "$test"
done
