export type AppUser = {
  id: string;
  email: string | null;
  display_name: string;
  is_guest: boolean;
  source: "ads" | "organic";
  campaign: string | null;
  plan_name: string | null;
  plan_ends_at: string | null;
  ads_access_status: "none" | "pending" | "approved" | "rejected";
  created_at: string;
  purchases?: number;
  spent_paise?: number;
  last_purchase_at?: string | null;
  total_count?: number;
};
