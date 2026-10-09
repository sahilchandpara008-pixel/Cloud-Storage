import type { Metadata } from "next";
import Link from "next/link";
import { SUPPORT_EMAIL } from "@/lib/policies";
import { createPublicClient } from "@/lib/supabase/server";

// Public website (shown at "/" to visitors who are not logged in to the admin panel).
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Flixvault – 2 TB Cloud Storage & Creator Channels",
  description:
    "Simple, secure and swift. Back up photos, videos and documents in the cloud, share them, and watch creator channels.",
  robots: { index: true },
};

const PLAY_URL = "https://play.google.com/store/apps/details?id=com.flixvault.app";

type Plan = { code: string; name: string; duration_days: number; price_inr: number };

const PREMIUM = ["2 TB cloud storage", "Full premium videos", "Ad-free experience", "Ultra-fast downloads", "Upload & manage your channel"];

const days = (d: number) =>
  d % 365 === 0 ? `${d / 365} Year` : d % 30 === 0 ? `${d / 30} Month${d > 30 ? "s" : ""}` : `${d} Days`;

function PlayButton({ light = false }: { light?: boolean }) {
  return (
    <a
      href={PLAY_URL}
      className={`inline-flex items-center gap-2 rounded-lg px-5 py-3 font-semibold shadow-lg ${
        light ? "bg-white text-gray-900" : "bg-[#FF7A1A] text-white"
      }`}
    >
      <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden>
        <path fill={light ? "#34A853" : "#fff"} d="M3.6 1.8 13.8 12 3.6 22.2c-.4-.2-.6-.6-.6-1.1V2.9c0-.5.2-.9.6-1.1Z" />
        <path fill={light ? "#FBBC04" : "#fff"} d="m17.2 15.4-3.4-3.4 3.4-3.4 3.9 2.2c.9.5.9 1.8 0 2.3l-3.9 2.3Z" />
        <path fill={light ? "#EA4335" : "#fff"} d="M13.8 12 3.6 22.2c.4.2.9.2 1.3 0l12.3-6.8L13.8 12Z" />
        <path fill={light ? "#4285F4" : "#fff"} d="M13.8 12 17.2 8.6 4.9 1.8c-.4-.2-.9-.2-1.3 0L13.8 12Z" />
      </svg>
      Google Play
    </a>
  );
}

