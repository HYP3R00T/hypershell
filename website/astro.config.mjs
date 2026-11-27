// @ts-check
import { defineConfig } from "astro/config";
import icon from "astro-icon";

export default defineConfig({
  compressHTML: true,
  devToolbar: { enabled: false },
  integrations: [
    icon({
      iconDir: "src/assets/icons",
      svgoOptions: {
        plugins: [{ name: "convertColors", params: { currentColor: true } }],
      },
    }),
  ],
});
