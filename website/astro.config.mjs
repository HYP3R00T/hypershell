// @ts-check
import { defineConfig } from "astro/config";
import icon from "astro-icon";

export default defineConfig({
  compressHTML: true,
  devToolbar: { enabled: false },
  redirects: { "/themes/linear-carbon": "/themes/carbon" },
  integrations: [
    icon({
      iconDir: "src/assets/icons",
      svgoOptions: {
        plugins: [{ name: "convertColors", params: { currentColor: true } }],
      },
    }),
  ],
});
