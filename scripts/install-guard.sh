#!/bin/sh
# Installs the push and post guard outside the checkout (CLAUDE.md → Commands → Guard). The owner
# runs origin's main copy of this script, never the working tree's, as a stream from any checkout of
# this repository, once per clone, after every merged change to scripts/guard/, scripts/xcbuild.sh or
# scripts/check-project-scripts.mjs, and after creating a worktree (the exact command is in CLAUDE.md). It finds the repository from the current folder,
# refuses unless origin is this GitHub repository, asks origin for main's commit with git ls-remote
# (never trusting the local origin/main) and requires that commit here. It installs the guard's
# files from that commit, never from the working tree, so neither an edit nor an index flag
# (--skip-worktree, --assume-unchanged) in the checkout reaches the installed copy. Then it builds
# the guard folder (and a config.json naming the deny-list and the scratchpad root of every
# worktree) under a temporary name and swaps it in, writes the git hook and the gh-post command that
# run it, and points core.hooksPath (this repository only) at the absolute hook folder last. The
# folder also gets main's build script and project check, and bin/ the xcbuild command that runs
# them in a cleared environment (H1c): the only build the local settings allow.
# MOONSHINE_GUARD_DIR, MOONSHINE_SCRATCH_BASE and MOONSHINE_ORIGIN_URL override the two locations
# and the expected origin (tests use them).
set -eu

fail() {
  echo "install-guard: $1" >&2
  exit 1
}

[ $# -eq 1 ] || fail "usage: run origin's main copy of the installer with the absolute path of the deny-list (CLAUDE.md → Commands → Guard)."
deny_list=$1
dir=${MOONSHINE_GUARD_DIR:-$HOME/.config/moonshine}
base=${MOONSHINE_SCRATCH_BASE:-/private/tmp/claude-$(id -u)}
expected=${MOONSHINE_ORIGIN_URL:-https://github.com/Ruslan-Mz/moonshine.git}

# The build wrapper's PATH names node's folder, as found now (H1c); after that folder changes (a
# node upgrade), the owner reinstalls.
node_bin=$(command -v node) || fail "node is not on PATH; install node, then run the installer again."
node_dir=$(dirname "$node_bin")

# The guard folder and node's are written into generated scripts: refuse characters that would need quoting.
for path in "$dir" "$base" "$deny_list" "$node_dir"; do
  case $path in
    /*) ;;
    *) fail "$path is not absolute." ;;
  esac
  case $path in
    *\'* | *\"* | *\\* | *[[:cntrl:]]*) fail "a path contains a quote, a backslash or a control character." ;;
  esac
done
[ -f "$deny_list" ] && [ -r "$deny_list" ] || fail "the deny-list is not a readable file."

top=$(git rev-parse --show-toplevel 2> /dev/null) || fail "run it inside a checkout of this repository."
cd "$top"
# The URLs git really uses (insteadOf applied), for fetching and for pushing.
[ "$(git remote get-url origin 2> /dev/null)" = "$expected" ] &&
  [ "$(git remote get-url --push origin 2> /dev/null)" = "$expected" ] ||
  fail "origin is not $expected; run it inside a checkout of this repository."

heads=$(git ls-remote origin refs/heads/main) || fail "origin cannot be reached."
main=$(printf '%s\n' "$heads" | awk -F '\t' '$2 == "refs/heads/main" { print $1 }')
[ -n "$main" ] || fail "origin has no main."
git cat-file -e "$main^{commit}" 2> /dev/null || fail "origin's main is not here yet; run git fetch origin first."

mkdir -p "$dir/hooks" "$dir/bin"
stage=$(mktemp -d "$dir/guard.new.XXXXXX")
trap 'rm -rf "$stage" "$stage.old"' EXIT
for file in matcher.mjs commit-scan.mjs pre-push.mjs gh-post.mjs binary-allowlist.txt; do
  git cat-file blob "$main:scripts/guard/$file" > "$stage/$file" ||
    fail "origin's main has no scripts/guard/$file; the old guard is unchanged."
done
# The build's script and the project check it runs first (H1c).
for file in xcbuild.sh check-project-scripts.mjs; do
  git cat-file blob "$main:scripts/$file" > "$stage/$file" ||
    fail "origin's main has no scripts/$file; the old guard is unchanged."
done
chmod 755 "$stage"

# config.json: the deny-list and one scratchpad root per worktree git lists (a prunable one has no
# folder left). The paths reach node as arguments, never as part of the script.
node -e '
const { execFileSync } = require("node:child_process");
const { writeFileSync } = require("node:fs");
const [out, denyList, base] = process.argv.slice(1);
const scratchRoots = [];
for (const record of execFileSync("git", ["worktree", "list", "--porcelain", "-z"], { encoding: "utf8" }).split("\0\0")) {
  const lines = record.split("\0");
  const path = lines.find((line) => line.startsWith("worktree "))?.slice("worktree ".length);
  if (!path || lines.some((line) => line === "prunable" || line.startsWith("prunable "))) continue;
  scratchRoots.push(`${base}/${path.replace(/[^A-Za-z0-9]/g, "-")}`);
}
if (scratchRoots.length === 0) throw new Error("git listed no worktree");
writeFileSync(out, JSON.stringify({ denyList, scratchRoots }, null, 2) + "\n");
' "$stage/config.json" "$deny_list" "$base" || fail "config.json could not be written; the old guard is unchanged."

# Swap: between the two renames a push or post finds no guard and is blocked.
if [ -d "$dir/guard" ]; then mv "$dir/guard" "$stage.old"; fi
mv "$stage" "$dir/guard"

printf '#!/bin/sh\n# Generated by scripts/install-guard.sh. Without node, the push is blocked.\nexec node '\''%s/guard/pre-push.mjs'\'' "$@"\n' "$dir" > "$dir/hooks/pre-push.new"
printf '#!/bin/sh\n# Generated by scripts/install-guard.sh.\nexec node '\''%s/guard/gh-post.mjs'\'' "$@"\n' "$dir" > "$dir/bin/gh-post.new"
printf '#!/bin/sh\n# Generated by scripts/install-guard.sh. Builds the current folder with main'\''s build script and check, in a cleared environment.\nexec /usr/bin/env -i HOME="$HOME" PATH='\''/usr/bin:/bin:/usr/sbin:/sbin:%s:/opt/homebrew/bin:/usr/local/bin'\'' /bin/sh '\''%s/guard/xcbuild.sh'\'' "$@"\n' "$node_dir" "$dir" > "$dir/bin/xcbuild.new"
chmod 755 "$dir/hooks/pre-push.new" "$dir/bin/gh-post.new" "$dir/bin/xcbuild.new"
mv -f "$dir/hooks/pre-push.new" "$dir/hooks/pre-push"
mv -f "$dir/bin/gh-post.new" "$dir/bin/gh-post"
mv -f "$dir/bin/xcbuild.new" "$dir/bin/xcbuild"

git config core.hooksPath "$dir/hooks"

echo "install-guard: guard installed in $dir from origin's main $main; core.hooksPath set for $top."
echo "install-guard: gh-post is $dir/bin/gh-post; scratchpad roots under $base."
echo "install-guard: the build is $dir/bin/xcbuild build|test, run from a checkout's root."
