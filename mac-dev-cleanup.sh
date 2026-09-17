#!/bin/bash

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Andrei Ionescu

# mac-dev-cleanup.sh
# Conservative disk-space scanner and cleaner for a macOS development machine.
# Compatible with the Bash 3.2 version shipped with macOS.

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
USER_HOME="${HOME}"
DATA_VOLUME="/System/Volumes/Data"

CLEAN_SAFE=0
ERASE_SIMULATORS=0
DELETE_DEVICE_SUPPORT=0
PRUNE_DOCKER=0
ASSUME_YES=0

if [ ! -d "$DATA_VOLUME" ]; then
  DATA_VOLUME="/"
fi

usage() {
  cat <<EOF
Usage:
  ./$SCRIPT_NAME                         Scan only; make no changes
  ./$SCRIPT_NAME --clean                Delete safe, regenerable caches
  ./$SCRIPT_NAME --erase-simulators     Reset all iOS simulator contents
  ./$SCRIPT_NAME --device-support       Delete Xcode iOS DeviceSupport files
  ./$SCRIPT_NAME --docker-prune         Prune unused Docker data (not volumes)

Options can be combined. Every cleanup asks for confirmation unless --yes is
provided. Android SDK/AVD, Claude VM, LM Studio, and other optional data are
reported but never deleted automatically.

Examples:
  ./$SCRIPT_NAME
  ./$SCRIPT_NAME --clean
  ./$SCRIPT_NAME --clean --erase-simulators
  ./$SCRIPT_NAME --clean --docker-prune --yes
EOF
}

for argument in "$@"; do
  case "$argument" in
    --clean)
      CLEAN_SAFE=1
      ;;
    --erase-simulators)
      ERASE_SIMULATORS=1
      ;;
    --device-support)
      DELETE_DEVICE_SUPPORT=1
      ;;
    --docker-prune)
      PRUNE_DOCKER=1
      ;;
    --yes|-y)
      ASSUME_YES=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $argument" >&2
      usage >&2
      exit 2
      ;;
  esac
done

human_kib() {
  awk -v kib="${1:-0}" 'BEGIN {
    split("KiB MiB GiB TiB", units, " ")
    value = kib + 0
    unit = 1
    while (value >= 1024 && unit < 4) {
      value /= 1024
      unit++
    }
    if (unit == 1) {
      printf "%.0f %s", value, units[unit]
    } else {
      printf "%.1f %s", value, units[unit]
    }
  }'
}

human_signed_kib() {
  value="${1:-0}"
  if [ "$value" -lt 0 ]; then
    absolute=$((0 - value))
    printf -- "-%s" "$(human_kib "$absolute")"
  else
    printf "+%s" "$(human_kib "$value")"
  fi
}

du_kib() {
  target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    du -sk "$target" 2>/dev/null | awk 'NR == 1 { print $1 + 0 }'
  else
    echo 0
  fi
}

available_kib() {
  df -k "$DATA_VOLUME" 2>/dev/null | awk 'NR == 2 { print $4 + 0 }'
}

append_target() {
  label="$1"
  path="$2"
  printf '%s\t%s\n' "$label" "$path" >> "$SAFE_TARGETS_FILE"
}

