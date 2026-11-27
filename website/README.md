# HyperShell website

The Astro project uses the package setup, strict TypeScript configuration,
local icon integration, and fonts from
[HYP3R00T's Astro project template](https://github.com/HYP3R00T/astro-project-template).
The homepage lists Omarchy themes. Linear Carbon is the first theme and has its
own interactive preview with illustrative data.

Run these commands from the repository root. Mise supplies Node.js and pnpm.
Run `mise trust` once if Mise prompts you.

```sh
mise install
mise exec -- pnpm --dir website install
mise run site
```

Use `pnpm check` to check the Astro and TypeScript sources.
Use `pnpm build` to produce the static site in `dist/`.

From the repository root, use `mise run biome` to check and format the
website's JavaScript and TypeScript. Use `mise run dicon -- 511075/more-grid-small`
to add an icon from SVGRepo to `src/assets/icons/`.
