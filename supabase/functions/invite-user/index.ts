// iD Fresh Artwork Library — send sign-in invites (admins only).
// Uses the project's service role key, which Supabase provides to functions automatically.
import { createClient } from "jsr:@supabase/supabase-js@2";

const COMPANY = "@idfreshfood.com";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
    if (!service) return json({ error: "Service key isn't available to the function." }, 500);
    const admin = createClient(url, service, { auth: { persistSession: false } });

    // 1. Caller must be a signed-in admin on the team list.
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await admin.auth.getUser(token);
    const callerEmail = (user?.email ?? "").toLowerCase();
    if (!user || !callerEmail.endsWith(COMPANY)) return json({ error: "Sign in with your iD Fresh email." }, 401);
    const { data: me } = await admin.from("team").select("role").eq("email", callerEmail).maybeSingle();
    if (me?.role !== "admin") return json({ error: "Only admins can send invites." }, 403);

    // 2. Validate the request.
    const body = await req.json().catch(() => ({}));
    const emails: string[] = Array.isArray(body.emails) ? body.emails.map((e: unknown) => String(e).trim().toLowerCase()) : [];
    if (!emails.length || emails.length > 100) return json({ error: "Send between 1 and 100 emails." }, 400);
    let redirectTo: string | undefined;
    try { const u = new URL(String(body.redirectTo ?? "")); if (u.protocol === "https:" || u.hostname === "localhost") redirectTo = u.origin + u.pathname; } catch { /* use Site URL */ }

    // 3. Invite each person who is on the team list.
    const results = [];
    for (const email of emails) {
      if (!email.endsWith(COMPANY)) { results.push({ email, ok: false, error: "not an @idfreshfood.com address" }); continue; }
      const { data: person } = await admin.from("team").select("full_name, role, department").eq("email", email).maybeSingle();
      if (!person) { results.push({ email, ok: false, error: "not on the team list" }); continue; }
      const meta = { full_name: person.full_name, role: person.role, department: person.department ?? "" };
      let { error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo, data: meta });
      if (error && /already been registered|already registered|exists/i.test(error.message)) {
        // Already has an account: send a fresh sign-in link instead.
        const r = await createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? service).auth.signInWithOtp({ email, options: { emailRedirectTo: redirectTo, shouldCreateUser: false } });
        error = r.error;
      }
      if (error) { results.push({ email, ok: false, error: error.message }); continue; }
      await admin.from("team").update({ invited_at: new Date().toISOString(), invited_by: callerEmail }).eq("email", email);
      results.push({ email, ok: true });
    }
    return json({ results });
  } catch (e) {
    console.error(e);
    return json({ error: "Invites didn't finish. Try again." }, 500);
  }
});
