import { Button, Card, Field, Input, SectionTitle, Select, Table, Td, Th } from "@/components/ui";

type Kind = { enabled: boolean; title: string; body: string; nv_mode: string; interval_hours: number };
type Channel = { id: string; name: string; members: number; mode: string | null };
export type AutoSettings = { kinds: Record<string, Kind>; channels: Channel[]; sent_7d: Record<string, number> };

const ROWS: { kind: string; icon: string; title: string; sub: string; vars: string }[] = [
  {
    kind: "payment_reminder",
    icon: "🛒",
    title: "Payment reminder",
    sub: "Sent once, 1 hour after someone started paying for a plan but didn't finish (at most once a day). Tapping opens Premium.",
    vars: "{plan} {price} {duration}",
  },
  {
    kind: "payment_approved",
    icon: "✅",
    title: "Payment approved",
    sub: "Sent as soon as a payment is approved (by the UPI app or by you).",
    vars: "{plan} {price} {duration} {end_date}",
  },
  {
    kind: "plan_ending",
    icon: "⏰",
    title: "Plan ending",
    sub: "Sent 1 day before a plan ends (not if they already bought a longer one). Tapping opens Premium.",
    vars: "{plan} {end_date}",
  },
  {
    kind: "come_back",
    icon: "💤",
    title: "Come back",
    sub: "Sent once to phones that haven't opened the app for 7 days.",
    vars: "",
  },
];

function Toggle({ on }: { on: boolean }) {
  return (
    <label className="relative inline-flex shrink-0 cursor-pointer items-center gap-2 text-sm text-gray-700">
      <input type="checkbox" name="enabled" defaultChecked={on} className="peer sr-only" />
      <span className="relative h-6 w-11 rounded-full bg-gray-300 transition-colors peer-checked:bg-brand-500 after:absolute after:left-1 after:top-1 after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:after:translate-x-5" />
      <span className="peer-checked:hidden">Off</span>
      <span className="hidden peer-checked:inline">On</span>
    </label>
  );
}

// Automatic messages tab: one form per message type + per-channel settings.
export function PushAuto({
  data,
  saveAuto,
  saveChannelMode,
}: {
  data: AutoSettings;
  saveAuto: (kind: string, formData: FormData) => Promise<void>;
  saveChannelMode: (channelId: string, formData: FormData) => Promise<void>;
}) {
  const nv = data.kinds?.new_videos;
  const sent = data.sent_7d ?? {};
  const defaultLabel = nv?.nv_mode === "members" ? "Channel members only" : "All app users";
  return (
    <div className="space-y-5">
      {nv && (
        <Card>
          <SectionTitle action={<span className="text-xs text-gray-500">{sent.new_videos ?? 0} sent in the last 7 days</span>}>
            New videos
          </SectionTitle>
          <form action={saveAuto.bind(null, "new_videos")} className="space-y-4">
            <div className="flex flex-wrap items-end gap-4">
              <Toggle on={nv.enabled} />
              <Field label="When a new video goes live, tell">
                <Select name="nv_mode" defaultValue={nv.nv_mode} className="w-56!">
                  <option value="all">All app users</option>
                  <option value="members">Channel members only</option>
                </Select>
              </Field>
              <Field label="At most">
                <Select name="interval_hours" defaultValue={String(nv.interval_hours)} className="w-56!">
                  {[1, 2, 4, 6, 12, 24].map((h) => (
                    <option key={h} value={h}>
                      1 message every {h} hour{h === 1 ? "" : "s"}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Title (one new video)" hint="{channel} {title}">
                <Input name="title" defaultValue={nv.title} maxLength={65} required />
              </Field>
              <Field label="Text" hint="Several new videos together: “5 new videos in {channel}”">
                <Input name="body" defaultValue={nv.body} maxLength={240} />
              </Field>
            </div>
            <p className="text-xs text-gray-500">
              Sent with the video&apos;s thumbnail; tapping opens the video (or the channel when there are several). Ads-only
              videos go only to ads installs. Only videos that go live after you turn this on are announced.
            </p>
            <Button type="submit">Save</Button>
          </form>

          <div className="mt-5">
            <Table>
              <thead>
                <tr>
                  <Th>Channel</Th>
                  <Th>Members</Th>
                  <Th>Tell about new videos</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {data.channels.map((c) => (
                  <tr key={c.id}>
                    <Td className="font-semibold text-gray-900">{c.name}</Td>
                    <Td className="tabular-nums">{c.members}</Td>
                    <Td>
                      <form action={saveChannelMode.bind(null, c.id)} className="flex flex-wrap items-center gap-2">
                        <Select name="mode" defaultValue={c.mode ?? "default"} className="w-56!">
                          <option value="default">Default ({defaultLabel})</option>
                          <option value="all">All app users</option>
                          <option value="members">Channel members only</option>
                          <option value="off">Off</option>
                        </Select>
                        <Button type="submit" variant="secondary">
                          Save
                        </Button>
                      </form>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          </div>
        </Card>
      )}

      <Card>
        <SectionTitle>Payments &amp; plans</SectionTitle>
        <div className="divide-y divide-gray-200">
          {ROWS.map((r) => {
            const k = data.kinds?.[r.kind];
            if (!k) return null;
            return (
              <form key={r.kind} action={saveAuto.bind(null, r.kind)} className="flex flex-wrap gap-4 py-5 first:pt-0 last:pb-0">
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-brand-50 text-lg">{r.icon}</span>
                <div className="min-w-0 flex-1 basis-80 space-y-3">
                  <div>
                    <p className="font-semibold text-gray-900">
                      {r.title}{" "}
                      <span className="text-xs font-normal text-gray-500">· {sent[r.kind] ?? 0} sent in the last 7 days</span>
                    </p>
                    <p className="text-sm text-gray-500">{r.sub}</p>
                  </div>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <Field label="Title" hint={r.vars ? `You can use ${r.vars}` : undefined}>
                      <Input name="title" defaultValue={k.title} maxLength={65} required />
                    </Field>
                    <Field label="Text">
                      <Input name="body" defaultValue={k.body} maxLength={240} />
                    </Field>
                  </div>
                </div>
                <div className="flex flex-col items-end gap-3">
                  <Toggle on={k.enabled} />
                  <Button type="submit">Save</Button>
                </div>
              </form>
            );
          })}
        </div>
      </Card>
    </div>
  );
}
