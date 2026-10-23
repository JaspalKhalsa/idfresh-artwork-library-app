# iD Fresh Artwork Library: setup guide

The setup takes about 30–40 minutes. You only do it once.

## What's in this folder

| File | What it is |
|---|---|
| `index.html`, `logo-white.png`, `logo-green.png`, `icon.png`, `dict/` | The web app. Upload all of these to your host. The `dict` folder holds the UK spelling list. |
| `supabase/schema.sql` | Creates the tables, access levels, security rules, file storage and live updates. It also makes you (jaspal@idfreshfood.com) the first Admin. |
| `supabase/seed.sql` | Adds the 9 current projects from ManageArtworks. |
| `supabase/functions/artwork-check/` | The AI part of the artwork checks (UK spelling proofread and font-size estimate). |
| `supabase/functions/invite-user/` | Sends sign-in invites from the Team page. Only Admins can use it. |
| `supabase/email-templates/invite.html` | The invite email, with different wording for each access level. |
| `supabase/config.toml` | Settings for the two functions. |

## Step 0: Rotate the secret key (do this first)

The secret key was pasted into a chat, so treat it as exposed.

Go to Supabase → **Project Settings → API Keys**, revoke the old secret key, then create a new one. The app never uses the secret key. Keep it out of any web page.

## Step 1: Database (5 min)

1. Go to Supabase → **SQL Editor → New query**.
2. Paste in all of `supabase/schema.sql`, then click **Run**.
3. Open a new query, paste in `supabase/seed.sql`, then click **Run**.

If you ran an older `schema.sql` before, just run the new one again. It's safe to re-run.

## Step 2: Sign-in and invite emails (10 min)

1. Go to **Authentication → Sign In / Providers**:
   - Make sure **Email** is on.
   - Turn **off "Allow new users to sign up"**. Invites, magic links and password sign-in all still work. It just stops anyone registering a team email before the real person does.
   - Make sure **Confirm email** and **Secure email change** are on.
   - Turn off anonymous sign-ins and any other providers you don't use.
   - Set **minimum password length** to 10 and turn on **leaked password protection**, if your plan has it.
2. Go to **Authentication → URL Configuration**:
   - **Site URL**: your app's address (from Step 4), for example `https://artwork.idfreshfood.com`.
   - **Redirect URLs**: add the same exact address. Don't use wildcards like `https://*.netlify.app/**`, because sign-in links are sent to these addresses.
3. **Important:** Supabase's built-in email only sends a few emails an hour. That's not enough for a team. Go to **Authentication → Emails → SMTP Settings** and connect your company mail (Microsoft 365 SMTP) or a service like Resend or SendGrid.
4. Set up the invite email in **Authentication → Emails → Templates → Invite user**:
   - Subject: `You're invited to the iD Fresh Artwork Library`
   - Body: paste in all of `supabase/email-templates/invite.html`.

   The email picks its wording from each person's access level.

**Sign-in is invite-only.** Only people on the Team list with an `@idfreshfood.com` email can sign in. The database enforces this.

## Step 3: Functions: AI check and invites (10 min)

The AI check needs an Anthropic API key from console.anthropic.com. API usage is billed per check.

Run these commands in a terminal on a computer with Node installed:

```bash
npm install -g supabase
supabase login
cd idfresh-artwork-library
supabase link --project-ref fwtujjspadphjilydibp
supabase secrets set ANTHROPIC_API_KEY=your-anthropic-key
supabase functions deploy artwork-check --no-verify-jwt
supabase functions deploy invite-user --no-verify-jwt
```

Both functions check the caller's sign-in themselves, so `--no-verify-jwt` is safe. The invite function also checks the caller is an Admin.

The AI check uses `claude-sonnet-5-5` by default. To change the model, run `supabase secrets set ANTHROPIC_MODEL=claude-opus-5-5`.

## Step 4: Put the app online (5 min)

Pick one:

- **GitHub Pages** (free, straight from your repo):
  1. On GitHub, go to **Settings → Pages**.
  2. Under **Source**, choose **Deploy from a branch**, then **main** and **/ (root)**, and save.
  3. After a minute the app is live at `https://jaspalkhalsa.github.io/idfresh-artwork-library/`.

  Add that exact address as the Site URL and Redirect URL in Step 2. Every `git push` updates the site.

  Pages is free for public repos. A private repo needs a paid GitHub plan.
- **Your cPanel domain:** upload the website zip to a subdomain folder and run AutoSSL.
- **Netlify Drop:** go to app.netlify.com/drop and drag in the whole app (`index.html`, the 3 PNGs and the `dict` folder). You get a link straight away.
- **Vercel or your IT team's hosting:** it's a static site, with no build step.

To use a company address like `artwork.idfreshfood.com`, ask IT to point the domain to the host. Then update the Site URL from Step 2.

## Step 5: First sign-in and invite the team

1. Create your login in Supabase:
   - Go to **Authentication → Users → Add user → Create new user**.
   - Email: `jaspal@idfreshfood.com`
   - Password: your starter password. Don't write it in this repo or any shared file.
   - Tick **Auto Confirm User**, then click **Create user**.

   The starter password is stored only in Supabase, never in the app's code.
2. **Straight away**, open the app and sign in with that email and starter password. The app makes you choose your own password before you can do anything else (at least 10 characters). You're the first Admin.

   You can change your password later from **Password** in the top bar, or use **Forgot password?** on the sign-in page. Anyone can also choose **Email me a link instead** to sign in without a password.
3. Go to **Team** in the top menu and add people. You can:
   - Add them one at a time.
   - Paste a list into **Add a list**, one per line: `Name, email, department, level`. You can copy straight from Excel.
4. Click **Send invite**, or **Invite everyone not yet invited**. Each person gets the invite email written for their level.
5. Open any project, click **Check settings** and add the brand colours as a name plus hex code, one per line. iD Fresh Teal `#037D70` is already there.
6. Re-upload the artwork for the imported projects. ManageArtworks files weren't copied across, only their names.

## Access levels

| Level | For | Can do |
|---|---|---|
| **Admin** | Creative and brand leads | Everything, plus the Team page, invites and check settings |
| **Requester** | Marketing | Start requests, write briefs, add notes, nudge people, upload reference files |
| **Designer** | Creative team and agencies | Upload artwork, run checks, hand over final files, start requests |
| **Approver** | Quality, Legal, Manufacturing | Run checks, approve or request changes with a reason |
| **Viewer** | Sales, printers, leadership | View projects, download from the Library, share on WhatsApp |

Each person's name comes from their email on the Team list, so nobody can act or approve as someone else. To change someone's level, use the dropdown on the Team page.

**The database enforces the workflow, not just the app.** Even someone using developer tools can't:
- approve as another person;
- skip approval to Final files or Live;
- change the approver list (admins only);
- log notes or activity in someone else's name.

**Removing someone:** remove them on the Team page, **and** delete their user in Supabase → Authentication → Users.

**Unique names:** don't give two team members the exact same full name, because approvals are recorded by name.

## Good to know

- **File size:** files can be up to 50 MB. For bigger .ai files, upload a packaged PDF or a zip.
- **Live text:** for exact font sizes and the dictionary spelling check, upload a PDF with live (not outlined) text.
- **AI is a first pass:** treat the spelling and font results as estimates. Approvers still own the final check. Barcode check digits are calculated exactly, but scan the printer's proof too.
- **Same-time edits:** if two people approve at the same moment, both approvals are kept, so the pack still moves on to final files.
- **Reporting:** all data lives in your Supabase project. You can query `public.projects` and `public.team` directly. The `stage` and `product` columns are filled in automatically.
