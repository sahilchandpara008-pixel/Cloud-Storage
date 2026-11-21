import Link from "next/link";
import { PushAuto, type AutoSettings } from "@/components/push-auto";
import { PushComposer } from "@/components/push-composer";
import { Badge, Button, Empty, Flash, PageHeader, Stat, Table, Td, Th } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { cancelPush, saveAuto, saveChannelMode, sendPush } from "./actions";

type Msg = {
  id: string;
  kind: string;
  title: string;
  body: string;
  audience: string;
  status: string;
  scheduled_at: string;
  sent_at: string | null;
  created_at: string;
  recipients: number;
  sent: number;
  failed: number;
  opened: number;
};
type Overview = {
  reachable: number;
  tokens: number;
  my_phones: number;
  sent_7d: number;
  sent_today_all: number;
  configured: boolean;
  last_error: string | null;
  messages: Msg[];
};

const AUDIENCE_LABEL: Record<string, string> = {
  all: "All app users",
  members: "All channel members",
  channels: "Chosen channels",
  premium: "Premium",
  not_premium: "Not Premium",
  ads: "Ads installs",
  organic: "Organic installs",
  logged_in: "Logged in",
  guests: "Guests",
  test: "Test (my phone)",
};

const KIND_LABEL: Record<string, string> = {
  manual: "Manual",
  new_videos: "New videos",
  payment_reminder: "Payment reminder",
  payment_approved: "Payment approved",
  plan_ending: "Plan ending",
  come_back: "Come back",
};

const when = (iso: string | null) =>
  iso
    ? new Date(iso).toLocaleString("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" })
    : "—";

function Tabs({ tab }: { tab: string }) {
  return (
    <nav className="mb-6 inline-flex max-w-full flex-wrap gap-1 rounded-xl border border-gray-200 bg-white p-1">
      {[
        ["send", "New message"],
        ["auto", "Automatic"],
        ["history", "History"],
      ].map(([k, l]) => (
        <Link
          key={k}
          href={k === "send" ? "/notifications" : `/notifications?tab=${k}`}
          aria-current={k === tab ? "page" : undefined}
          className={`rounded-lg px-3 py-1.5 text-sm font-medium ${k === tab ? "bg-gray-900 font-semibold text-gray-50" : "text-gray-600 hover:bg-gray-100"}`}
        >
          {l}
        </Link>
      ))}
    </nav>
  );
}