export default async function HomePage() {
  const { data } = await createPublicClient()
    .from("plans")
    .select("code, name, duration_days, price_inr")
    .eq("active", true)
    .order("position");
  const plans = (data ?? []) as Plan[];

  return (
    <div className="min-h-screen bg-white text-gray-900">
      {/* Header */}
      <header className="sticky top-0 z-30 border-b border-gray-100 bg-white/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center px-5 py-3">
          <Link href="/" className="flex items-center gap-2">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/site/icon.png" alt="" width={34} height={34} className="h-[34px] w-[34px] rounded-lg" />
            <span className="text-2xl font-extrabold tracking-tight text-[#FF6A0D]">Flixvault</span>
          </Link>
          <nav className="ml-auto hidden items-center gap-7 text-sm font-medium text-gray-600 md:flex">
            <a href="#backup" className="hover:text-gray-900">Features</a>
            <a href="#security" className="hover:text-gray-900">Security</a>
            <a href="#plans" className="hover:text-gray-900">Plans</a>
            <Link href="/privacy" className="hover:text-gray-900">Privacy</Link>
            <a href={PLAY_URL} className="rounded-lg bg-[#FF7A1A] px-4 py-2 text-white">Get the app</a>
          </nav>
          <details className="relative ml-auto md:hidden">
            <summary className="list-none rounded-lg border border-gray-200 p-2" aria-label="Menu">
              <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth={2}><path d="M4 7h16M4 12h16M4 17h16" strokeLinecap="round" /></svg>
            </summary>
            <div className="absolute right-0 mt-2 w-48 rounded-xl border border-gray-100 bg-white p-2 text-sm shadow-xl">
              <a href="#backup" className="block rounded-lg px-3 py-2 hover:bg-gray-50">Features</a>
              <a href="#security" className="block rounded-lg px-3 py-2 hover:bg-gray-50">Security</a>
              <a href="#plans" className="block rounded-lg px-3 py-2 hover:bg-gray-50">Plans</a>
              <Link href="/privacy" className="block rounded-lg px-3 py-2 hover:bg-gray-50">Privacy Policy</Link>
              <a href={PLAY_URL} className="mt-1 block rounded-lg bg-[#FF7A1A] px-3 py-2 text-center font-semibold text-white">Get the app</a>
            </div>
          </details>
        </div>
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden bg-[#0B0B0D] text-white">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/site/2-cloud.jpg" alt="" className="absolute inset-0 h-full w-full object-cover opacity-25 blur-sm" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_70%_0%,rgba(255,122,26,0.45),transparent_60%)]" />
        <div className="relative mx-auto max-w-4xl px-5 py-24 text-center md:py-32">
          <p className="mx-auto mb-5 inline-block rounded-full border border-white/25 bg-white/10 px-3 py-1 text-xs font-semibold">Now in Early Access</p>
          <h1 className="text-5xl font-extrabold leading-[1.05] tracking-tight md:text-7xl">
            2 TB Cloud Storage <br className="hidden md:block" />for Everyone
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg text-white/80">
            Simple, Secure, and Swift. Your digital life — and your favourite creator channels — organised in one app.
          </p>
          <div className="mt-9 flex flex-wrap justify-center gap-3">
            <PlayButton />
            <Link href="/d" className="inline-flex items-center rounded-lg border border-white/40 px-5 py-3 font-semibold hover:bg-white/10">Download APK</Link>
          </div>
        </div>
      </section>

      {/* Backup and share */}
      <section id="backup" className="mx-auto grid max-w-6xl scroll-mt-20 items-center gap-10 px-5 py-20 md:grid-cols-2">
        <div className="flex justify-center">
          <svg viewBox="0 0 220 180" className="w-60 md:w-72" aria-hidden>
            <path d="M18 40c0-8 6-14 14-14h50l16 16h90c8 0 14 6 14 14v96c0 8-6 14-14 14H32c-8 0-14-6-14-14V40Z" fill="#9C6B5B" />
            <path d="M18 62h184v94c0 8-6 14-14 14H32c-8 0-14-6-14-14V62Z" fill="#B07D6B" />
            <circle cx="150" cy="118" r="44" fill="#fff" stroke="#9C6B5B" strokeWidth="8" />
            <path d="M150 94v26l18 12" stroke="#9C6B5B" strokeWidth="8" strokeLinecap="round" fill="none" />
          </svg>
        </div>
        <div>
          <h2 className="text-3xl font-bold md:text-4xl">Backup and Share with Ease</h2>
          <p className="mt-4 text-lg leading-relaxed text-gray-600">
            Easily back up your photos, videos and documents. Open your files from any phone, anytime, and keep them
            organised in folders. Download them back to your phone whenever you need — fast, even for large media.
          </p>
          <ul className="mt-6 grid gap-2 text-gray-700 sm:grid-cols-2">
            {["Photos & videos backup", "Folders for everything", "Fast upload & download", "Smooth video player"].map((t) => (
              <li key={t} className="flex items-center gap-2"><span className="text-[#FF7A1A]">✓</span>{t}</li>
            ))}
          </ul>
        </div>
      </section>

      {/* Security */}
      <section id="security" className="scroll-mt-20 bg-orange-50/60">
        <div className="mx-auto grid max-w-6xl items-center gap-10 px-5 py-20 md:grid-cols-2">
          <div className="order-2 md:order-1">
            <h2 className="text-3xl font-bold md:text-4xl">Flixvault Protects Your Data</h2>
            <p className="mt-4 text-lg leading-relaxed text-gray-600">
              We prioritise your privacy and data security. Every connection is encrypted, your cloud files are private to
              your account, and you stay in control — delete your account and data any time.
            </p>
            <div className="mt-6 flex items-center gap-3">
              <span className="flex h-11 w-11 items-center justify-center rounded-full bg-[#FF7A1A] text-white">🛡️</span>
              <div>
                <p className="font-semibold">Keep Your Data Safe</p>
                <p className="text-sm text-gray-500">Encrypted connections · Private files · You control deletion</p>
              </div>
            </div>
            <Link href="/privacy" className="mt-7 inline-flex items-center gap-1 rounded-lg border border-[#FF7A1A] px-4 py-2 text-sm font-semibold text-[#E25A00] hover:bg-[#FF7A1A]/10">
              View More Details →
            </Link>
          </div>
          <div className="order-1 flex justify-center md:order-2">
            <svg viewBox="0 0 200 220" className="w-52 md:w-64" aria-hidden>
              <path d="M100 10 180 40v62c0 56-35 92-80 108-45-16-80-52-80-108V40l80-30Z" fill="#FF8A2A" />
              <path d="M100 26 166 51v51c0 46-28 77-66 91-38-14-66-45-66-91V51l66-25Z" fill="#FFB066" />
              <circle cx="100" cy="92" r="26" fill="#C2410C" />
              <path d="M56 160c8-28 26-40 44-40s36 12 44 40c-12 12-28 20-44 24-16-4-32-12-44-24Z" fill="#C2410C" />
            </svg>
          </div>
        </div>
      </section>

      {/* Channels & UGC */}
      <section className="mx-auto max-w-6xl px-5 py-20">
        <div className="grid items-center gap-10 md:grid-cols-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/site/1-explore.jpg" alt="Flixvault channels" className="mx-auto w-56 rounded-[2rem] border-[6px] border-gray-900 shadow-2xl" />
          <div>
            <h2 className="text-3xl font-bold md:text-4xl">Channels &amp; Creator Content</h2>
            <p className="mt-4 text-lg leading-relaxed text-gray-600">
              Follow channels, watch free trailers and unlock full videos with Premium. Anyone can create a channel and
              share content — and all channels are user-generated and managed, with strong safeguards:
            </p>
            <ol className="mt-5 space-y-2 text-gray-700">
              <li><b className="text-[#FF6A0D]">1.</b> Moderation tools to review all new channels.</li>
              <li><b className="text-[#FF6A0D]">2.</b> Approval system — every channel is reviewed before it goes live.</li>
              <li><b className="text-[#FF6A0D]">3.</b> DMCA-compliant takedown policy with fast removal of reported content.</li>
            </ol>
            <Link href="/report-content" className="mt-5 inline-block text-sm font-semibold text-[#E25A00] underline">Report content →</Link>
          </div>
        </div>
      </section>

      {/* Plans */}
      <section id="plans" className="scroll-mt-20 bg-gray-50">
        <div className="mx-auto max-w-5xl px-5 py-20">
          <h2 className="text-center text-3xl font-bold md:text-4xl">Choose Your Best Flixvault Plan</h2>
          <p className="mx-auto mt-3 max-w-xl text-center text-gray-600">Unlock premium privileges and supercharge your cloud storage.</p>
          <p className="mx-auto mt-4 max-w-xl rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-center text-sm text-green-800">
            <b>Free on Google Play:</b> log in and get 15 GB of cloud storage free. Premium plans are not sold in the Google Play version.
          </p>
          <div className="mt-10 grid gap-6 md:grid-cols-2">
            <div className="rounded-2xl border border-gray-200 bg-white p-7 shadow-sm">
              <div className="flex items-center gap-2">
                <h3 className="text-xl font-bold">Premium</h3>
                <span className="rounded bg-[#FF7A1A] px-2 py-0.5 text-xs font-semibold text-white">Popular</span>
              </div>
              <p className="mt-2 text-gray-600">For individuals and power users who need more space, full videos and features.</p>
              <ul className="mt-6 space-y-2">
                {PREMIUM.map((f) => (
                  <li key={f} className="flex items-center gap-2 text-gray-800"><span className="text-green-600">✓</span>{f}</li>
                ))}
              </ul>
              <Link href="/d" className="mt-7 block rounded-lg bg-[#FF7A1A] py-3 text-center font-semibold text-white">Choose Premium</Link>
            </div>
            <div className="rounded-2xl border border-gray-200 bg-white p-7 shadow-sm">
              <h3 className="font-bold">Select Your Plan</h3>
              <div className="mt-4 space-y-2">
                {plans.map((p, i) => (
                  <div key={p.code} className={`flex items-center justify-between rounded-xl border px-4 py-3 ${i === 2 ? "border-[#FF7A1A] bg-orange-50" : "border-gray-200"}`}>
                    <div>
                      <p className="font-semibold">{p.name}</p>
                      <p className="text-xs text-gray-500">{days(p.duration_days)}</p>
                    </div>
                    <p className="text-lg font-bold text-[#E25A00]">₹{p.price_inr}</p>
                  </div>
                ))}
              </div>
              <Link href="/d" className="mt-5 block rounded-lg bg-[#FF7A1A] py-3 text-center font-semibold text-white">Download the app to subscribe</Link>
              <p className="mt-2 text-center text-xs text-gray-500">Buy in the app downloaded from this website, with any UPI app. Plans don&apos;t renew automatically.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-[#16161A] text-white/70">
        <div className="mx-auto grid max-w-6xl gap-10 px-5 py-12 text-sm md:grid-cols-3">
          <div>
            <p className="mb-3 text-base font-semibold text-white">About</p>
            <p className="italic text-white/90">Flixvault</p>
            <p className="mt-1"><span className="underline">Email</span>: <a href={`mailto:${SUPPORT_EMAIL}`} className="hover:text-white">{SUPPORT_EMAIL}</a></p>
            <p className="mt-1">Secure cloud storage and creator channels.</p>
          </div>
          <div>
            <p className="mb-3 text-base font-semibold text-white">Legals</p>
            <ul className="space-y-2">
              <li><Link href="/privacy" className="hover:text-white">Privacy Policy</Link></li>
              <li><Link href="/terms#refund" className="hover:text-white">Refund Policy</Link></li>
              <li><Link href="/terms" className="hover:text-white">Terms and Conditions</Link></li>
              <li><Link href="/terms#community" className="hover:text-white">Community Guidelines</Link></li>
              <li><Link href="/delete-account" className="hover:text-white">Delete Account</Link></li>
              <li><Link href="/report-content" className="hover:text-white">Report Content</Link></li>
            </ul>
          </div>
          <div>
            <p className="mb-3 text-base font-semibold text-white">Get the app</p>
            <PlayButton light />
            <p className="mt-3"><Link href="/d" className="underline hover:text-white">Download APK</Link></p>
          </div>
        </div>
        <p className="border-t border-white/10 py-5 text-center text-xs text-white/50">
          Copyright ©{new Date().getFullYear()} Flixvault. All Rights Reserved.
        </p>
      </footer>
    </div>
  );
}
