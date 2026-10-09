import type { Metadata } from "next";
import Link from "next/link";
import Script from "next/script";
import { createPublicClient } from "@/lib/supabase/server";
import { DownloadButton } from "./download-button";

// Public download page used as the destination of Meta ads. The Pixel set in
// the admin panel (Meta Pixel page) is added here automatically.
export const dynamic = "force-dynamic";

type Config = { pixel_id: string | null; apk_url: string | null; title: string; subtitle: string };

async function config(): Promise<Config> {
  const { data } = await createPublicClient().rpc("download_page_config");
  return (data as Config | null) ?? { pixel_id: null, apk_url: null, title: "Flixvault", subtitle: "" };
}

export async function generateMetadata(): Promise<Metadata> {
  const c = await config();
  return { title: `${c.title} — Download`, description: c.subtitle, robots: { index: true } };
}

const FEATURES = [
  ["🎬", "Full videos", "Watch full shows and videos from top creators."],
  ["▶️", "Free trailers", "Preview videos with a free trailer."],
  ["☁️", "15 GB cloud storage", "Keep your photos, videos and files safe."],
  ["🆓", "Completely free", "No plans and no payments. Just log in."],
];

export default async function DownloadPage() {
  const c = await config();
  const pixel = c.pixel_id && /^[0-9]{5,20}$/.test(c.pixel_id) ? c.pixel_id : null;

  return (
    <div className="min-h-screen bg-[#0B0B0D] text-white">
      {pixel && (
        <>
          <Script id="meta-pixel" strategy="afterInteractive">
            {`!function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');fbq('init','${pixel}');fbq('track','PageView');`}
          </Script>
          <noscript>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img height="1" width="1" style={{ display: "none" }} alt=""
              src={`https://www.facebook.com/tr?id=${pixel}&ev=PageView&noscript=1`} />
          </noscript>
        </>
      )}

      <div className="pointer-events-none absolute inset-x-0 top-0 h-80 bg-[radial-gradient(ellipse_at_top,rgba(255,122,26,0.35),transparent_70%)]" />

      <main className="relative mx-auto flex max-w-md flex-col px-5 pb-10 pt-12">
        <div className="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-3xl bg-gradient-to-br from-[#FF7A1A] to-[#E25A00] text-4xl font-black shadow-lg">
          F
        </div>
        <h1 className="text-center text-4xl font-extrabold tracking-tight">{c.title}</h1>
        <p className="mt-3 text-center text-base text-white/70">{c.subtitle}</p>

        <div className="mt-8">
          <DownloadButton apkUrl={c.apk_url} />
          <p className="mt-3 text-center text-xs text-white/50">Free download · Android · About 25 MB</p>
        </div>

        <ul className="mt-10 space-y-3">
          {FEATURES.map(([icon, title, text]) => (
            <li key={title} className="flex gap-4 rounded-2xl border border-white/10 bg-white/[0.04] p-4">
              <span className="text-2xl" aria-hidden>{icon}</span>
              <div>
                <p className="font-semibold">{title}</p>
                <p className="text-sm text-white/60">{text}</p>
              </div>
            </li>
          ))}
        </ul>

        <div className="mt-10 rounded-2xl border border-white/10 bg-white/[0.04] p-4 text-sm text-white/70">
          <p className="mb-2 font-semibold text-white">How to install</p>
          <ol className="list-decimal space-y-1 pl-5">
            <li>Tap <b>Download the app</b>.</li>
            <li>Open the downloaded file. If asked, allow installs from your browser.</li>
            <li>Tap <b>Install</b>, then open {c.title}.</li>
          </ol>
        </div>

        <footer className="mt-10 text-center text-xs text-white/40">
          <Link href="/privacy" className="underline">Privacy Policy</Link> ·{" "}
          <Link href="/privacy#terms" className="underline">Terms</Link> ·{" "}
          <Link href="/privacy#refund" className="underline">Refunds</Link>
        </footer>
      </main>
    </div>
  );
}
