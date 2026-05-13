#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE="${1:-fast}"
shift || true
SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clawix-test.XXXXXX")"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

run() {
  echo "+ $*" >&2
  "$@"
}

swift_package_tests() {
  local package
  for package in "$@"; do
    [[ -f "$package/Package.swift" ]] || continue
    [[ -d "$package/Tests" ]] || continue
    run swift test --package-path "$package" --scratch-path "$SCRATCH_ROOT/$(basename "$package")"
  done
}

fast_swift_packages() {
  printf '%s\n' \
    "$ROOT_DIR/packages/AIProviders" \
    "$ROOT_DIR/packages/ClawixArgon2" \
    "$ROOT_DIR/packages/ClawixCore" \
    "$ROOT_DIR/packages/SecretsModels" \
    "$ROOT_DIR/packages/SecretsProxyCore"
}

integration_swift_packages() {
  printf '%s\n' \
    "$ROOT_DIR/packages/SecretsCrypto" \
    "$ROOT_DIR/packages/SecretsPersistence" \
    "$ROOT_DIR/packages/SecretsVault" \
    "$ROOT_DIR/packages/ClawixEngine" \
    "$ROOT_DIR/macos"
}

web_tests() {
  if [[ -d "$ROOT_DIR/web/node_modules" ]]; then
    run npm --prefix "$ROOT_DIR/web" test -- "$@"
  else
    echo "PARTIAL web tests skipped: web/node_modules is not installed" >&2
  fi
}

android_unit_tests() {
  if [[ -x "$ROOT_DIR/android/gradlew" ]]; then
    run "$ROOT_DIR/android/gradlew" -p "$ROOT_DIR/android" testDebugUnitTest
  else
    echo "PARTIAL Android unit tests skipped: Gradle wrapper is not executable" >&2
  fi
}

bridge_fixture_tests() {
  run bash "$ROOT_DIR/macos/scripts/e2e_validate.sh"
}

host_tests() {
  if [[ -n "${CLAWIX_HOST_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_HOST_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING host lane: set CLAWIX_HOST_TEST_COMMAND for signed-host validation" >&2
  fi
}

device_tests() {
  android_unit_tests
  if [[ -n "${CLAWIX_DEVICE_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_DEVICE_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING device lane: set CLAWIX_DEVICE_TEST_COMMAND for simulator/device validation" >&2
  fi
}

live_tests() {
  if [[ "${CLAWIX_TEST_LIVE:-}" != "1" ]]; then
    echo "CLAWIX_TEST_LIVE=1 is required for the live lane." >&2
    exit 2
  fi
  if [[ -n "${CLAWIX_LIVE_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_LIVE_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING live lane: set CLAWIX_LIVE_TEST_COMMAND for approved live validation" >&2
  fi
}

fast() {
  run bash "$ROOT_DIR/macos/scripts/public_hygiene_check.sh"
  mapfile -t packages < <(fast_swift_packages)
  swift_package_tests "${packages[@]}"
  web_tests "$@"
}

case "$LANE" in
  fast)
    fast "$@"
    ;;
  changed)
    fast "$@"
    ;;
  integration)
    fast "$@"
    mapfile -t packages < <(integration_swift_packages)
    swift_package_tests "${packages[@]}"
    bridge_fixture_tests
    ;;
  e2e)
    bridge_fixture_tests
    ;;
  host)
    host_tests
    ;;
  device)
    device_tests
    ;;
  live)
    live_tests
    ;;
  release)
    fast "$@"
    bridge_fixture_tests
    device_tests
    host_tests
    ;;
  *)
    echo "Unknown test lane: $LANE" >&2
    exit 2
    ;;
esac
