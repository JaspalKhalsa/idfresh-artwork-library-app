// iD Fresh Artwork Library — AI artwork check
// Proofreads packaging artwork: UK English spelling, font size, barcode digits, QR presence.
// Secrets needed (supabase secrets set ...): ANTHROPIC_API_KEY. Optional: ANTHROPIC_MODEL.
import { createClient } from "jsr:@supabase/supabase-js@2";

const COMPANY = "@idfreshfood.com";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Body = {
  image: string; product?: string; category?: string; packSize?: string; packType?: string;
  widthMm?: number | null; heightMm?: number | null; widthPx?: number; heightPx?: number;
  minFontPt?: number; notes?: string;
};

function buildPrompt(b: Body): string {
  const size = b.widthMm && b.widthPx
    ? `Artwork page size: ${Math.round(b.widthMm)} x ${Math.round(b.heightMm ?? 0)} mm. Image is ${b.widthPx} x ${b.heightPx} px, so 1 mm = ${(b.widthPx / b.widthMm).toFixed(2)} px.\n`
    : "Physical size unknown; estimate font sizes relative to the pack and say they are estimates.\n";
  return "You are a meticulous packaging artwork proofreader for iD Fresh, an Indian packaged-food company. Review the attached packaging artwork image.\n" +
    `Product: ${b.product ?? ""} (${b.category ?? ""}, ${b.packSize ?? ""}, ${b.packType ?? ""}).\n` + size +
    "House rules: spelling must be UK English (e.g. colour, flavour, fibre, litre, organised, savoury, yoghurt). Flag US spellings, typos, grammar errors, inconsistent units and repeated words. Do not flag brand names, Hindi or other non-English script, or ingredient proper nouns.\n" +
    `Minimum font size: ${b.minFontPt ?? 6} pt. List text that looks smaller than that (approximate point size).\n` +
    (b.notes ? `Extra brand notes: ${String(b.notes).slice(0, 2000)}\n` : "") +
    "Barcode: if a linear barcode is visible, read the human-readable digits under it exactly.\n" +
    "QR: say whether a QR code is visible and any call-to-action text next to it.\n" +
    'Reply with ONLY JSON in this shape: {"summary": string (2 sentences, plain UK English), "spelling": {"status": "pass"|"warn"|"fail", "items": [{"found": string, "suggest": string, "note": string}]}, "fonts": {"status": "pass"|"warn"|"fail", "items": [{"text": string, "estSizePt": number, "note": string}]}, "barcodeDigits": string|null, "barcodeType": string|null, "qrVisible": boolean, "qrNote": string|null, "other": [string]}. Keep each list to the 12 most important items.';
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    // Only signed-in iD Fresh people can use this.
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, anon);
    const { data: { user } } = await sb.auth.getUser(token);
    if (!user || !(user.email ?? "").toLowerCase().endsWith(COMPANY)) {
      return json({ error: "Sign in with your iD Fresh email to run the check." }, 401);
    }
    // Only current team members who can run checks (not viewers, not removed people).
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
    if (service) {
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, service, { auth: { persistSession: false } });
      const { data: member } = await admin.from("team").select("role").eq("email", (user.email ?? "").toLowerCase()).maybeSingle();
      if (!member || !["admin", "designer", "approver"].includes(member.role)) {
        return json({ error: "Your access level can't run artwork checks." }, 403);
      }
    }

    const body = (await req.json()) as Body;
    if (!body?.image || typeof body.image !== "string") return json({ error: "No artwork image was sent." }, 400);
    if (body.image.length > 7_000_000) return json({ error: "Artwork image is too large to check." }, 413);

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "AI key isn't set up yet. Ask the admin to add ANTHROPIC_API_KEY." }, 500);

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5",
        max_tokens: 2500,
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: "image/jpeg", data: body.image } },
            { type: "text", text: buildPrompt(body) },
          ],
        }],
      }),
    });
    if (!r.ok) {
      const detail = await r.text();
      console.error("Anthropic error", r.status, detail);
      return json({ error: r.status === 429 ? "AI is busy — try again in a minute." : `AI service error (${r.status}).` }, 502);
    }
    const out = await r.json();
    const text = (out.content ?? []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
    const m = text.match(/\{[\s\S]*\}/);
    if (!m) return json({ error: "The AI reply couldn't be read. Try again." }, 502);
    return json(JSON.parse(m[0]));
  } catch (e) {
    console.error(e);
    return json({ error: "The check didn't finish. Try again." }, 500);
  }
});
