import { headers } from "next/headers";
import { ApkUpload } from "@/components/apk-upload";
import { CopyButton } from "@/components/copy-button";
import { Badge, Button, Card, Empty, Flash, Input, PageHeader, Table, Td, Th } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { connectMeta, saveMetaExtras, sendTestEvent, turnTrackingOff } from "./actions";

type Settings = {
  pixel_id: string | null;
  access_token: string | null;
  test_event_code: string | null;
  action_source: "app" | "website";
  website_url: string | null;
  apk_url: string | null;
  page_title: string | null;
  page_subtitle: string | null;
  enabled: boolean;
};

type MetaEvent = {
  id: number;
  event_name: string;
  event_id: string;
  email: string | null;
  value: number | null;
  status: "queued" | "sent" | "ok" | "failed";
  attempts: number;
  response: string | null;
  created_at: string;
  sent_at: string | null;
};

type Health = {
  clicks_7d: number;
  matched_7d: number;
  purchases_7d: number;
  purchases_ok_7d: number;
  purchases_with_click_7d: number;
  revenue_7d: number;
};

const EVENTS = [
  ["PageView", "Download page opened (browser Pixel)"],
  ["Lead", "Download tapped on the download page (browser Pixel + server, counted once)"],
  ["AppInstall", "First time the app is opened on a phone"],
  ["CompleteRegistration", "A guest creates an account or logs in for the first time"],
  ["ViewContent", "A video, image or trailer is opened"],
  ["InitiateCheckout", "Continue to payment is tapped (UPI order created), with the plan price"],
  ["Purchase", "A payment is approved, with the amount paid in INR — use this for ROAS"],
  ["Subscribe", "Sent together with Purchase, for subscription optimisation"],
];

function StatusBadge({ status }: { status: MetaEvent["status"] }) {
  if (status === "ok") return <Badge tone="green">Received by Meta</Badge>;
  if (status === "failed") return <Badge tone="red">Failed</Badge>;
  if (status === "sent") return <Badge tone="blue">Sent</Badge>;
  return <Badge tone="amber">Waiting</Badge>;
}

function mask(token: string | null) {
  if (!token) return "Not set";
  return `••••••••${token.slice(-4)}`;
}

