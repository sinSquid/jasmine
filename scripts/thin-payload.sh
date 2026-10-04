#!/bin/sh
set -eu
# Thin unsigned IPA payloads without failing on an already arm64-only binary.
foreachThin() (
  for path in "$1"/*; do
    if [ -d "$path" ]; then
      foreachThin "$path"
    elif [ -f "$path" ]; then
      mime=$(file --mime-type -b "$path")
      if [ "$mime" = application/x-mach-binary ] || [ "${path##*.}" = dylib ]; then
        architectures=$(xcrun -sdk iphoneos lipo -archs "$path")
        case " $architectures " in
          *' arm64 '*) ;;
          *) printf 'No arm64 architecture: %s\n' "$path" >&2; exit 1 ;;
        esac
        if [ "$architectures" != arm64 ]; then
          xcrun -sdk iphoneos lipo "$path" -thin arm64 -output "$path"
        fi
        xcrun -sdk iphoneos bitcode_strip "$path" -r -o "$path"
        strip -S -x "$path" -o "$path"
      fi
    fi
  done
)
test -d ./Payload
foreachThin ./Payload
