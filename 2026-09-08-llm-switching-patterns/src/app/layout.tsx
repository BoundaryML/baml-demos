import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Launch studio · BAML switching patterns",
  description: "Prepare a product-launch logo and announcement in parallel with OpenAI, Gemini, BAML, and WorkOS.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
