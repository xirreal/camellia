#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 X.Y.Z" >&2
  exit 1
fi

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
version=$1
output_dir="$root_dir/dist"
output="$output_dir/Camellia-v$version.zip"

mkdir -p "$output_dir"
rm -f "$output"
(
  cd "$root_dir"
  zip -qr "$output" shaders LICENSE THIRD_PARTY_NOTICES.md licenses
)

printf 'Created %s\n' "$output"
