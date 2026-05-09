// Mac mirrors `prefers-color-scheme`; the user can override later via
// settings. We treat dark/light as a CSS pseudo-class (Tailwind's
// `darkMode: "media"`), so this function is a no-op today and serves
// as the hook point for the manual override.
export function applyTheme(): void {
  document.documentElement.dataset.theme =
    window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}
