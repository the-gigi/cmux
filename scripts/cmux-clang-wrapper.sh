#!/usr/bin/env bash
# clang shim for the cmux custom Xcode toolchain.
#
# Workaround for a SwiftBuild deadlock seen on macOS 26.3 + Xcode 26.4 (and
# possibly later). At the start of every build, SwiftBuild's spec discovery
# probe runs:
#
#     clang -v -E -dM -arch <arch> -isysroot <SDK> -x c -c /dev/null
#
# clang's verbose output (the `-v` preamble) plus the macro dump from `-dM`
# gets large enough to fill macOS's 16 KiB pipe buffer. SwiftBuild stops
# draining the pipe and clang blocks in write() forever, wedging xcodebuild
# before any compile starts. Stripping `-v` from this one specific probe
# keeps the output small enough that SwiftBuild can read it. We forward
# every other invocation to the real clang untouched.
set -euo pipefail

developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "$developer_dir" ]]; then
  developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
fi
if [[ -z "$developer_dir" ]]; then
  developer_dir="/Applications/Xcode.app/Contents/Developer"
fi

real_clang="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
if [[ ! -x "$real_clang" ]]; then
  echo "cmux-clang-wrapper: missing real clang at $real_clang" >&2
  exit 1
fi

strip_verbose=0
has_E=0
has_dM=0
has_devnull=0
for arg in "$@"; do
  case "$arg" in
    -E) has_E=1 ;;
    -dM) has_dM=1 ;;
    /dev/null) has_devnull=1 ;;
  esac
done
if [[ $has_E -eq 1 && $has_dM -eq 1 && $has_devnull -eq 1 ]]; then
  strip_verbose=1
fi

args=()
for arg in "$@"; do
  if [[ $strip_verbose -eq 1 && ( "$arg" = -v || "$arg" = -c ) ]]; then
    continue
  fi
  args+=("$arg")
done

exec "$real_clang" "${args[@]}"
