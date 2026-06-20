import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        ink: "#000000",
        paper: "#ffffff",
      },
      fontFamily: {
        sans: ["var(--font-grotesk)", "Helvetica Neue", "Arial", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "SFMono-Regular", "monospace"],
      },
      boxShadow: {
        brut: "6px 6px 0 0 #000",
        "brut-sm": "4px 4px 0 0 #000",
        "brut-lg": "10px 10px 0 0 #000",
        "brut-white": "6px 6px 0 0 #fff",
      },
      keyframes: {
        marquee: {
          "0%": { transform: "translateX(0)" },
          "100%": { transform: "translateX(-50%)" },
        },
        spinArc: {
          "0%": { transform: "rotate(0deg)" },
          "100%": { transform: "rotate(360deg)" },
        },
        pulseDot: {
          "0%, 100%": { transform: "scale(0.4)", opacity: "0.4" },
          "50%": { transform: "scale(1)", opacity: "1" },
        },
        drawCheck: {
          "0%": { strokeDashoffset: "48" },
          "100%": { strokeDashoffset: "0" },
        },
      },
      animation: {
        marquee: "marquee 22s linear infinite",
        spinArc: "spinArc 1s linear infinite",
        pulseDot: "pulseDot 1s ease-in-out infinite",
        drawCheck: "drawCheck 0.5s ease-out forwards",
      },
    },
  },
  plugins: [],
};

export default config;
