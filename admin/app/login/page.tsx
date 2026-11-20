import { PasswordInput } from "@/components/password-input";
import { Button, Field, Input } from "@/components/ui";
import { inter, spaceGrotesk } from "@/app/fonts";
import { signIn } from "./actions";

const errors: Record<string, string> = {
  invalid: "Wrong email or password.",
  not_admin: "This account doesn't have admin access.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  return (
    <main
      className={`admin-theme ${inter.variable} ${spaceGrotesk.variable} flex min-h-screen items-center justify-center px-4 py-10`}
    >
      <div className="w-full max-w-sm">
        <div className="mb-7 text-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/site/logo.png" alt="" width={56} height={56} className="mx-auto mb-3 h-14 w-14 rounded-2xl" />
          <h1 className="text-2xl font-bold text-white">Flixvault Admin</h1>
          <p className="mt-1 text-sm text-gray-400">Sign in to manage content and users</p>
        </div>
        <form action={signIn} className="space-y-4 rounded-2xl border border-gray-200 bg-white p-6 shadow-xl">
          {error && (
            <p role="alert" className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
              {errors[error] ?? "Sign-in failed."}
            </p>
          )}
          <Field label="Email">
            <Input name="email" type="email" autoComplete="email" placeholder="you@example.com" required />
          </Field>
          <Field label="Password">
            <PasswordInput name="password" autoComplete="current-password" placeholder="Your password" required />
          </Field>
          <Button type="submit" className="w-full">
            Sign in
          </Button>
        </form>
        <p className="mt-6 text-center text-xs text-gray-500">For approved Flixvault administrators only.</p>
      </div>
    </main>
  );
}
