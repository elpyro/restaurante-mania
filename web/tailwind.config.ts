import type { Config } from "tailwindcss";

const token = (name: string) => `rgb(var(--${name}) / <alpha-value>)`;

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        surface: {
          DEFAULT: token("surface"),
          raised: token("surface-raised"),
          muted: token("surface-muted"),
        },
        ink: {
          DEFAULT: token("ink"),
          soft: token("ink-soft"),
          muted: token("ink-muted"),
          400: token("ink-400"),
          500: token("ink-500"),
          700: token("ink-700"),
          900: token("ink-900"),
        },
        brand: {
          DEFAULT: token("brand-600"),
          strong: token("brand-700"),
          soft: token("brand-100"),
          50: token("brand-50"),
          100: token("brand-100"),
          200: token("brand-200"),
          300: token("brand-300"),
          400: token("brand-400"),
          500: token("brand-500"),
          600: token("brand-600"),
          700: token("brand-700"),
          800: token("brand-800"),
          900: token("brand-900"),
        },
        accent: {
          DEFAULT: token("accent"),
          strong: token("accent-strong"),
          soft: token("accent-soft"),
        },
        line: token("line"),
        hero: {
          from: token("hero-from"),
          to: token("hero-to"),
        },
        footer: {
          DEFAULT: token("footer"),
          ink: token("footer-ink"),
        },
      },
      fontFamily: {
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
        display: ["var(--font-display)", "Georgia", "serif"],
      },
      boxShadow: {
        card: "0 24px 60px -36px rgb(var(--ink) / 0.55)",
        glow: "0 0 0 1px rgb(var(--brand-200) / 0.7), 0 24px 50px -30px rgb(var(--brand-500) / 0.65)",
      },
      borderRadius: {
        "4xl": "2rem",
        "5xl": "2.5rem",
      },
      keyframes: {
        "fade-up": {
          from: { opacity: "0", transform: "translateY(14px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        float: {
          "0%, 100%": { transform: "translateY(0)" },
          "50%": { transform: "translateY(-12px)" },
        },
        shimmer: {
          from: { backgroundPosition: "200% 0" },
          to: { backgroundPosition: "-200% 0" },
        },
        "pulse-soft": {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.55" },
        },
      },
      animation: {
        "fade-up": "fade-up 0.5s ease-out both",
        float: "float 6s ease-in-out infinite",
        shimmer: "shimmer 2.2s linear infinite",
        "pulse-soft": "pulse-soft 2.4s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
