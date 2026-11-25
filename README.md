# Omarchy Extras

A collection of themes, wallpapers, and shell plugins for Omarchy.

## Themes

[**Linear Carbon**](themes/linear-carbon/) pairs charcoal surfaces with a silver accent and
muted syntax colors.
It includes a matching wallpaper and colors for the shell, Hyprland, the
terminal, and Chromium-family browsers.

![Linear Carbon desktop preview](themes/linear-carbon/linear-carbon.webp)

### Install Linear Carbon

Run these commands from the repository root on an Omarchy workstation. If you
have a local Linear Carbon theme, the copy updates files with matching names.

```sh
mkdir -p "$HOME/.config/omarchy/themes"
cp -R themes/linear-carbon "$HOME/.config/omarchy/themes/"
omarchy theme set "Linear Carbon"
```

### Develop Linear Carbon locally

From the repository root, link the theme into Omarchy's theme directory. If
that destination already contains a theme folder, move it aside first.

```sh
mkdir -p "$HOME/.config/omarchy/themes"
ln -sT "$PWD/themes/linear-carbon" "$HOME/.config/omarchy/themes/linear-carbon"
```

Edit the files in `themes/linear-carbon/` and run `omarchy theme set "Linear Carbon"`
to preview your changes. Omarchy rebuilds its active theme when you run that
command, including the generated application colors and wallpaper.

### Enable the Linear Carbon notch

The optional notch is a separate Quickshell panel. It reads the Linear Carbon
palette from `colors.toml` and provides workspace indicators, a clock, and
quick controls. It runs alongside the standard Omarchy bar.

With Linear Carbon installed, enable its notch on an Omarchy desktop with
Quickshell and Python 3.11 or newer. Run once from the repository root:

```sh
omarchy hook install theme-set themes/linear-carbon/notch/linear-carbon-notch
omarchy hook install post-boot themes/linear-carbon/notch/linear-carbon-notch
omarchy theme set "Linear Carbon"
```

Selecting Linear Carbon starts the notch. Switching themes stops it, and
logging into Omarchy restores it when Linear Carbon is the active theme.

## Install standalone wallpapers

Put images or videos in `wallpapers/`, then run this from the repository root:

```sh
mise run install-wallpapers
```

You can also run `./scripts/install-wallpaper.sh` directly. Both commands copy
all supported files into the active theme's personal Omarchy wallpaper folder.
Files in subfolders appear together in the picker, so each filename must be
unique. Running the command again updates matching files by name and keeps
other wallpapers in that folder. Press **Super + Ctrl + W** to choose one.

## Repository layout

| Directory | Contents |
| --- | --- |
| `themes/` | One folder per theme, including its matching wallpapers |
| `plugins/` | One folder per Omarchy shell plugin |
| `wallpapers/` | Standalone wallpapers and [artist credits](wallpapers/CREDITS.md) |

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidance and
[LICENSE](LICENSE) for licensing.
