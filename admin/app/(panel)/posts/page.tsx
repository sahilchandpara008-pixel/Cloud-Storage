import Link from "next/link";
import {
  AudienceBadge,
  Badge,
  Button,
  Empty,
  Flash,
  LinkButton,
  PageHeader,
  Select,
  StatusBadge,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
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
  searchParams: Promise<{ ok?: string; error?: string; channel?: string; folder?: string; audience?: string; status?: string }>;
}) {
  const sp = await searchParams;
  const { supabase } = await requireAdmin();

  const { data: channels } = await supabase.from("channels").select("id, name").order("name");

  let query = supabase
    .from("posts")
    .select("id, title, audience, status, published_at, view_count, channels(name), channel_folders(name), post_items(is_premium, thumb_key, position, processing_status)")
    .order("created_at", { ascending: false })
    .limit(200);
  if (sp.channel) query = query.eq("channel_id", sp.channel);
  if (sp.folder) query = query.eq("folder_id", sp.folder);
  if (sp.audience) query = query.eq("audience", sp.audience);
  if (sp.status) query = query.eq("status", sp.status);
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
            <LinkButton variant="secondary" href="/posts/bulk">Bulk upload</LinkButton>
            <LinkButton href={sp.channel ? `/posts/new?channel=${sp.channel}` : "/posts/new"}>New post</LinkButton>
          </div>
        }
      />
      <Flash ok={sp.ok} error={sp.error} />

      <form className="mb-4 grid gap-3 sm:grid-cols-4">
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
                    <Link href={`/posts/${p.id}`} className="flex items-center gap-3 font-medium text-gray-900 hover:text-red-700">
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
