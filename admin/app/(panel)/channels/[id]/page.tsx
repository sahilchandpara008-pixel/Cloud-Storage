import Link from "next/link";
import { redirect } from "next/navigation";
import { ChannelForm, type ChannelValues } from "@/components/channel-form";
import { DeleteButton } from "@/components/delete-button";
import { Button, Card, Flash, Input, LinkButton, PageHeader } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { withMessage } from "@/lib/format";
import { addFolder, deleteChannel, deleteFolder, setFollowers, updateChannel, updateFolder } from "../actions";

type Folder = { id: string; name: string; position: number; posts: { count: number }[] };

export default async function ChannelPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase, role } = await requireAdmin();

  const { data: channel } = await supabase
    .from("channels")
    .select("id, name, handle, description, category, icon_url, audience, status, members_count, followers_offset")
    .eq("id", id)
    .maybeSingle();
  // A deleted channel's link (old tab, bookmark, a late redirect) lands on the
  // list with a note instead of a bare 404.
  if (!channel) redirect(withMessage("/channels", "error", "That channel no longer exists. It may have been deleted."));

  const { data: folderRows } = await supabase
    .from("channel_folders")
    .select("id, name, position, posts(count)")
    .eq("channel_id", id)
    .order("position");
  const folders = (folderRows ?? []) as Folder[];

  const { data: creatorRows } = await supabase.rpc("admin_channel_creators");
  const creator = ((creatorRows ?? []) as { channel_id: string; email: string | null; display_name: string | null }[])
    .find((c) => c.channel_id === id);
  const createdBy = creator?.email ?? creator?.display_name ?? null;

  return (
    <>
      <PageHeader
        title={channel.name}
        subtitle={`${Number(channel.members_count).toLocaleString("en-IN")} followers shown in the app · Created by ${createdBy ?? "admin panel"}`}
        action={
          <div className="flex gap-2">
            <LinkButton variant="secondary" href={`/posts?channel=${id}`}>
              View posts
            </LinkButton>
            <LinkButton variant="secondary" href={`/posts/new?mode=bulk&channel=${id}`}>
              Bulk upload
            </LinkButton>
            <LinkButton href={`/posts/new?channel=${id}`}>New post</LinkButton>
          </div>
        }
      />
      <Flash ok={ok} error={error} />

      <div className="grid gap-6 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <h2 className="mb-4 font-semibold">Channel details</h2>
          <ChannelForm
            action={updateChannel.bind(null, id)}
            values={channel as ChannelValues}
            submitLabel="Save channel"
          />
        </Card>

        <div className="space-y-6">
        <Card>
          <h2 className="mb-1 font-semibold">Followers shown in app</h2>
          <p className="mb-4 text-sm text-gray-500">
            The number people see on this channel in the app. Each real join adds one to it and each leave removes
            one. Real follows right now: {Math.max(0, Number(channel.members_count) - Number(channel.followers_offset ?? 0)).toLocaleString("en-IN")}.
          </p>
          <form action={setFollowers.bind(null, id)} className="flex gap-2">
            <Input
              name="followers"
              inputMode="numeric"
              defaultValue={String(channel.members_count)}
              aria-label="Followers shown in app"
              required
            />
            <Button type="submit">Save</Button>
          </form>
        </Card>

        <Card>
          <h2 className="mb-1 font-semibold">Folders</h2>
          <p className="mb-4 text-sm text-gray-500">Group this channel&apos;s posts. Lower numbers show first.</p>
          <ul className="mb-4 space-y-3">
            {folders.length === 0 && <li className="text-sm text-gray-500">No folders yet.</li>}
            {folders.map((f) => (
              <li key={f.id} className="rounded-lg border border-gray-200 p-3">
                <form action={updateFolder.bind(null, id, f.id)} className="flex items-center gap-2">
                  <div className="w-16 shrink-0">
                    <Input name="position" type="number" defaultValue={f.position} aria-label="Order" />
                  </div>
                  <Input name="name" defaultValue={f.name} required aria-label="Folder name" />
                  <Button variant="secondary" type="submit">Save</Button>
                </form>
                <div className="mt-2 flex items-center justify-between text-xs text-gray-500">
                  <Link href={`/posts?channel=${id}&folder=${f.id}`} className="hover:text-red-700">
                    {f.posts[0]?.count ?? 0} posts
                  </Link>
                  <form action={deleteFolder.bind(null, id, f.id)}>
                    <button className="text-red-700 hover:underline">Delete</button>
                  </form>
                </div>
              </li>
            ))}
          </ul>
          <form action={addFolder.bind(null, id)} className="flex gap-2">
            <Input name="name" placeholder="New folder name" required aria-label="New folder name" />
            <Button type="submit">Add</Button>
          </form>
        </Card>
        </div>
      </div>

      {role === "owner" && (
        <Card className="mt-6 border-red-200">
          <h2 className="font-semibold text-red-800">Delete channel</h2>
          <p className="mb-3 text-sm text-gray-600">
            Deletes the channel with all its folders and posts -- including every uploaded video, image, thumbnail
            and trailer. This cannot be undone.
          </p>
          <form action={deleteChannel.bind(null, id)}>
            <DeleteButton
              label="Delete channel"
              pendingLabel="Deleting… please wait"
              confirmText={`Delete "${channel.name}" and permanently remove every video, image, thumbnail and preview in it? This cannot be undone.`}
            />
          </form>
        </Card>
      )}
    </>
  );
}
