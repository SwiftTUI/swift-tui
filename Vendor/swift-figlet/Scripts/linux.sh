#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

WASM_SDK_ID="${WASM_SDK_ID:-swift-6.3-RELEASE_wasm}"
WASM_SDK_URL="${WASM_SDK_URL:-https://download.swift.org/swift-6.3-release/wasm-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_wasm.artifactbundle.tar.gz}"
WASM_SDK_CHECKSUM="${WASM_SDK_CHECKSUM:-9fa4016ee632c7e9e906608ec3b55cf13dfc4dff44e47574c5af58064dc33fd9}"

CONTAINER_TOOL=""
IMAGE="${LINUX_IMAGE:-swift:6.3}"
IMAGE_SLUG="$(printf '%s' "$IMAGE" | tr '/:' '--')"
CONTAINER_NAME="${LINUX_CONTAINER_NAME:-swift-figlet-${IMAGE_SLUG}}"
CONTAINER_DIR="${LINUX_CONTAINER_DIR:-/swift-figlet-workspace}"
SWIFTPM_HOME_VOLUME="${LINUX_SWIFTPM_HOME_VOLUME:-${CONTAINER_NAME}-swiftpm-home}"
SWIFTPM_CACHE_VOLUME="${LINUX_SWIFTPM_CACHE_VOLUME:-${CONTAINER_NAME}-swiftpm-cache}"
LINUX_DISABLE_EXPLICIT_PLATFORMS="${LINUX_DISABLE_EXPLICIT_PLATFORMS:-1}"
LINUX_SWIFT_SCRATCH_DIR="${LINUX_SWIFT_SCRATCH_DIR:-$CONTAINER_DIR/.build-linux}"

