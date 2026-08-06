#!/usr/bin/env bash
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "docker-stale-cleanup requires Bash 4 or newer" >&2
  exit 69
fi

CONFIG_FILE="${DOCKER_STALE_CLEANUP_CONFIG:-/etc/default/docker-stale-cleanup}"
if [[ -r "${CONFIG_FILE}" ]]; then
  # The file is installed root-owned and uses shell-compatible key/value syntax.
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

MODE="${1:-prune}"
LOCK_FILE="/run/lock/docker-stale-cleanup.lock"
DOCKER_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
LOG_PREFIX="[docker-stale-cleanup]"
CLEANUP_ENABLED="${DOCKER_STALE_CLEANUP_ENABLED:-false}"
REQUIRE_DATA_ROOT_MOUNT="${DOCKER_REQUIRE_DATA_ROOT_MOUNT:-false}"
STALE_AFTER_HOURS="${DOCKER_STALE_AFTER_HOURS:-168}"
PROTECTED_NAME_REGEX="${DOCKER_PROTECTED_NAME_REGEX:-^buildx_buildkit_.*$}"
KEEP_LABEL="${DOCKER_CLEANUP_KEEP_LABEL:-docker.cleanup.keep}"
CLEANUP_STALE_CONTAINERS="${DOCKER_CLEANUP_STALE_CONTAINERS:-true}"
CLEANUP_RUNNING_CONTAINERS="${DOCKER_CLEANUP_RUNNING_CONTAINERS:-false}"
CLEANUP_CONTAINER_VOLUMES="${DOCKER_CLEANUP_CONTAINER_VOLUMES:-false}"
CLEANUP_UNUSED_VOLUMES="${DOCKER_CLEANUP_UNUSED_VOLUMES:-false}"
CLEANUP_IMAGES="${DOCKER_CLEANUP_IMAGES:-true}"
CLEANUP_NETWORKS="${DOCKER_CLEANUP_NETWORKS:-true}"
CLEANUP_BUILD_CACHE="${DOCKER_CLEANUP_BUILD_CACHE:-true}"
DRY_RUN=0

log() {
  echo "${LOG_PREFIX} $*"
}

available_bytes() {
  df -B1 --output=avail "${DOCKER_ROOT}" | awk 'NR == 2 { print $1 }'
}

