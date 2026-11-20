"use client";

import { useMemo, useState } from "react";
import { Button, Field, Input, Select, Textarea } from "@/components/ui";
import { AUDIENCES, STATUSES, fromLocalInput, toLocalInput } from "@/lib/format";

export type ChannelOption = {
  id: string;
  name: string;
  audience: string;
  folders: { id: string; name: string }[];
};

export type PostValues = {
  channel_id: string;
  folder_id: string | null;
  title: string;
  caption: string | null;
  audience: string;
  status: string;
  published_at: string | null;
};

export function PostForm({
  action,
  channels,
  values,
  submitLabel,
}: {
  action: (formData: FormData) => Promise<void>;
  channels: ChannelOption[];
  values?: Partial<PostValues>;
  submitLabel: string;
}) {
  const [channelId, setChannelId] = useState(values?.channel_id ?? channels[0]?.id ?? "");
  const [audience, setAudience] = useState(values?.audience ?? "all");
  const [publishLocal, setPublishLocal] = useState(toLocalInput(values?.published_at));

  const channel = useMemo(() => channels.find((c) => c.id === channelId), [channels, channelId]);
  // A post can't be wider than its channel: lock the audience to the channel's.
  const lockedAudience = channel && channel.audience !== "all" ? channel.audience : null;
  const effectiveAudience = lockedAudience ?? audience;
  const publishIso = fromLocalInput(publishLocal)?.toISOString() ?? "";

  if (channels.length === 0) {
    return <p className="text-sm text-gray-600">Create a channel first.</p>;
  }

  return (
    <form action={action} className="grid gap-4 md:grid-cols-2">
      <Field label="Channel">
        <Select name="channel_id" value={channelId} onChange={(e) => setChannelId(e.target.value)} required>
          {channels.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
              {c.audience !== "all" ? ` (${c.audience === "ads" ? "Ads only" : "Organic only"})` : ""}
            </option>
          ))}
        </Select>
      </Field>
      <Field label="Folder">
        <Select key={channelId} name="folder_id" defaultValue={values?.folder_id ?? ""}>
          <option value="">No folder</option>
          {channel?.folders.map((f) => (
            <option key={f.id} value={f.id}>
              {f.name}
            </option>
          ))}
        </Select>
      </Field>
      <div className="md:col-span-2">
        <Field label="Title">
          <Input name="title" required defaultValue={values?.title} />
        </Field>
      </div>
      <div className="md:col-span-2">
        <Field label="Caption" hint="Emojis and #hashtags are fine">
          <Textarea name="caption" rows={4} defaultValue={values?.caption ?? ""} />
        </Field>
      </div>
      <Field
        label="Who can see this post"
        hint={lockedAudience ? "Set by the channel's audience" : "Everyone, organic users only, or users from your ads only"}
      >
        <Select
          name="audience"
          value={effectiveAudience}
          onChange={(e) => setAudience(e.target.value)}
          disabled={!!lockedAudience}
        >
          {AUDIENCES.map((a) => (
            <option key={a.value} value={a.value}>
              {a.label}
            </option>
          ))}
        </Select>
        {lockedAudience && <input type="hidden" name="audience" value={lockedAudience} />}
      </Field>
      <Field label="Status">
        <Select name="status" defaultValue={values?.status ?? "draft"}>
          {STATUSES.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </Select>
      </Field>
      <Field label="Publish at (India time)" hint="Leave empty to publish immediately. A future time schedules the post.">
        <Input type="datetime-local" value={publishLocal} onChange={(e) => setPublishLocal(e.target.value)} />
        <input type="hidden" name="published_at" value={publishIso} />
      </Field>
      <div className="flex items-end md:col-span-2">
        <Button type="submit">{submitLabel}</Button>
      </div>
    </form>
  );
}
