import localFont from "next/font/local";

// Same fonts as the app (both SIL Open Font License, see app/fonts/OFL-*.txt).
export const inter = localFont({
  src: [
    { path: "./fonts/Inter_400Regular.ttf", weight: "400" },
    { path: "./fonts/Inter_500Medium.ttf", weight: "500" },
    { path: "./fonts/Inter_600SemiBold.ttf", weight: "600" },
    { path: "./fonts/Inter_700Bold.ttf", weight: "700" },
  ],
  variable: "--font-inter",
  display: "swap",
});

export const spaceGrotesk = localFont({
  src: [
    { path: "./fonts/SpaceGrotesk_500Medium.ttf", weight: "500" },
    { path: "./fonts/SpaceGrotesk_600SemiBold.ttf", weight: "600" },
    { path: "./fonts/SpaceGrotesk_700Bold.ttf", weight: "700" },
  ],
  variable: "--font-display",
  display: "swap",
});