is_kept() {
  case "${1,,}" in
    1|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

created_epoch() {
  date --date="$1" +%s 2>/dev/null
}

status() {
  local active="no"
  local mount_source="missing"

  if systemctl is-active --quiet docker.service; then
    active="yes"
  fi

  mount_source="$(findmnt -rn -o SOURCE -T "${DOCKER_ROOT}" 2>/dev/null || echo missing)"
  echo "docker_active=${active}"
  echo "docker_root=${DOCKER_ROOT}"
  echo "docker_mount_source=${mount_source}"
  echo "available_bytes=$(available_bytes)"
  echo "cleanup_enabled=${CLEANUP_ENABLED}"
  echo "require_data_root_mount=${REQUIRE_DATA_ROOT_MOUNT}"
  echo "stale_after_hours=${STALE_AFTER_HOURS}"
  echo "cleanup_stale_containers=${CLEANUP_STALE_CONTAINERS}"
  echo "cleanup_running_containers=${CLEANUP_RUNNING_CONTAINERS}"
  echo "cleanup_container_volumes=${CLEANUP_CONTAINER_VOLUMES}"
  echo "cleanup_unused_volumes=${CLEANUP_UNUSED_VOLUMES}"
  echo "cleanup_images=${CLEANUP_IMAGES}"
  echo "cleanup_networks=${CLEANUP_NETWORKS}"
  echo "cleanup_build_cache=${CLEANUP_BUILD_CACHE}"
  echo "protected_name_regex=${PROTECTED_NAME_REGEX}"
  echo "keep_label=${KEEP_LABEL}=true"
}

prune_old_docker_objects() {
  local output_file="$1"
  local age_filter="until=${STALE_AFTER_HOURS}h"
  local summary

  if is_kept "${CLEANUP_IMAGES}"; then
    if ! docker image prune --all --force --filter "${age_filter}" >"${output_file}" 2>&1; then
      log "image cleanup failed; last output follows" >&2
      tail -n 50 "${output_file}" >&2
      return 1
    fi
    summary="$(tail -n 1 "${output_file}")"
    log "images: ${summary}"
  else
    log "image cleanup disabled"
  fi

  if is_kept "${CLEANUP_NETWORKS}"; then
    if ! docker network prune --force --filter "${age_filter}" >"${output_file}" 2>&1; then
      log "network cleanup failed; last output follows" >&2
      tail -n 50 "${output_file}" >&2
      return 1
    fi
    summary="$(tail -n 1 "${output_file}")"
    log "networks: ${summary}"
  else
    log "network cleanup disabled"
  fi

  if is_kept "${CLEANUP_BUILD_CACHE}"; then
    if ! docker builder prune --all --force --filter "${age_filter}" >"${output_file}" 2>&1; then
      log "build-cache cleanup failed; last output follows" >&2
      tail -n 50 "${output_file}" >&2
      return 1
    fi
    summary="$(tail -n 1 "${output_file}")"
    log "build cache: ${summary}"
  else
    log "build-cache cleanup disabled"
  fi
}

prune() {
  local before after reclaimed output_file cleanup_trap now cutoff
  local id name created project keep container_status group epoch volume
  local inspect_format volume_inspect_format
  local -a remove_args=()
  local -a all_ids=() target_ids=() all_volumes=()
  local -A id_group=() group_newest=() group_keep=() group_active=()
  local -A group_names=() target_groups=() target_volumes=() used_volumes=()

  if [[ ! "${STALE_AFTER_HOURS}" =~ ^[0-9]+$ ]] || (( STALE_AFTER_HOURS < 1 )); then
    log "DOCKER_STALE_AFTER_HOURS must be a positive integer" >&2
    return 64
  fi

  if (( ! DRY_RUN )) && ! is_kept "${CLEANUP_ENABLED}"; then
    log "cleanup is disabled; set DOCKER_STALE_CLEANUP_ENABLED=true to opt in"
    return 0
  fi

  if ! systemctl is-active --quiet docker.service; then
    log "Docker is inactive; skipping cleanup"
    return 0
  fi

  if is_kept "${REQUIRE_DATA_ROOT_MOUNT}" && ! mountpoint -q "${DOCKER_ROOT}"; then
    log "${DOCKER_ROOT} is not a mountpoint; refusing cleanup" >&2
    return 1
  fi

  if ! docker info >/dev/null; then
    log "Docker is not responding; refusing cleanup" >&2
    return 1
  fi

  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    log "another cleanup is already running; skipping"
    return 0
  fi

  before="$(available_bytes)"
  now="$(date +%s)"
  cutoff=$((now - STALE_AFTER_HOURS * 3600))
  log "starting cleanup with ${before} bytes available; stale threshold is ${STALE_AFTER_HOURS} hours"

  mapfile -t all_ids < <(docker container ls --all --quiet --no-trunc)
  inspect_format="{{.Id}}|{{.Name}}|{{.Created}}|{{index .Config.Labels \"com.docker.compose.project\"}}|{{index .Config.Labels \"${KEEP_LABEL}\"}}|{{.State.Status}}"

  if (( ${#all_ids[@]} > 0 )); then
    while IFS='|' read -r id name created project keep container_status; do
      name="${name#/}"
      if [[ -z "${project}" || "${project}" == "<no value>" ]]; then
        group="container:${id}"
      else
        group="project:${project}"
      fi

      id_group["${id}"]="${group}"
      group_names["${group}"]+="${name} "

      if ! epoch="$(created_epoch "${created}")"; then
        log "cannot parse creation time for ${name}; preserving its group" >&2
        group_keep["${group}"]=1
        continue
      fi

      if [[ -z "${group_newest[${group}]:-}" ]] || (( epoch > group_newest[${group}] )); then
        group_newest["${group}"]="${epoch}"
      fi

      if [[ "${name}" =~ ${PROTECTED_NAME_REGEX} ]] || is_kept "${keep}"; then
        group_keep["${group}"]=1
      fi

      case "${container_status}" in
        running|restarting|paused) group_active["${group}"]=1 ;;
      esac
    done < <(docker container inspect --format "${inspect_format}" "${all_ids[@]}")

    if is_kept "${CLEANUP_STALE_CONTAINERS}"; then
      for id in "${all_ids[@]}"; do
        group="${id_group[${id}]}"
        if [[ "${group_keep[${group}]:-0}" != 1 ]] \
          && { is_kept "${CLEANUP_RUNNING_CONTAINERS}" || [[ "${group_active[${group}]:-0}" != 1 ]]; } \
          && (( ${group_newest[${group}]} <= cutoff )); then
          target_ids+=("${id}")
          target_groups["${group}"]=1
        fi
      done
    else
      log "stale-container cleanup disabled"
    fi
  fi

  if (( ${#target_groups[@]} > 0 )); then
    while IFS= read -r group; do
      log "stale target ${group}: ${group_names[${group}]}"
    done < <(printf '%s\n' "${!target_groups[@]}" | sort)
  else
    log "no stale containers found"
  fi

  if (( ${#target_ids[@]} > 0 )); then
    if is_kept "${CLEANUP_CONTAINER_VOLUMES}"; then
      while IFS= read -r volume; do
        [[ -n "${volume}" ]] && target_volumes["${volume}"]=1
      done < <(docker container inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' "${target_ids[@]}")
    fi

    if (( DRY_RUN )); then
      log "plan: would remove ${#target_ids[@]} containers; attached volumes selected=${#target_volumes[@]}"
    else
      log "disabling restart policies for ${#target_ids[@]} stale containers"
      if ! docker container update --restart=no "${target_ids[@]}" >/dev/null; then
        log "could not disable every stale container restart policy; refusing partial cleanup" >&2
        return 1
      fi

      log "removing ${#target_ids[@]} stale containers"
      remove_args=(--force)
      if is_kept "${CLEANUP_CONTAINER_VOLUMES}"; then
        remove_args+=(--volumes)
      fi
      if ! docker container rm "${remove_args[@]}" "${target_ids[@]}" >/dev/null; then
        log "could not remove every stale container; attached volumes were retained for safety" >&2
        return 1
      fi

      if is_kept "${CLEANUP_CONTAINER_VOLUMES}"; then
        for volume in "${!target_volumes[@]}"; do
          if docker volume rm "${volume}" >/dev/null 2>&1; then
            log "removed stale attached volume ${volume}"
          else
            log "retained attached volume ${volume}; it is still in use or protected"
          fi
        done
      fi
    fi
  fi

  if (( DRY_RUN )); then
    log "plan complete; no Docker objects were changed"
    return 0
  fi

  if is_kept "${CLEANUP_UNUSED_VOLUMES}"; then
    mapfile -t all_ids < <(docker container ls --all --quiet --no-trunc)
    if (( ${#all_ids[@]} > 0 )); then
      while IFS= read -r volume; do
        [[ -n "${volume}" ]] && used_volumes["${volume}"]=1
      done < <(docker container inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' "${all_ids[@]}")
    fi

    mapfile -t all_volumes < <(docker volume ls --quiet)
    volume_inspect_format="{{.Name}}|{{.CreatedAt}}|{{index .Labels \"${KEEP_LABEL}\"}}"
    if (( ${#all_volumes[@]} > 0 )); then
      while IFS='|' read -r volume created keep; do
        [[ -n "${used_volumes[${volume}]:-}" ]] && continue
        is_kept "${keep}" && continue
        [[ "${volume}" =~ ^buildx_buildkit_.* ]] && continue

        if ! epoch="$(created_epoch "${created}")"; then
          log "cannot parse creation time for volume ${volume}; preserving it" >&2
          continue
        fi
        if (( epoch <= cutoff )); then
          if docker volume rm "${volume}" >/dev/null 2>&1; then
            log "removed stale unused volume ${volume}"
          else
            log "could not remove stale unused volume ${volume}" >&2
          fi
        fi
      done < <(docker volume inspect --format "${volume_inspect_format}" "${all_volumes[@]}")
    fi
  else
    log "unused-volume cleanup disabled"
  fi

  output_file="$(mktemp /tmp/docker-stale-cleanup.XXXXXX)"
  printf -v cleanup_trap 'rm -f -- %q' "${output_file}"
  # Expand the command now so the EXIT trap does not depend on a local variable.
  # shellcheck disable=SC2064
  trap "${cleanup_trap}" EXIT
  prune_old_docker_objects "${output_file}"

  after="$(available_bytes)"
  reclaimed=$((after - before))
  log "cleanup finished with ${after} bytes available (${reclaimed} filesystem bytes reclaimed)"
  rm -f -- "${output_file}"
  trap - EXIT
}

case "${MODE}" in
  prune|--prune)
    prune
    ;;
  plan|--plan)
    DRY_RUN=1
    prune
    ;;
  status|--status)
    status
    ;;
  *)
    echo "usage: $0 [prune|plan|status]" >&2
    exit 64
    ;;
esac