async function firebaseKeySet() {
  try {
    const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/push-send`, { cache: "no-store" });
    return Boolean((await res.json())?.key);
  } catch {
    return false;
  }
}

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string; ok?: string; error?: string }>;
}) {
  const sp = await searchParams;
  const tab = sp.tab === "history" || sp.tab === "auto" ? sp.tab : "send";
  const { supabase } = await requireOwner();
  const [{ data: ov }, { data: posts }, { data: channels }, keySet, { data: auto }] = await Promise.all([
    supabase.rpc("admin_push_overview", { p_limit: 100 }),
    supabase
      .from("posts")
      .select("id, title")
      .eq("status", "published")
      .order("published_at", { ascending: false, nullsFirst: false })
      .limit(500),
    supabase.from("channels").select("id, name").order("name"),
    firebaseKeySet(),
    supabase.rpc("admin_push_auto_get"),
  ]);
  const o = (ov ?? {}) as Overview;
  const messages = o.messages ?? [];
  const sentTotal = messages.filter((m) => m.audience !== "test").reduce((s, m) => s + m.sent, 0);
  const openedTotal = messages.filter((m) => m.audience !== "test").reduce((s, m) => s + m.opened, 0);

  return (
    <>
      <PageHeader
        title="Notifications"
        subtitle={
          tab === "send"
            ? "Send a message with an image to people's phones — new releases, offers and announcements."
            : tab === "auto"
              ? "Messages the app sends by itself. Turn each one on or off and edit its text."
              : "Every message sent or scheduled, and how many people tapped it."
        }
      />
      <Flash ok={sp.ok} error={sp.error} />
      {!keySet && (
        <p className="mb-5 rounded-xl border border-red-800 bg-red-950/40 px-4 py-3 text-sm text-red-300">
          Firebase key missing: messages can&apos;t be delivered yet. Add the secret <b>FCM_SERVICE_ACCOUNT</b> in Supabase →
          Edge Functions → Secrets (Firebase → Project settings → Service accounts → Generate new private key).
        </p>
      )}
      {keySet && o.last_error && (
        <p className="mb-5 rounded-xl border border-amber-800 bg-amber-950/40 px-4 py-3 text-sm text-amber-300">
          Last delivery problem: {o.last_error}
        </p>
      )}
      <Tabs tab={tab} />

      {tab === "auto" ? (
        <PushAuto data={(auto ?? { kinds: {}, channels: [], sent_7d: {} }) as AutoSettings} saveAuto={saveAuto} saveChannelMode={saveChannelMode} />
      ) : tab === "send" ? (
        <PushComposer
          action={sendPush}
          posts={(posts ?? []).map((p) => ({ id: p.id as string, name: p.title as string }))}
          channels={(channels ?? []).map((c) => ({ id: c.id as string, name: c.name as string }))}
          sentTodayAll={Number(o.sent_today_all ?? 0)}
          myPhones={Number(o.my_phones ?? 0)}
        />
      ) : (
        <div className="space-y-5">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Phones that can receive" value={Number(o.reachable ?? 0).toLocaleString("en-IN")} icon="📱" hint="allowed notifications, app 1.11.9+" />
            <Stat label="Phones registered" value={Number(o.tokens ?? 0).toLocaleString("en-IN")} icon="🔔" tone="green" />
            <Stat label="Sent · last 7 days" value={Number(o.sent_7d ?? 0)} icon="✉" tone="blue" hint="messages" />
            <Stat
              label="Tap rate"
              value={sentTotal > 0 ? `${((openedTotal / sentTotal) * 100).toFixed(1)}%` : "—"}
              icon="👆"
              tone="purple"
              hint="of the messages below"
            />
          </div>
          {messages.length === 0 ? (
            <Empty icon="🔔">No messages yet. Write one in “New message”.</Empty>
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>When</Th>
                  <Th>Message</Th>
                  <Th>To</Th>
                  <Th>Type</Th>
                  <Th>Status</Th>
                  <Th>Sent</Th>
                  <Th>Tapped</Th>
                  <Th />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {messages.map((m) => (
                  <tr key={m.id}>
                    <Td className="whitespace-nowrap">{when(m.sent_at ?? m.scheduled_at)}</Td>
                    <Td>
                      <p className="font-semibold text-gray-900">{m.title}</p>
                      {m.body && <p className="max-w-md truncate text-xs text-gray-500">{m.body}</p>}
                    </Td>
                    <Td>
                      {m.kind === "manual"
                        ? (AUDIENCE_LABEL[m.audience] ?? m.audience)
                        : m.kind === "new_videos"
                          ? m.audience === "channels"
                            ? "Channel members"
                            : "All app users"
                          : "1 person"}
                    </Td>
                    <Td>
                      <Badge tone={m.kind === "manual" ? "blue" : m.kind === "new_videos" ? "gray" : "green"}>
                        {KIND_LABEL[m.kind] ?? m.kind}
                      </Badge>
                    </Td>
                    <Td>
                      {m.status === "scheduled" ? (
                        <Badge tone="amber">Scheduled</Badge>
                      ) : m.status === "sending" ? (
                        <Badge tone="blue">Sending</Badge>
                      ) : m.status === "cancelled" ? (
                        <Badge>Cancelled</Badge>
                      ) : (
                        <Badge tone="green">Sent</Badge>
                      )}
                    </Td>
                    <Td className="whitespace-nowrap tabular-nums">
                      {m.status === "scheduled" || m.status === "cancelled" ? "—" : `${m.sent} / ${m.recipients}`}
                      {m.failed > 0 && <span className="ml-1 text-xs text-red-700">({m.failed} failed)</span>}
                    </Td>
                    <Td className="whitespace-nowrap tabular-nums">
                      {m.sent > 0 ? `${m.opened} (${((m.opened / m.sent) * 100).toFixed(1)}%)` : "—"}
                    </Td>
                    <Td>
                      {m.status === "scheduled" && (
                        <form action={cancelPush.bind(null, m.id)}>
                          <Button type="submit" variant="danger" className="whitespace-nowrap">
                            Cancel
                          </Button>
                        </form>
                      )}
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
          <p className="text-xs text-gray-500">
            “Sent” means Firebase accepted the message for that phone. “Tapped” counts people who opened the app from it.
          </p>
        </div>
      )}
    </>
  );
}
