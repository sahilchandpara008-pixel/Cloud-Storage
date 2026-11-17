import { BulkUploader } from "@/components/bulk-uploader";
import { Card, PageHeader } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { loadChannelOptions } from "@/lib/channels";

export default async function BulkUploadPage() {
  const { supabase } = await requireAdmin();
  const channels = await loadChannelOptions(supabase);

  return (
    <>
      <PageHeader
        title="Bulk upload"
        subtitle="Upload many videos or images into a channel at once. Each file becomes its own post, with its own optional preview and thumbnail. Videos and previews are saved on Bunny, with the same audience, premium and approval rules as any post."
      />
      <Card>
        {channels.length === 0 ? (
          <p className="text-sm text-gray-600">Create a channel first.</p>
        ) : (
          <BulkUploader channels={channels} />
        )}
      </Card>
    </>
  );
}
