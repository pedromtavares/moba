module.exports = {
  content: [
    "../lib/moba_web/v2/**/*.ex",
    "../lib/moba_web/v2/**/*.heex",
  ],
  theme: {
    extend: {
      colors: {
        faction: {
          bg: "var(--faction-bg, #1A1A2A)",
          "bg-light": "var(--faction-bg-light, #242438)",
          "bg-surface": "var(--faction-bg-surface, #2A2A40)",
          text: "var(--faction-text, #C8C0D0)",
          "text-muted": "var(--faction-text-muted, #8080A0)",
          accent: "var(--faction-accent, #6A4ABF)",
          glow: "var(--faction-glow, #8866FF)",
        },
       
        gold: {
          DEFAULT: "#E0A526",
          light: "#F0C060",
          dark: "#B08018",
        },
       
        hp: { DEFAULT: "#4CAF50", dark: "#2E7D32", light: "#81C784" },
        mp: { DEFAULT: "#42A5F5", dark: "#1565C0", light: "#90CAF9" },
        atk: { DEFAULT: "#EF5350", dark: "#C62828", light: "#EF9A9A" },
        power: { DEFAULT: "#EC407A", dark: "#AD1457", light: "#F48FB1" },
        armor: { DEFAULT: "#FFA726", dark: "#E65100", light: "#FFCC80" },
        speed: { DEFAULT: "#AB47BC", dark: "#6A1B9A", light: "#CE93D8" },
       
        rarity: {
          normal: "#9E9E9E",
          rare: "#42A5F5",
          epic: "#AB47BC",
          legendary: "#EF5350",
        },
       
        surface: {
          DEFAULT: "#16213E",
          light: "#1A2A4E",
          dark: "#0F1628",
          border: "#0F3460",
          "border-light": "#1A4A7A",
        },
      },
      fontFamily: {
        sans: [
          "-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto",
          "Oxygen", "Ubuntu", "Cantarell", "Fira Sans", "Droid Sans",
          "Helvetica Neue", "sans-serif",
        ],
      },
    },
  },
  plugins: [],
};
