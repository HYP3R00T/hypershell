export const repository = "https://github.com/HYP3R00T/hypershell"

export function sitePath(path = "") {
  return `${import.meta.env.BASE_URL.replace(/\/$/, "")}/${path}`
}

export const carbon = {
  slug: "carbon",
  name: "Carbon",
  description: "A charcoal desktop with a cool blue accent, a curved notch, and a full-width dock.",
  wallpaper: "salty-suburban.webp",
}

export const themes = [carbon]
