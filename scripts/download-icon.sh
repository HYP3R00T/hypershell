#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! $1 =~ ^[0-9]+/[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  printf 'Usage: %s <ID/slug> [output-name.svg]\n' "$0" >&2
  exit 2
fi

output=${2:-${1#*/}.svg}
if [[ ! $output =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*\.svg$ ]]; then
  printf 'Invalid SVG filename: %s\n' "$output" >&2
  exit 2
fi

target="src/assets/icons/$output"
temporary=$(mktemp)
trap 'rm -f -- "$temporary"' EXIT
curl -fsSL "https://www.svgrepo.com/show/$1.svg" -o "$temporary"
if ! (set -o noclobber; cat "$temporary" > "$target"); then
  exit 1
fi
printf 'Saved %s\n' "$target"