usage() {
  cat <<EOF
Usage: ./linux.sh <command> [args...]

Lifecycle:
  pull              Pull the configured Linux image
  start             Create and start the container
  stop              Stop the container
  reset             Remove the container
  nuke              Remove the container and cached volumes

Interactive:
  shell             Open an interactive shell in the container
  run <cmd...>      Run a command in the repo-mounted container
  info              Print container configuration and tool versions

Repo-aware:
  test              Run \`swift test\`


Environment:
  LINUX_CONTAINER_TOOL  Force docker or podman
  LINUX_IMAGE           Override the image (default: $IMAGE)
  LINUX_CONTAINER_NAME  Override the container name
  LINUX_CONTAINER_DIR   Override the in-container workspace mount
  LINUX_DISABLE_EXPLICIT_PLATFORMS
                       Export DISABLE_EXPLICIT_PLATFORMS inside repo commands
                       (default: $LINUX_DISABLE_EXPLICIT_PLATFORMS)
  LINUX_SWIFT_SCRATCH_DIR
                       SwiftPM scratch directory for Linux builds
                       (default: $LINUX_SWIFT_SCRATCH_DIR)
EOF
}

log() {
  printf '==> %s\n' "$*"
}

ensure_container_tool() {
  if [[ -n "$CONTAINER_TOOL" ]]; then
    return
  fi

  if [[ -n "${LINUX_CONTAINER_TOOL:-}" ]]; then
    CONTAINER_TOOL="$LINUX_CONTAINER_TOOL"
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    CONTAINER_TOOL=docker
    return
  fi

  if command -v podman >/dev/null 2>&1; then
    CONTAINER_TOOL=podman
    return
  fi

  cat >&2 <<'EOF'
error: docker or podman is required.

Install one of them, or set LINUX_CONTAINER_TOOL to an explicit binary.
EOF
  exit 1
}

container_exists() {
  ensure_container_tool
  "$CONTAINER_TOOL" container inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

container_running() {
  ensure_container_tool
  [[ "$("$CONTAINER_TOOL" inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || printf false)" == "true" ]]
}

ensure_volume() {
  ensure_container_tool
  local volume_name="$1"
  if ! "$CONTAINER_TOOL" volume inspect "$volume_name" >/dev/null 2>&1; then
    "$CONTAINER_TOOL" volume create "$volume_name" >/dev/null
  fi
}

pull_image() {
  ensure_container_tool
  log "Pulling $IMAGE"
  "$CONTAINER_TOOL" pull "$IMAGE"
}

ensure_container() {
  ensure_container_tool
  if ! "$CONTAINER_TOOL" image inspect "$IMAGE" >/dev/null 2>&1; then
    pull_image
  fi

  ensure_volume "$SWIFTPM_HOME_VOLUME"
  ensure_volume "$SWIFTPM_CACHE_VOLUME"

  if ! container_exists; then
    log "Creating $CONTAINER_NAME"
    "$CONTAINER_TOOL" create \
      --name "$CONTAINER_NAME" \
      --mount "type=bind,src=$REPO_DIR,dst=$CONTAINER_DIR" \
      --mount "type=volume,src=$SWIFTPM_HOME_VOLUME,dst=/root/.swiftpm" \
      --mount "type=volume,src=$SWIFTPM_CACHE_VOLUME,dst=/root/.cache/org.swift.swiftpm" \
      --workdir "$CONTAINER_DIR" \
      "$IMAGE" sleep infinity >/dev/null
  fi

  if ! container_running; then
    log "Starting $CONTAINER_NAME"
    "$CONTAINER_TOOL" start "$CONTAINER_NAME" >/dev/null
  fi
}

exec_flags() {
  if [[ -t 0 && -t 1 ]]; then
    printf '%s\n' "-it"
  else
    printf '%s\n' "-i"
  fi
}

run_in_container() {
  ensure_container_tool
  ensure_container
  local flags
  flags="$(exec_flags)"
  "$CONTAINER_TOOL" exec "$flags" --workdir "$CONTAINER_DIR" "$CONTAINER_NAME" "$@"
}

run_shell_script() {
  local script="$1"
  run_in_container bash -lc "
    export DISABLE_EXPLICIT_PLATFORMS=$(printf '%q' "$LINUX_DISABLE_EXPLICIT_PLATFORMS")
    cd $(printf '%q' "$CONTAINER_DIR")
    $script
  "
}

cmd_info() {
  ensure_container_tool
  run_shell_script '

    echo "container_tool='"$CONTAINER_TOOL"'"
    echo "image='"$IMAGE"'"
    echo "container='"$CONTAINER_NAME"'"
    echo "workspace='"$CONTAINER_DIR"'"
    echo "disable_explicit_platforms='"$LINUX_DISABLE_EXPLICIT_PLATFORMS"'"
    echo "swift_scratch_dir='"$LINUX_SWIFT_SCRATCH_DIR"'"
    echo
    uname -a
    echo
    swift --version
    echo
    '
}

cmd_examples() {
  run_shell_script "
    swift --version
    swift build --scratch-path $(printf '%q' "$LINUX_SWIFT_SCRATCH_DIR/examples-gallery") --package-path Examples/gallery
    swift build --scratch-path $(printf '%q' "$LINUX_SWIFT_SCRATCH_DIR/examples-todoist") --package-path Examples/todoist
  "
}

cmd_test() {
  run_shell_script "
    swift test --scratch-path $(printf '%q' "$LINUX_SWIFT_SCRATCH_DIR/root")
  "
}

main() {
  local command="${1:-help}"
  case "$command" in
  help | -h | --help)
    usage
    ;;
  pull)
    pull_image
    ;;
  start)
    ensure_container
    cmd_info
    ;;
  stop)
    if container_running; then
      log "Stopping $CONTAINER_NAME"
      "$CONTAINER_TOOL" stop "$CONTAINER_NAME" >/dev/null
    else
      log "$CONTAINER_NAME is not running"
    fi
    ;;
  reset)
    if container_exists; then
      log "Removing $CONTAINER_NAME"
      "$CONTAINER_TOOL" rm -f "$CONTAINER_NAME" >/dev/null
    else
      log "$CONTAINER_NAME does not exist"
    fi
    ;;
  nuke)
    "$0" reset
    log "Removing cached volumes"
    "$CONTAINER_TOOL" volume rm -f \
      "$SWIFTPM_HOME_VOLUME" \
      "$SWIFTPM_CACHE_VOLUME" >/dev/null 2>&1 || true
    ;;
  shell)
    ensure_container
    run_in_container bash
    ;;
  run)
    shift
    if [[ $# -eq 0 ]]; then
      echo "error: ./linux.sh run requires a command" >&2
      exit 1
    fi
    run_in_container "$@"
    ;;
  info)
    cmd_info
    ;;
  test)
    cmd_test
    ;;
  *)
    echo "error: unknown command '$command'" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
  esac
}

main "$@"
