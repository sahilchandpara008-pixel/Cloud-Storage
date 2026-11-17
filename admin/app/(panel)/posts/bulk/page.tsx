import { redirect } from "next/navigation";

// Bulk upload now lives on the upload page as its own tab.
export default async function BulkUploadPage({ searchParams }: { searchParams: Promise<{ channel?: string }> }) {
  const { channel } = await searchParams;
  redirect(channel ? `/posts/new?mode=bulk&channel=${encodeURIComponent(channel)}` : "/posts/new?mode=bulk");
}