build_safe_target_list() {
  : > "$SAFE_TARGETS_FILE"

  append_target "Xcode DerivedData" "$USER_HOME/Library/Developer/Xcode/DerivedData"
  append_target "CocoaPods cache" "$USER_HOME/Library/Caches/CocoaPods"
  append_target "Yarn download cache" "$USER_HOME/Library/Caches/Yarn"
  append_target "npm content cache" "$USER_HOME/.npm/_cacache"
  append_target "npm logs" "$USER_HOME/.npm/_logs"
  append_target "Gradle dependency cache" "$USER_HOME/.gradle/caches"
  append_target "VS Code updater cache" "$USER_HOME/Library/Caches/com.microsoft.VSCode.ShipIt"
  append_target "React Native cache" "$USER_HOME/Library/Caches/ReactNative"
  append_target "TypeScript cache" "$USER_HOME/Library/Caches/typescript"
  append_target "Playwright browser cache" "$USER_HOME/Library/Caches/ms-playwright"
  append_target "Homebrew download cache" "$USER_HOME/Library/Caches/Homebrew"
  append_target "JetBrains cache" "$USER_HOME/Library/Caches/JetBrains"
  append_target "Raspberry Pi Imager cache" "$USER_HOME/Library/Caches/Raspberry Pi"
  append_target "Spotify cache" "$USER_HOME/Library/Caches/com.spotify.client"
  append_target "Firefox cache" "$USER_HOME/Library/Caches/Firefox"
  append_target "Mozilla updater cache" "$USER_HOME/Library/Caches/Mozilla"
  append_target "Adobe cache" "$USER_HOME/Library/Caches/Adobe"
  append_target "Claude web cache" "$USER_HOME/Library/Application Support/Claude/Cache"
  append_target "Discord web cache" "$USER_HOME/Library/Application Support/discord/Cache"
  append_target "VS Code extension package cache" "$USER_HOME/Library/Application Support/Code/CachedExtensionVSIXs"
  append_target "Spotify persistent cache" "$USER_HOME/Library/Application Support/Spotify/PersistentCache"

  android_cache_root="$USER_HOME/Library/Caches/Google"
  if [ -d "$android_cache_root" ]; then
    find "$android_cache_root" -mindepth 1 -maxdepth 1 -type d \
      -name 'AndroidStudio*' -print 2>/dev/null |
      while IFS= read -r path; do
        append_target "Android Studio index/cache ($(basename "$path"))" "$path"
      done
  fi
}

