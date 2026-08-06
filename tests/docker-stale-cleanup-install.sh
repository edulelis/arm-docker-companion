#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

ENV_FILE=/dev/null \
DRY_RUN=1 \
ENABLE_DOCKER_STALE_CLEANUP=1 \
DOCKER_STALE_AFTER_HOURS=72 \
sh -c 'repo=$1; set -- help; . "$repo/install.sh" >/dev/null; configure_docker_stale_cleanup' sh "$repo_dir" \
  >"$test_dir/enabled.out"

grep -Fq 'would install /usr/local/sbin/docker-stale-cleanup' "$test_dir/enabled.out"
grep -Fq 'DOCKER_STALE_AFTER_HOURS=72' "$test_dir/enabled.out"
grep -Fq 'would install /etc/systemd/system/docker-stale-cleanup.timer' "$test_dir/enabled.out"
grep -Fq 'systemctl enable --now docker-stale-cleanup.timer' "$test_dir/enabled.out"

if ENV_FILE=/dev/null \
  DRY_RUN=1 \
  ENABLE_DOCKER_STALE_CLEANUP=1 \
  DOCKER_CLEANUP_IMAGES=maybe \
  sh -c 'repo=$1; set -- help; . "$repo/install.sh" >/dev/null; configure_docker_stale_cleanup' sh "$repo_dir" \
    >"$test_dir/invalid.out" 2>&1; then
  echo 'invalid cleanup boolean unexpectedly accepted' >&2
  exit 1
fi

grep -Fq 'DOCKER_CLEANUP_IMAGES must be 0 or 1' "$test_dir/invalid.out"

printf '%s\n' 'docker stale cleanup installer checks passed'
