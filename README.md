# iD Fresh Artwork Library

Artwork management for iD Fresh: requests, approvals, final-file handover, a print-ready Library, team access levels and built-in artwork checks.

**Checks:** UK English spelling (dictionary + AI), exact font sizes from the PDF, brand colours (HEX/RGB/CMYK), barcode (read from the bars, check digit verified), QR link and 300 DPI print resolution.

**Sign-in:** iD Fresh email + password, or a one-time email link. Sign-in is invite-only, and people are added on the Team page.

**Security:** access levels and the approval workflow are enforced by the database (row-level security and a workflow trigger), not just the app.

**Stack:** a single static page (`index.html`, vanilla JS), with a Supabase backend for the database, sign-in, file storage and edge functions. It can be hosted on GitHub Pages, cPanel or Netlify.

## Folder

| Path | What |
|---|---|
| `index.html`, `*.png`, `dict/` | The website. |
| `supabase/schema.sql`, `supabase/seed.sql` | Database, access levels, workflow rules and security policies. |
| `supabase/functions/` | `artwork-check` (AI proofread) and `invite-user` (team invites). |
| `supabase/email-templates/invite.html` | Invite email, worded for each access level. |

## Setup

See [SETUP.md](SETUP.md).

## Notes

- **Key in `index.html`:** the Supabase **publishable** key there is meant to be public. Access is protected by the database rules.
- **Never commit secrets:** the secret or service key, the Anthropic API key and any passwords stay out of this repo.

## Third-party code

- Barcode reader: [Quagga2](https://github.com/ericblade/quagga2), MIT licence, loaded from jsDelivr.
- `dict/en_GB.txt`: UK English word list from [check-spelling/cspell-dicts](https://github.com/check-spelling/cspell-dicts), LGPL-3.0.
