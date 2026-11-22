import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#fff8ed",
          100: "#ffefd4",
          200: "#ffdca8",
          300: "#ffc271",
          400: "#ff9d38",
          500: "#fe7f12",
          600: "#ef6408",
          700: "#c64b09",
          800: "#9d3c10",
          900: "#7e3310",
        },
        ink: {
          900: "#1c1917",
          700: "#44403c",
          500: "#78716c",
        },
      },
      fontFamily: {
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
        display: ["var(--font-display)", "Georgia", "serif"],
      },
      boxShadow: {
        card: "0 18px 40px -24px rgba(28, 25, 23, 0.35)",
      },
    },
  },
  plugins: [],
};

export default config;
