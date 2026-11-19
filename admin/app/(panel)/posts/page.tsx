import Link from "next/link";
import { DatePresets } from "@/components/date-range";
import {
  AudienceBadge,
  Badge,
  Button,
  Empty,
  Flash,
  Input,
  LinkButton,
  PageHeader,
  Select,
  StatusBadge,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { dayEnd, dayStart, isDate } from "@/lib/dates";
import { AUDIENCES, STATUSES, formatDate } from "@/lib/format";
import { publicUrl } from "@/lib/supabase/browser";

type Row = {
  id: string;
  title: string;
  audience: string;
  status: string;
  published_at: string | null;
  view_count: number;
  channels: { name: string } | null;
  channel_folders: { name: string } | null;
  post_items: { is_premium: boolean; thumb_key: string | null; position: number; processing_status: string }[];
};

// Why a published post isn't live in the app yet (the database hides it).
function hiddenReason(p: Row, now: number) {
  if (p.status !== "published") return null;
  if (p.post_items.some((i) => i.processing_status === "failed")) return { tone: "red" as const, text: "Video failed" };
  if (p.post_items.some((i) => i.processing_status === "pending")) return { tone: "blue" as const, text: "Encoding…" };
  if (p.published_at && new Date(p.published_at).getTime() > now) {
    const hours = Math.max(1, Math.round((new Date(p.published_at).getTime() - now) / 3_600_000));
    return { tone: "blue" as const, text: `Scheduled · in ${hours} h` };
  }
  return null;
}

export default async function PostsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string; channel?: string; folder?: string; audience?: string; status?: string; q?: string; sort?: string; from?: string; to?: string }>;
}) {
  const sp = await searchParams;
  const { supabase } = await requireAdmin();

  const { data: channels } = await supabase.from("channels").select("id, name").order("name");

  let query = supabase
    .from("posts")
    .select("id, title, audience, status, published_at, view_count, channels(name), channel_folders(name), post_items(is_premium, thumb_key, position, processing_status)")
    .limit(300);
  const from = isDate(sp.from) ? sp.from : undefined;
  const to = isDate(sp.to) ? sp.to : undefined;
  if (dayStart(from)) query = query.gte("created_at", dayStart(from)!);
  if (dayEnd(to)) query = query.lt("created_at", dayEnd(to)!);
  if (sp.sort === "oldest") query = query.order("created_at", { ascending: true });
  else if (sp.sort === "views") query = query.order("view_count", { ascending: false });
  else if (sp.sort === "title") query = query.order("title", { ascending: true });
  else if (sp.sort === "published") query = query.order("published_at", { ascending: false, nullsFirst: false });
  else query = query.order("created_at", { ascending: false });
  if (sp.channel) query = query.eq("channel_id", sp.channel);
  if (sp.folder) query = query.eq("folder_id", sp.folder);
  if (sp.audience) query = query.eq("audience", sp.audience);
  if (sp.status) query = query.eq("status", sp.status);
  const q = sp.q?.trim();
  if (q) query = query.ilike("title", `%${q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`);
  const { data } = await query;
  const rows = (data ?? []) as unknown as Row[];

  const now = Date.now();

  return (
    <>
      <PageHeader
        title="Posts"
        subtitle="Everything posted to channels. Published posts appear in the app's Explore and Feed."
        action={
          <div className="flex gap-2">
            <LinkButton variant="secondary" href={sp.channel ? `/posts/new?mode=bulk&channel=${sp.channel}` : "/posts/new?mode=bulk"}>
              Bulk upload
            </LinkButton>
            <LinkButton href={sp.channel ? `/posts/new?channel=${sp.channel}` : "/posts/new"}>New post</LinkButton>
          </div>
        }
      />
      <Flash ok={sp.ok} error={sp.error} />

      <DatePresets
        className="mb-3"
        from={isDate(sp.from) ? sp.from : undefined}
        to={isDate(sp.to) ? sp.to : undefined}
        href={(f, t) => {
          const p = new URLSearchParams();
          for (const [k, v] of Object.entries({ ...sp, ok: undefined, error: undefined, from: f, to: t })) if (v) p.set(k, v);
          return `/posts?${p.toString()}`;
        }}
      />
      <form className="mb-4 grid gap-3 sm:grid-cols-4 lg:grid-cols-8">
        <Input name="q" defaultValue={sp.q ?? ""} placeholder="Search titles" aria-label="Search titles" />
        {sp.folder && <input type="hidden" name="folder" value={sp.folder} />}
        <Select name="channel" defaultValue={sp.channel ?? ""} aria-label="Channel">
          <option value="">All channels</option>
          {(channels ?? []).map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </Select>
        <Select name="audience" defaultValue={sp.audience ?? ""} aria-label="Audience">
          <option value="">Any audience</option>
          {AUDIENCES.map((a) => (
            <option key={a.value} value={a.value}>{a.label}</option>
          ))}
        </Select>
        <Select name="status" defaultValue={sp.status ?? ""} aria-label="Status">
          <option value="">Any status</option>
          {STATUSES.map((s) => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </Select>
        <Select name="sort" defaultValue={sp.sort ?? "newest"} aria-label="Sort">
          <option value="newest">Newest first</option>
          <option value="oldest">Oldest first</option>
          <option value="published">Latest published</option>
          <option value="views">Most views</option>
          <option value="title">Title A–Z</option>
        </Select>
        <Input type="date" name="from" defaultValue={isDate(sp.from) ? sp.from : ""} aria-label="Uploaded from" title="Uploaded from" />
        <Input type="date" name="to" defaultValue={isDate(sp.to) ? sp.to : ""} aria-label="Uploaded to" title="Uploaded to" />
        <Button variant="secondary" type="submit">Filter</Button>
      </form>

      {rows.length === 0 ? (
        <Empty>No posts match. Create a post to get started.</Empty>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>Post</Th>
              <Th>Channel</Th>
              <Th>Audience</Th>
              <Th>Status</Th>
              <Th>Media</Th>
              <Th className="text-right">Views</Th>
              <Th>Publish time</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map((p) => {
              const premium = p.post_items.filter((i) => i.is_premium).length;
              const thumb = [...p.post_items].sort((a, b) => a.position - b.position)[0]?.thumb_key;
              const hidden = hiddenReason(p, now);
              return (
                <tr key={p.id} className="hover:bg-gray-50">
                  <Td>
                    <Link href={`/posts/${p.id}`} className="flex items-center gap-3 font-medium text-gray-900 hover:text-brand-700">
                      {thumb ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={publicUrl(thumb)!}
                          alt=""
                          loading="lazy"
                          decoding="async"
                          className="h-10 w-10 shrink-0 rounded object-cover"
                        />
                      ) : (
                        <span className="h-10 w-10 shrink-0 rounded bg-gray-100" />
                      )}
                      {p.title}
                    </Link>
                  </Td>
                  <Td>
                    {p.channels?.name}
                    {p.channel_folders && <span className="text-gray-500"> › {p.channel_folders.name}</span>}
                  </Td>
                  <Td><AudienceBadge audience={p.audience} /></Td>
                  <Td>{hidden ? <Badge tone={hidden.tone}>{hidden.text}</Badge> : <StatusBadge status={p.status} />}</Td>
                  <Td>
                    {p.post_items.length} {premium > 0 && <Badge tone="amber">👑 {premium}</Badge>}
                  </Td>
                  <Td className="text-right tabular-nums">{p.view_count}</Td>
                  <Td className="whitespace-nowrap">{formatDate(p.published_at)}</Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </>
  );
}
