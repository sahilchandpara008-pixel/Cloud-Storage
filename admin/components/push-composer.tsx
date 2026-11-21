"use client";

import { useEffect, useMemo, useState } from "react";
import { Button, Card, Field, Input, Select, Textarea } from "@/components/ui";
import { extension } from "@/lib/media";
import { createClient, publicUrl } from "@/lib/supabase/browser";

type Option = { id: string; name: string };

const AUDIENCES: { value: string; title: string; sub: string }[] = [
  { value: "all", title: "All app users", sub: "Everyone who allowed notifications" },
  { value: "members", title: "All channel members", sub: "Joined at least one channel" },
  { value: "channels", title: "Pick channels", sub: "Members of the channels you tick" },
  { value: "not_premium", title: "Not Premium", sub: "Good for offers" },
  { value: "premium", title: "Premium", sub: "Has an active plan" },
  { value: "ads", title: "Ads installs", sub: "Came from Meta ads" },
  { value: "organic", title: "Organic installs", sub: "Everyone else" },
  { value: "logged_in", title: "Logged in", sub: "Have an account" },
  { value: "guests", title: "Guests", sub: "Not logged in yet" },
];

const ACTIONS = [
  ["home", "App home"],
  ["premium", "Premium page"],
  ["post", "A video"],
  ["channel", "A channel"],
  ["url", "Website link"],
] as const;

function Step({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <h2 className="mb-4 flex items-center gap-2.5 text-base font-semibold text-gray-900">
      <span className="grid h-6 w-6 place-items-center rounded-full bg-brand-50 text-xs font-bold text-brand-600">{n}</span>
      {children}
    </h2>
  );
}