safe_target_allowed() {
  target="$1"
  case "$target" in
    "$USER_HOME"/Library/Developer/Xcode/DerivedData|\
    "$USER_HOME"/Library/Caches/*|\
    "$USER_HOME"/.npm/_cacache|\
    "$USER_HOME"/.npm/_logs|\
    "$USER_HOME"/.gradle/caches|\
    "$USER_HOME"/Library/Application\ Support/Claude/Cache|\
    "$USER_HOME"/Library/Application\ Support/discord/Cache|\
    "$USER_HOME"/Library/Application\ Support/Code/CachedExtensionVSIXs|\
    "$USER_HOME"/Library/Application\ Support/Spotify/PersistentCache)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

print_safe_scan() {
  total=0
  found=0

  echo "Safe, regenerable cleanup targets:"
  while IFS="$(printf '\t')" read -r label path; do
    size="$(du_kib "$path")"
    if [ "$size" -gt 0 ]; then
      printf "  %-43s %10s\n" "$label" "$(human_kib "$size")"
      total=$((total + size))
      found=1
    fi
  done < "$SAFE_TARGETS_FILE"

  if [ "$found" -eq 0 ]; then
    echo "  No listed caches currently use measurable space."
  fi

  echo "  -------------------------------------------------------"
  printf "  %-43s %10s\n" "Estimated safely reclaimable" "$(human_kib "$total")"
  SAFE_TOTAL_KIB="$total"
}

print_optional_item() {
  label="$1"
  path="$2"
  note="$3"
  size="$(du_kib "$path")"
  if [ "$size" -gt 0 ]; then
    printf "  %-36s %10s  %s\n" "$label" "$(human_kib "$size")" "$note"
  fi
}

print_optional_scan() {
  echo
  echo "Large optional items (reported, not automatically deleted):"
  print_optional_item "Xcode simulator devices" \
    "$USER_HOME/Library/Developer/CoreSimulator/Devices" \
    "Use --erase-simulators to reset data"
  print_optional_item "Xcode iOS DeviceSupport" \
    "$USER_HOME/Library/Developer/Xcode/iOS DeviceSupport" \
    "Use --device-support to delete"
  print_optional_item "Docker Desktop data" \
    "$USER_HOME/Library/Containers/com.docker.docker/Data" \
    "Use --docker-prune; volumes are preserved"
  print_optional_item "Android virtual devices" \
    "$USER_HOME/.android/avd" \
    "Manage in Android Studio Device Manager"
  print_optional_item "Android emulator images" \
    "$USER_HOME/Library/Android/sdk/system-images" \
    "Manage in Android Studio SDK Manager"
  print_optional_item "Android NDK versions" \
    "$USER_HOME/Library/Android/sdk/ndk" \
    "Remove unused versions in SDK Manager"
  print_optional_item "Claude local VM bundles" \
    "$USER_HOME/Library/Application Support/Claude/vm_bundles" \
    "Keep if you use Claude local environments"
  print_optional_item "LM Studio data/models" \
    "$USER_HOME/.lmstudio" \
    "Remove unused models through LM Studio"
  print_optional_item "Bun data/cache" \
    "$USER_HOME/.bun" \
    "Inspect before cleaning"
  print_optional_item "Rust toolchains" \
    "$USER_HOME/.rustup" \
    "Remove unused toolchains with rustup"
}

remove_safe_target() {
  label="$1"
  path="$2"
  before="$(du_kib "$path")"

  if [ "$before" -eq 0 ]; then
    return
  fi

  if ! safe_target_allowed "$path"; then
    printf "  [REFUSED] %-38s unsafe target: %s\n" "$label" "$path"
    return
  fi

  if rm -rf -- "$path" 2>/dev/null; then
    after="$(du_kib "$path")"
    freed=$((before - after))
    CLEANED_TARGET_KIB=$((CLEANED_TARGET_KIB + freed))
    printf "  [CLEANED] %-38s %10s\n" "$label" "$(human_kib "$freed")"
  else
    after="$(du_kib "$path")"
    freed=$((before - after))
    CLEANED_TARGET_KIB=$((CLEANED_TARGET_KIB + freed))
    printf "  [PARTIAL] %-38s %10s\n" "$label" "$(human_kib "$freed")"
  fi
}

confirm_cleanup() {
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi

  echo
  echo "Close Xcode, Simulator, Android Studio, VS Code/Cursor, Claude,"
  echo "Docker Desktop, browsers, Spotify, and Adobe apps before continuing."
  printf "Proceed with the selected cleanup actions? [y/N] "
  IFS= read -r reply
  case "$reply" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_safe_cleanup() {
  echo
  echo "Safe-cache cleanup log:"
  while IFS="$(printf '\t')" read -r label path; do
    remove_safe_target "$label" "$path"
  done < "$SAFE_TARGETS_FILE"
}

run_simulator_cleanup() {
  echo
  echo "Xcode simulator cleanup:"
  simulator_path="$USER_HOME/Library/Developer/CoreSimulator/Devices"
  before="$(du_kib "$simulator_path")"

  if ! command -v xcrun >/dev/null 2>&1; then
    echo "  [SKIPPED] xcrun is unavailable."
    return
  fi

  xcrun simctl shutdown all >/dev/null 2>&1 || true
  if xcrun simctl erase all >/dev/null 2>&1; then
    after="$(du_kib "$simulator_path")"
    freed=$((before - after))
    OPTIONAL_TARGET_KIB=$((OPTIONAL_TARGET_KIB + freed))
    printf "  [RESET] All simulator contents            %10s\n" "$(human_kib "$freed")"
  else
    echo "  [FAILED] Could not erase simulator contents."
  fi
}

run_device_support_cleanup() {
  echo
  echo "Xcode DeviceSupport cleanup:"
  path="$USER_HOME/Library/Developer/Xcode/iOS DeviceSupport"
  before="$(du_kib "$path")"

  if [ "$before" -eq 0 ]; then
    echo "  [SKIPPED] No DeviceSupport data found."
    return
  fi

  if rm -rf -- "$path" 2>/dev/null; then
    after="$(du_kib "$path")"
    freed=$((before - after))
    OPTIONAL_TARGET_KIB=$((OPTIONAL_TARGET_KIB + freed))
    printf "  [CLEANED] iOS DeviceSupport               %10s\n" "$(human_kib "$freed")"
  else
    echo "  [FAILED] Could not remove iOS DeviceSupport."
  fi
}

run_docker_cleanup() {
  echo
  echo "Docker cleanup:"
  docker_path="$USER_HOME/Library/Containers/com.docker.docker/Data"
  before="$(du_kib "$docker_path")"

  if ! command -v docker >/dev/null 2>&1; then
    echo "  [SKIPPED] Docker command is unavailable."
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "  [SKIPPED] Docker Desktop is not running. Start it and retry."
    return
  fi

  if docker system prune -f; then
    after="$(du_kib "$docker_path")"
    freed=$((before - after))
    OPTIONAL_TARGET_KIB=$((OPTIONAL_TARGET_KIB + freed))
    printf "  [PRUNED] Docker host footprint change      %10s\n" "$(human_signed_kib "$freed")"
    echo "  Docker volumes were not removed."
  else
    echo "  [FAILED] Docker prune did not complete."
  fi
}

TMP_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-dev-cleanup.XXXXXX")" || exit 1
SAFE_TARGETS_FILE="$TMP_WORK_DIR/safe-targets.tsv"
trap 'rm -rf -- "$TMP_WORK_DIR"' EXIT HUP INT TERM

build_safe_target_list

echo "macOS developer storage report"
echo "=============================="
printf "Disk free before: %s\n\n" "$(human_kib "$(available_kib)")"
print_safe_scan
print_optional_scan

if [ "$CLEAN_SAFE" -eq 0 ] && \
   [ "$ERASE_SIMULATORS" -eq 0 ] && \
   [ "$DELETE_DEVICE_SUPPORT" -eq 0 ] && \
   [ "$PRUNE_DOCKER" -eq 0 ]; then
  echo
  echo "Scan only: nothing was deleted."
  echo "Run ./$SCRIPT_NAME --clean to remove the safe targets listed above."
  exit 0
fi

if ! confirm_cleanup; then
  echo "Cleanup cancelled; nothing was deleted."
  exit 0
fi

DISK_BEFORE_KIB="$(available_kib)"
CLEANED_TARGET_KIB=0
OPTIONAL_TARGET_KIB=0

if [ "$CLEAN_SAFE" -eq 1 ]; then
  run_safe_cleanup
fi

if [ "$ERASE_SIMULATORS" -eq 1 ]; then
  run_simulator_cleanup
fi

if [ "$DELETE_DEVICE_SUPPORT" -eq 1 ]; then
  run_device_support_cleanup
fi

if [ "$PRUNE_DOCKER" -eq 1 ]; then
  run_docker_cleanup
fi

sync
DISK_AFTER_KIB="$(available_kib)"
DISK_GAIN_KIB=$((DISK_AFTER_KIB - DISK_BEFORE_KIB))
TARGET_TOTAL_KIB=$((CLEANED_TARGET_KIB + OPTIONAL_TARGET_KIB))

echo
echo "Cleanup summary"
echo "==============="
printf "Measured data removed:      %s\n" "$(human_kib "$TARGET_TOTAL_KIB")"
printf "Disk free before cleanup:   %s\n" "$(human_kib "$DISK_BEFORE_KIB")"
printf "Disk free after cleanup:    %s\n" "$(human_kib "$DISK_AFTER_KIB")"
printf "Actual free-space increase: %s\n" "$(human_signed_kib "$DISK_GAIN_KIB")"

if [ "$DISK_GAIN_KIB" -lt "$TARGET_TOTAL_KIB" ]; then
  echo
  echo "The disk-space increase can differ from measured deletions because APFS,"
  echo "open applications, sparse files, and macOS purgeable storage update on"
  echo "their own schedule. Restarting the Mac can refresh the Storage display."
fi

echo
echo "Remaining cleanup opportunities:"
build_safe_target_list
print_safe_scan
print_optional_scan
