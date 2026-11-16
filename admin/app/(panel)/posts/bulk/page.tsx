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
        subtitle="Upload many videos or images into one channel at once. Each file becomes its own post, saved on Bunny exactly like a single upload -- same audience, premium and approval rules."
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