// "New message" form with a live Android lock-screen preview.
export function PushComposer({
  action,
  posts,
  channels,
  sentTodayAll,
  myPhones,
}: {
  action: (formData: FormData) => Promise<void>;
  posts: Option[];
  channels: Option[];
  sentTodayAll: number;
  myPhones: number;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [image, setImage] = useState("");
  const [imgStatus, setImgStatus] = useState<string | null>(null);
  const [tap, setTap] = useState<string>("home");
  const [postQuery, setPostQuery] = useState("");
  const [postId, setPostId] = useState("");
  const [channelId, setChannelId] = useState("");
  const [url, setUrl] = useState("");
  const [audience, setAudience] = useState("all");
  const [picked, setPicked] = useState<string[]>([]);
  const [when, setWhen] = useState<"now" | "later">("now");
  const [reach, setReach] = useState<number | null>(null);

  useEffect(() => {
    let live = true;
    const t = setTimeout(async () => {
      const { data } = await createClient().rpc("admin_push_reach", {
        p_audience: audience,
        p_channel_ids: audience === "channels" ? picked : [],
      });
      if (live) setReach(typeof data === "number" ? data : null);
    }, 250);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [audience, picked]);

  const shownPosts = useMemo(() => {
    const q = postQuery.trim().toLowerCase();
    return (q ? posts.filter((p) => p.name.toLowerCase().includes(q)) : posts).slice(0, 100);
  }, [posts, postQuery]);

  async function onFile(file: File | undefined) {
    if (!file) return;
    if (!/^image\/(jpeg|png)$/.test(file.type)) return setImgStatus("Use a JPG or PNG image.");
    if (file.size > 1024 * 1024) return setImgStatus("Image must be 1 MB or smaller.");
    setImgStatus("Uploading…");
    const key = `push/${crypto.randomUUID()}.${extension(file)}`;
    const { error } = await createClient()
      .storage.from("public")
      .upload(key, file, { contentType: file.type, upsert: false });
    if (error) return setImgStatus(error.message);
    setImage(publicUrl(key) ?? "");
    setImgStatus(null);
  }

  const chip = (on: boolean) =>
    `rounded-full border px-3 py-1.5 text-sm ${
      on ? "border-brand-500 bg-brand-500 font-semibold text-ink-900" : "border-gray-300 text-gray-700 hover:bg-gray-100"
    }`;

  return (
    <form action={action} className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
      <div className="space-y-5">
        <Card>
          <Step n={1}>Message</Step>
          <div className="space-y-4">
            <Field label="Title" hint={`Shown in bold. Keep it short. · ${title.length} / 65`}>
              <Input name="title" maxLength={65} required value={title} onChange={(e) => setTitle(e.target.value)} placeholder="🔥 New release: …" />
            </Field>
            <Field label="Message" hint={`${body.length} / 240`}>
              <Textarea name="body" rows={2} maxLength={240} value={body} onChange={(e) => setBody(e.target.value)} placeholder="All episodes are out now. Tap to watch." />
            </Field>
            <div>
              <p className="mb-1.5 text-sm font-medium text-gray-700">
                Image <span className="font-normal text-gray-500">(optional · wide 2:1 works best · JPG or PNG up to 1 MB)</span>
              </p>
              <div className="flex flex-wrap items-center gap-4">
                {image ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={image} alt="" className="h-20 w-40 shrink-0 rounded-xl object-cover ring-1 ring-gray-200" />
                ) : (
                  <div className="grid h-20 w-40 shrink-0 place-items-center rounded-xl border border-dashed border-gray-300 text-xs text-gray-500">
                    No image
                  </div>
                )}
                <div className="min-w-0 flex-1 space-y-2">
                  <Input type="file" accept="image/jpeg,image/png" onChange={(e) => onFile(e.target.files?.[0])} aria-label="Image" />
                  {image && (
                    <Button type="button" variant="danger" onClick={() => setImage("")}>
                      Remove image
                    </Button>
                  )}
                  {imgStatus && <p className="text-xs text-gray-500">{imgStatus}</p>}
                </div>
              </div>
              <input type="hidden" name="image_url" value={image} />
            </div>
          </div>
        </Card>

        <Card>
          <Step n={2}>When tapped, open</Step>
          <div className="mb-4 flex flex-wrap gap-2">
            {ACTIONS.map(([v, l]) => (
              <button key={v} type="button" className={chip(tap === v)} onClick={() => setTap(v)}>
                {l}
              </button>
            ))}
          </div>
          <input type="hidden" name="action_type" value={tap} />
          {tap === "post" && (
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Search videos">
                <Input value={postQuery} onChange={(e) => setPostQuery(e.target.value)} placeholder="Type a title" />
              </Field>
              <Field label="Video" hint="Published videos, newest first">
                <Select name="post_id" value={postId} onChange={(e) => setPostId(e.target.value)} required>
                  <option value="">Choose a video</option>
                  {shownPosts.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>
          )}
          {tap === "channel" && (
            <Field label="Channel">
              <Select name="channel_id" value={channelId} onChange={(e) => setChannelId(e.target.value)} required>
                <option value="">Choose a channel</option>
                {channels.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          {tap === "url" && (
            <Field label="Link" hint="Opens in the phone's browser">
              <Input name="url" type="url" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://" required />
            </Field>
          )}
        </Card>

        <Card>
          <Step n={3}>Send to</Step>
          <div className="grid gap-3 sm:grid-cols-3">
            {AUDIENCES.map((a) => {
              const on = audience === a.value;
              return (
                <button
                  key={a.value}
                  type="button"
                  onClick={() => setAudience(a.value)}
                  className={`relative rounded-xl border p-3 text-left ${on ? "border-brand-500 bg-brand-50" : "border-gray-200 hover:bg-gray-50"}`}
                >
                  {on && (
                    <span className="absolute right-3 top-3 grid h-5 w-5 place-items-center rounded-full bg-brand-500 text-[11px] font-bold text-ink-900">
                      ✓
                    </span>
                  )}
                  <span className="block text-sm font-semibold text-gray-900">{a.title}</span>
                  <span className="mt-0.5 block text-xs text-gray-500">{a.sub}</span>
                </button>
              );
            })}
          </div>
          <input type="hidden" name="audience" value={audience} />
          {audience === "channels" && (
            <div className="mt-4 flex max-h-48 flex-wrap gap-2 overflow-y-auto">
              {channels.map((c) => {
                const on = picked.includes(c.id);
                return (
                  <label key={c.id} className={`cursor-pointer ${chip(on)}`}>
                    <input
                      type="checkbox"
                      name="channel_ids"
                      value={c.id}
                      checked={on}
                      onChange={() => setPicked(on ? picked.filter((x) => x !== c.id) : [...picked, c.id])}
                      className="sr-only"
                    />
                    {c.name}
                  </label>
                );
              })}
            </div>
          )}
          <div className="mt-4 flex flex-wrap items-center gap-2 rounded-xl border border-green-800 bg-green-950/40 px-4 py-3 text-sm text-green-300">
            📱 Will reach <b className="text-base text-[#86efac]">{reach === null ? "…" : `${reach.toLocaleString("en-IN")} phones`}</b>
            <span className="text-gray-500">· people on app 1.11.9 or newer who allowed notifications</span>
          </div>
        </Card>

        <Card>
          <Step n={4}>When</Step>
          <div className="flex flex-wrap items-center gap-3">
            <span className="inline-flex gap-1 rounded-xl border border-gray-200 p-1">
              {(["now", "later"] as const).map((w) => (
                <button
                  key={w}
                  type="button"
                  onClick={() => setWhen(w)}
                  className={`rounded-lg px-3 py-1.5 text-sm ${when === w ? "bg-gray-900 font-semibold text-gray-50" : "text-gray-600"}`}
                >
                  {w === "now" ? "Send now" : "Schedule"}
                </button>
              ))}
            </span>
            <input type="hidden" name="when" value={when} />
            {when === "later" && (
              <label className="flex items-center gap-2 text-sm text-gray-600">
                <Input type="datetime-local" name="scheduled_at" required className="w-auto!" />
                India time
              </label>
            )}
          </div>
          {audience === "all" && sentTodayAll > 0 && (
            <p className="mt-4 rounded-xl border border-amber-800 bg-amber-950/40 px-4 py-3 text-sm text-amber-300">
              ⚠️ You already sent {sentTodayAll} message{sentTodayAll === 1 ? "" : "s"} to all users today. More than 1 a day
              makes people turn notifications off.
            </p>
          )}
        </Card>

        <div className="flex flex-wrap items-center justify-end gap-3">
          <span className="text-xs text-gray-500">
            {myPhones > 0 ? `Test goes to your ${myPhones} phone${myPhones === 1 ? "" : "s"}` : "Open the app on your phone (logged in as you) to receive tests"}
          </span>
          <Button type="submit" name="mode" value="test" variant="secondary" disabled={!title}>
            📲 Send test to my phone
          </Button>
          <Button type="submit" name="mode" value="send" disabled={!title}>
            {when === "later" ? "Schedule" : reach ? `Send to ${reach.toLocaleString("en-IN")} phones` : "Send"}
          </Button>
        </div>
      </div>

      <div className="lg:sticky lg:top-6">
        <div className="mb-3 flex justify-between text-xs font-medium text-gray-500">
          <span>Live preview</span>
          <span>Android</span>
        </div>
        <div className="mx-auto w-[300px] rounded-[38px] border border-gray-200 bg-black p-2.5 shadow-2xl">
          <div className="min-h-[540px] rounded-[30px] px-2.5 py-3" style={{ background: "linear-gradient(160deg,#1e293b,#0f172a 60%,#1c1917)" }}>
            <div className="flex justify-between px-3 text-xs font-semibold text-[#e5e7eb]">
              <span>9:41</span>
              <span>▾ ▮ 86%</span>
            </div>
            <p className="mt-6 text-center text-5xl font-light text-white">9:41</p>
            <p className="mb-5 text-center text-xs text-slate-300">Today</p>
            <div className="rounded-[20px] bg-slate-100/95 p-3 text-slate-900">
              <div className="flex items-center gap-2 text-[11px] text-slate-600">
                <span className="grid h-[18px] w-[18px] place-items-center rounded-[5px] bg-[#ff7a1a] text-[10px] font-extrabold text-white">F</span>
                Flixvault · now
              </div>
              <p className="mt-1.5 break-words text-sm font-bold">{title || "Your title"}</p>
              {(body || !title) && <p className="break-words text-[13px] leading-snug text-slate-700">{body || "Your message"}</p>}
              {image && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={image} alt="" className="mt-2.5 h-32 w-full rounded-xl object-cover" />
              )}
            </div>
          </div>
        </div>
        <p className="mt-3 text-center text-xs text-gray-500">Updates as you type</p>
      </div>
    </form>
  );
}
