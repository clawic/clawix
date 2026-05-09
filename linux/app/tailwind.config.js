/** @type {import('tailwindcss').Config} */
export default {
  content: ["./src/**/*.{ts,tsx,html}", "./index.html"],
  darkMode: "media",
  theme: {
    extend: {
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "Inter",
          "system-ui",
          "sans-serif"
        ]
      },
      colors: {
        clawix: {
          accent: "#0f0f10",
          surface: "#fafafa",
          surfaceDark: "#111213"
        }
      },
      letterSpacing: {
        tightish: "-0.02em",
        tighter2: "-0.025em"
      },
      borderRadius: {
        squircle: "1.4rem"
      },
      backdropBlur: {
        glass: "28px"
      },
      transitionTimingFunction: {
        "ease-out-cubic": "cubic-bezier(0.215, 0.61, 0.355, 1)"
      }
    }
  },
  plugins: []
};
