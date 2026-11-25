#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  printf 'Usage: %s\n' "${0##*/}" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
wallpapers_dir=$(realpath -e -- "$repo_dir/wallpapers")

shopt -s globstar nullglob dotglob
declare -A sources=()
for entry in "$wallpapers_dir"/**/*; do
  [[ -f $entry ]] || continue
  filename=${entry##*/}
  case "${filename,,}" in
    *.jpg | *.jpeg | *.png | *.gif | *.bmp | *.webp | *.mp4 | *.m4v | *.mov | *.webm | *.mkv | *.avi) ;;
    *) continue ;;
  esac

  source_file=$(realpath -e -- "$entry")
  if [[ $source_file != "$wallpapers_dir/"* ]]; then
    printf 'Wallpaper points outside wallpapers/: %s\n' "$entry" >&2
    exit 1
  fi
  # Omarchy's wallpaper picker only scans the top level of the destination.
  if [[ ${sources[$filename]+present} ]]; then
    printf 'Wallpaper filenames must be unique: %s\n' "$filename" >&2
    exit 1
  fi
  sources[$filename]=$source_file
done

if (( ${#sources[@]} == 0 )); then
  printf 'No wallpapers found in wallpapers/.\n'
  exit 0
fi

theme_file="$HOME/.local/state/omarchy/current/theme.name"
if [[ ! -r $theme_file ]]; then
  printf 'No active Omarchy theme was found.\n' >&2
  exit 1
fi
theme=$(<"$theme_file")
if [[ -z $theme || $theme == .* || $theme == */* || $theme == *$'\n'* ]]; then
  printf 'The active Omarchy theme name is invalid.\n' >&2
  exit 1
fi

destination="$HOME/.config/omarchy/backgrounds/$theme"
mkdir -p -- "$destination"

staged=
trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
for filename in "${!sources[@]}"; do
  # Staging beside the target keeps the previous copy intact if copying fails.
  staged=$(mktemp -- "$destination/.wallpaper.XXXXXXXX")
  install -m 0644 -- "${sources[$filename]}" "$staged"
  mv -fT -- "$staged" "$destination/$filename"
  staged=
done
printf 'Copied %d wallpaper file(s) to %s\n' "${#sources[@]}" "$destination"
