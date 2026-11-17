import { Badge, Button, Card, Field, Flash, Input, PageHeader, Select, Table, Td, Th } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { addAdmin, removeAdmin } from "./actions";

type AdminRow = {
  user_id: string;
  email: string;
  role: "owner" | "content_admin";
  created_at: string;
  channel_ids: string[];
};

export default async function AdminsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { ok, error } = await searchParams;
  const { supabase, user } = await requireOwner();
  const [{ data }, { data: channels }] = await Promise.all([
    supabase.rpc("admin_list_admins"),
    supabase.from("channels").select("id, name").order("name"),
  ]);
  const admins = (data ?? []) as AdminRow[];
  const channelName = new Map((channels ?? []).map((c) => [c.id, c.name]));

  return (
    <>
      <PageHeader title="Admins" subtitle="People who can sign in to this panel." />
      <Flash ok={ok} error={error} />

      <div className="grid gap-6 xl:grid-cols-3">
        <div className="xl:col-span-2">
          <Table>
            <thead>
              <tr>
                <Th>Email</Th>
                <Th>Role</Th>
                <Th>Channels</Th>
                <Th>Added</Th>
                <Th />
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {admins.map((a) => (
                <tr key={a.user_id}>
                  <Td className="font-medium">{a.email}</Td>
                  <Td>{a.role === "owner" ? <Badge tone="red">Owner</Badge> : <Badge>Content admin</Badge>}</Td>
                  <Td className="text-xs text-gray-600">
                    {a.role === "owner"
                      ? "All"
                      : a.channel_ids.length === 0
                        ? "All channels"
                        : a.channel_ids.map((id) => channelName.get(id) ?? "?").join(", ")}
                  </Td>
                  <Td className="whitespace-nowrap">{formatDate(a.created_at)}</Td>
                  <Td className="text-right">
                    {a.user_id !== user.id && (
                      <form action={removeAdmin.bind(null, a.user_id)}>
                        <button className="text-sm text-red-700 hover:underline">Remove</button>
                      </form>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </div>

        <Card>
          <h2 className="mb-1 font-semibold">Add an admin</h2>
          <p className="mb-4 text-sm text-gray-500">
            Creates a login for them. Share the email and password with them privately.
          </p>
          <form action={addAdmin} className="space-y-3">
            <Field label="Email">
              <Input name="email" type="email" required />
            </Field>
            <Field label="Temporary password" hint="At least 8 characters">
              <Input name="password" type="text" minLength={8} required autoComplete="off" />
            </Field>
            <Field label="Role">
              <Select name="role" defaultValue="content_admin">
                <option value="content_admin">Content admin (channels &amp; posts)</option>
                <option value="owner">Owner (full access)</option>
              </Select>
            </Field>
            <fieldset>
              <legend className="mb-1 text-sm font-medium text-gray-700">Limit to channels (optional)</legend>
              <p className="mb-2 text-xs text-gray-500">Leave all unticked to allow every channel.</p>
              <div className="max-h-40 space-y-1 overflow-y-auto">
                {(channels ?? []).map((c) => (
                  <label key={c.id} className="flex items-center gap-2 text-sm">
                    <input type="checkbox" name="channels" value={c.id} className="h-4 w-4 accent-brand-700" />
                    {c.name}
                  </label>
                ))}
              </div>
            </fieldset>
            <Button type="submit" className="w-full">Add admin</Button>
          </form>
        </Card>
      </div>
    </>
  );
}