export default async function MetaPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const sp = await searchParams;
  const { supabase } = await requireOwner();
  const h = await headers();
  const origin = `${h.get("x-forwarded-proto") ?? "https"}://${h.get("x-forwarded-host") ?? h.get("host")}`;
  const downloadPage = `${origin}/d`;
  const adLink = `${downloadPage}?utm_source=meta&utm_medium=paid_social&utm_campaign={{campaign.name}}&utm_content={{ad.name}}`;

  const [{ data: s }, { data: events }, { data: health }] = await Promise.all([
    supabase.from("meta_settings").select("*").eq("id", 1).maybeSingle(),
    supabase.rpc("admin_meta_events", { p_limit: 100 }),
    supabase.rpc("admin_meta_health"),
  ]);
  const settings = (s ?? { action_source: "website", enabled: false }) as Settings;
  const list = (events ?? []) as MetaEvent[];
  const hl = (health ?? {}) as Partial<Health>;
  const ok = list.filter((e) => e.status === "ok").length;
  const failed = list.filter((e) => e.status === "failed").length;
  const ready = !!settings.pixel_id && !!settings.access_token && settings.enabled;

  return (
    <>
      <PageHeader
        title="Meta Pixel"
        subtitle="Enter your Pixel ID and access token once. Everything else is automatic."
      />
      <Flash ok={sp.ok} error={sp.error} />

      <Card className="mb-6">
        <div className="mb-3 flex items-center justify-between gap-3">
          <h2 className="font-semibold">Connect your Pixel</h2>
          {ready ? <Badge tone="green">Connected · tracking on</Badge> : <Badge tone="amber">Not connected</Badge>}
        </div>
        <p className="mb-4 text-sm text-gray-600">
          Paste the two values and press the button. That is all: the Pixel is added to the download page, and every
          app version (website APK, ads APK and Google Play) reports installs, sign-ups, checkouts and purchases with
          the amount paid. No app update is needed.
        </p>
        <form action={connectMeta} className="grid gap-4 sm:grid-cols-2">
          <input type="hidden" name="origin" value={origin} />
          <label className="text-sm font-medium">
            Pixel ID
            <Input name="pixel_id" defaultValue={settings.pixel_id ?? ""} placeholder="e.g. 123456789012345" inputMode="numeric" required />
          </label>
          <label className="text-sm font-medium">
            Access token
            <Input name="access_token" type="password" placeholder={settings.access_token ? `Saved (${mask(settings.access_token)}) — leave empty to keep` : "Paste the token"} autoComplete="off" />
          </label>
          <div className="flex flex-wrap gap-2 sm:col-span-2">
            <Button type="submit">{ready ? "Save" : "Connect and turn tracking on"}</Button>
          </div>
        </form>
        {settings.enabled && (
          <form action={turnTrackingOff} className="mt-2">
            <Button variant="secondary" type="submit">Turn tracking off</Button>
          </form>
        )}
        {ready && !settings.apk_url && (
          <p className="mt-4 rounded bg-amber-50 px-3 py-2 text-sm text-amber-900">
            One more thing before running ads: upload <b>Flixvault-ads.apk</b> under <b>Download page and testing</b> below,
            so the download page has a file to give.
          </p>
        )}
        <div className="mt-5 grid gap-3 text-sm">
          <div>
            <p className="mb-1 font-medium">Download page (open it to check)</p>
            <div className="flex flex-wrap items-center gap-2">
              <a href="/d" target="_blank" className="break-all font-mono text-xs text-brand-700 underline">{downloadPage}</a>
              <CopyButton text={downloadPage} />
            </div>
          </div>
          <div>
            <p className="mb-1 font-medium">Website URL for your Meta ads (paste in the ad&apos;s Website URL)</p>
            <div className="flex flex-wrap items-center gap-2">
              <code className="break-all rounded bg-gray-100 px-2 py-1 text-xs">{adLink}</code>
              <CopyButton text={adLink} />
            </div>
          </div>
        </div>
        <details className="mt-4 text-sm text-gray-600">
          <summary className="cursor-pointer font-medium text-gray-900">How to create the ROAS campaign in Meta Ads Manager</summary>
          <ol className="mt-2 list-decimal space-y-1 pl-5">
            <li>Create campaign → objective <b>Sales</b>.</li>
            <li>Conversion location <b>Website</b>, choose this Pixel, conversion event <b>Purchase</b>.</li>
            <li>Performance goal <b>Maximise value of conversions</b> (needs purchase history; start with <b>Maximise number of conversions</b>, then switch once you have about 50 purchases a week). Optional: set a ROAS goal.</li>
            <li>In the ad, Website URL = the link above. Call to action: <b>Download</b>.</li>
            <li>Check Events Manager → this Pixel → Overview: PageView and Lead arrive from the page, Purchase from the server.</li>
          </ol>
        </details>
      </Card>

      <div className="grid gap-6 lg:grid-cols-[1fr_1fr]">
        <Card>
          <h2 className="mb-1 font-semibold">Download page and testing</h2>
          <p className="mb-4 text-sm text-gray-600">Optional. Tracking works without changing anything here.</p>
          <form action={saveMetaExtras} className="grid gap-4">
            <div className="text-sm font-medium">
              App file for the download page
              <ApkUpload defaultValue={settings.apk_url} />
            </div>
            <label className="text-sm font-medium">
              Download page title
              <Input name="page_title" defaultValue={settings.page_title ?? "Flixvault"} maxLength={60} />
            </label>
            <label className="text-sm font-medium">
              Download page text
              <Input name="page_subtitle" defaultValue={settings.page_subtitle ?? ""} maxLength={160} />
            </label>
            <label className="text-sm font-medium">
              Test event code <span className="font-normal text-gray-500">(only while testing in Events Manager)</span>
              <Input name="test_event_code" defaultValue={settings.test_event_code ?? ""} placeholder="e.g. TEST12345" />
            </label>
            <div className="flex flex-wrap gap-2">
              <Button type="submit">Save</Button>
            </div>
          </form>
          <form action={sendTestEvent} className="mt-3">
            <Button variant="secondary" type="submit">Send test event</Button>
          </form>
        </Card>

        <div className="grid content-start gap-6">
          <Card>
            <h2 className="mb-3 font-semibold">Attribution health (last 7 days)</h2>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><p className="text-2xl font-bold">{hl.clicks_7d ?? 0}</p><p className="text-gray-500">Download taps</p></div>
              <div><p className="text-2xl font-bold">{hl.matched_7d ?? 0}</p><p className="text-gray-500">Installs linked to an ad click</p></div>
              <div><p className="text-2xl font-bold">{hl.purchases_7d ?? 0}</p><p className="text-gray-500">Purchases sent ({hl.purchases_ok_7d ?? 0} received)</p></div>
              <div><p className="text-2xl font-bold">₹{Number(hl.revenue_7d ?? 0).toFixed(0)}</p><p className="text-gray-500">Purchase value sent</p></div>
            </div>
            <p className="mt-3 text-xs text-gray-500">
              {hl.purchases_with_click_7d ?? 0} of {hl.purchases_7d ?? 0} purchases came from someone who tapped Download on the ad page —
              those carry the Meta click id, so Meta can credit them to the ad.
            </p>
          </Card>

          <Card>
            <h2 className="mb-3 font-semibold">Events sent automatically</h2>
            <ul className="space-y-2 text-sm">
              {EVENTS.map(([name, text]) => (
                <li key={name} className="flex gap-3">
                  <code className="shrink-0 rounded bg-gray-100 px-1.5 py-0.5 text-xs font-semibold">{name}</code>
                  <span className="text-gray-600">{text}</span>
                </li>
              ))}
            </ul>
            <h3 className="mb-2 mt-6 text-sm font-semibold">How to get the Pixel ID and token</h3>
            <ol className="list-decimal space-y-1 pl-5 text-sm text-gray-600">
              <li>Open Meta <b>Events Manager</b> → <b>Data sources</b> → your Pixel/dataset (create one if needed). Copy its ID.</li>
              <li>In that dataset open <b>Settings</b> → <b>Conversions API</b> → <b>Generate access token</b>. Copy it.</li>
              <li>Paste both at the top of this page and press <b>Connect and turn tracking on</b>.</li>
              <li>To check: in Events Manager open <b>Test events</b>, copy the test code, paste it above, Save, then press <b>Send test event</b>. Remove the test code when done.</li>
            </ol>
            <p className="mt-4 text-xs text-gray-500">
              Emails and user ids are sent only as SHA-256 hashes. The token stays on the server and is never sent to the app or the download page.
              Purchase is sent once per order, only after the payment is approved.
            </p>
          </Card>
        </div>
      </div>

      <div className="mb-3 mt-8 flex items-center justify-between">
        <h2 className="font-semibold">Recent events</h2>
        <p className="text-sm text-gray-500">
          {ok} received · {failed} failed (last {list.length})
        </p>
      </div>
      {list.length === 0 ? (
        <Empty>No events yet. They appear here once tracking is on and people use the app.</Empty>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>Event</Th>
              <Th>User</Th>
              <Th>Value</Th>
              <Th>Status</Th>
              <Th>Meta&apos;s answer</Th>
              <Th>Time</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {list.map((e) => (
              <tr key={e.id}>
                <Td className="font-medium">{e.event_name}</Td>
                <Td className="text-xs text-gray-600">{e.email ?? "—"}</Td>
                <Td>{e.value != null ? `₹${Number(e.value).toFixed(2)}` : "—"}</Td>
                <Td>
                  <StatusBadge status={e.status} />
                  {e.attempts > 1 && <p className="mt-1 text-xs text-gray-400">{e.attempts} tries</p>}
                </Td>
                <Td>
                  <code className="block max-w-72 break-all text-[11px] text-gray-600">{e.response ?? "—"}</code>
                </Td>
                <Td className="whitespace-nowrap text-xs text-gray-600">{formatDate(e.created_at)}</Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </>
  );
}
