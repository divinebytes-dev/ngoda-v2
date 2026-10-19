// Run locally after user_role, operational_country, supported_language seeds.
// deno run --allow-env --allow-net seed_super_admin.ts
// Required: SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL), SUPABASE_SERVICE_ROLE_KEY.
// SEED_ADMIN_PASSWORD is required only when creating a new Auth account.
// Auth and public DB writes are separate operations; rerun to resume after failure.

//
// deno run --allow-env --allow-net supabase/scripts/seed_super_admin.ts
//
import { createClient, type User } from "npm:@supabase/supabase-js@2";

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("Missing environment variable: " + name);
  return value;
}

const url = Deno.env.get("SUPABASE_URL") ?? required("NEXT_PUBLIC_SUPABASE_URL");
const client = createClient(url, required("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false, autoRefreshToken: false },
});
const email = "divinebytes.dev@gmail.com";

async function seed() {
  const { data: role, error: roleError } = await client.from("user_role")
    .select("id,name").eq("name", "admin").single();
  if (roleError) throw new Error("Seed admin role first: " + roleError.message);
  const { data: country, error: countryError } = await client.from("operational_country")
    .select("country_code,is_active").eq("country_code", "zw").single();
  if (countryError || !country.is_active) throw new Error("Active Zimbabwe country is required.");
  const { error: languageError } = await client.from("supported_language")
    .select("code").eq("code", "en").eq("is_active", true).single();
  if (languageError) throw new Error("Seed active English language first.");

  let authUser: User | undefined;
  for (let page = 1; ; page++) {
    const { data, error } = await client.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error("Auth lookup failed: " + error.message);
    authUser = data.users.find(u => u.email?.toLowerCase() === email);
    if (authUser || data.users.length < 1000) break;
  }

  const { data: profiles, error: lookupError } = await client.from("users")
    .select("id,email,wallet_address,wallet_index,referral_code").eq("email", email);
  if (lookupError) throw new Error("Profile lookup failed: " + lookupError.message);
  if ((profiles?.length ?? 0) > 1) throw new Error("Ambiguous admin profile.");
  const profile = profiles?.[0];
  if (profile && (!authUser || profile.id !== authUser.id)) {
    throw new Error("Admin profile and Auth identity do not match; resolve before seeding.");
  }

  if (!authUser) {
    // Check supplied bootstrap values before creating Auth to avoid known conflicts.
    const { data: conflicts, error } = await client.from("users").select("id")
      .or("wallet_address.eq.0x00,wallet_index.eq.0,referral_code.eq.ngoda").limit(1);
    if (error) throw new Error("Bootstrap uniqueness check failed: " + error.message);
    if (conflicts?.length) throw new Error("Bootstrap wallet address/index/referral code is already used.");
    const { data, error: createError } = await client.auth.admin.createUser({
      email, password: required("SEED_ADMIN_PASSWORD"), email_confirm: true,
      app_metadata: { role: "admin", country_code: "zw", wallet_index: 0 },
    });
    if (createError || !data.user) throw new Error("Auth creation failed: " + (createError?.message ?? "No user returned"));
    authUser = data.user;
  }

  // An auth.users trigger may have created a public profile during Auth creation.
  const { data: current, error: currentError } = await client.from("users")
    .select("id,email,wallet_address,wallet_index,referral_code")
    .eq("id", authUser.id).maybeSingle();
  if (currentError) throw new Error("Profile refresh failed: " + currentError.message);
  if (current?.email && current.email.toLowerCase() !== email) {
    throw new Error("Auth ID belongs to a different public-profile email.");
  }
  if (current) {
    const { error } = await client.from("users").update({
      email, status: "active", country_code: "zw", role_id: role.id,
      updated_at: new Date().toISOString(),
    }).eq("id", authUser.id);
    if (error) throw new Error("Admin profile update failed: " + error.message);
  } else {
    const { error } = await client.from("users").insert({
      id: authUser.id, email, status: "active", country_code: "zw",
      role_id: role.id, wallet_address: "0x00", wallet_index: 0, referral_code: "ngoda",
    });
    if (error) throw new Error("Admin profile creation failed; rerun after resolving: " + error.message);
  }

  const { data: saved, error: savedError } = await client.from("users")
    .select("wallet_index").eq("id", authUser.id).single();
  if (savedError) throw new Error("Saved profile lookup failed: " + savedError.message);
  const { error: metadataError } = await client.auth.admin.updateUserById(authUser.id, {
    app_metadata: {
      ...authUser.app_metadata,
      role: "admin", country_code: "zw", wallet_index: saved.wallet_index,
    },
  });
  if (metadataError) throw new Error("Metadata update failed; rerun to repair: " + metadataError.message);
  console.log("Super admin seeded successfully: " + email);
}
await seed();
