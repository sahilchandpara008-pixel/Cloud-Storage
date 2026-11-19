import Link from "next/link";
import { PageHeader } from "@/components/ui";
import { requireOwner } from "@/lib/auth";

// Manual approval of organic users for Ads-only content was removed: only
// verified Meta-ad installs (and the ads APK) get ads content.
export default async function ApprovalsPage() {
  await requireOwner();
  return (
    <>
      <PageHeader title="Approvals" subtitle="Manual approval for ads content is switched off." />
      <div className="max-w-2xl rounded-xl border border-gray-200 bg-white p-5 text-sm leading-6 text-gray-700 shadow-sm">
        <p className="font-semibold text-gray-900">Ads-only content can no longer be approved by hand.</p>
        <p className="mt-2">
          Only people who installed Flixvault from your Meta ads (verified by Meta&apos;s own install tag) or from the
          ads APK see Ads-only content. Organic users, users from hand-made links, and new installs from Gujarat and
          Maharashtra always see organic content only. Organic users can still buy a plan for premium videos.
        </p>
        <p className="mt-3">
          See who gets ads content in{" "}
          <Link href="/users?filter=ads" className="font-medium text-brand-700 hover:underline">
            Users → Gets ads content
          </Link>
          .
        </p>
      </div>
    </>
  );
}
