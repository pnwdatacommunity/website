# Migration runbook: WordPress.com → GitHub Pages, oregonsql.org → oregondatacommunity.org

State on **2026-10-17**, checked against public DNS:

| | Nameservers | Records | Serves |
|---|---|---|---|
| `oregonsql.org` | **WordPress.com** (ns1–3.wordpress.com) | **MX 10 `sm10.internetmailserver.net`** · no SPF/TXT | WordPress.com site; **outreach@ email** |
| `oregondatacommunity.org` | **Bluehost** (ns1/ns2.bluehost.com) | A `66.81.203.198` · no `www` · no MX | 403. Never connected to the site. |

**Order matters.** `oregondatacommunity.org` has no email, so it's safe to change at any time. `oregonsql.org`'s DNS zone carries the MX record for `outreach@oregonsql.org`, the published contact for Day of Data. **Don't touch `oregonsql.org` nameservers until after Day of Data (7 Nov).**

---

## Phase 0: this week, on WordPress.com (before 7 Nov)

The new site won't be live in time to carry Day of Data traffic, so patch the old one. See the copy in the chat (banner, meetings block, menu fixes).

- [ ] Day of Data banner at the top of Home, linking to Zeffy registration
- [ ] Delete "Next meeting: Jan 21, 2025"
- [ ] Menu: Contact/About point to `sqlserverbiblog8.wordpress.com`. Fix them or remove them
- [ ] Remove the theme demo block ("Acme Corp Design Summit…") and the social icons that link to wordpress.org
- [ ] Replace "annual SQL Saturday" with "PNW Day of Data"
- [ ] Meetup: the ODC Day of Data event shows **4 RSVPs**. Post an announcement to both Meetup groups now

## Phase 1: GitHub organization and repo (~30 min)

1. Create a **free organization**: github.com → *+* → *New organization* → name **`pnwdatacommunity`** (chosen to match the likely PNW Data Community brand; the org hosts the site whatever the final domain is).
   If the name is taken, pick another and run: `Select-String -Path hugo.toml,content\*\*.md,docs\*.md -Pattern pnwdatacommunity` to find every reference.
2. Invite the co-president as a second **Owner**, so the site survives either of you stepping down.
3. In PowerShell:

```powershell
winget install Git.Git GitHub.cli Hugo.Hugo.Extended
# new terminal so PATH refreshes
git config --global user.name  "Michael Wall"
git config --global user.email "<your GitHub email or noreply address>"
gh auth login                                   # GitHub.com → HTTPS → browser

Expand-Archive "$HOME\Downloads\odc-website.zip" "$HOME\source"   # creates ...\source\website
cd "$HOME\source\website"
hugo server                                     # look at http://localhost:1313 first
gh repo create pnwdatacommunity/website --public --source . --remote origin --push
```

4. Repo → **Settings → Pages → Source: GitHub Actions**. The setting applies immediately.
5. **Actions** tab → "Deploy site" → it should go green. The site is now live at
   `https://pnwdatacommunity.github.io/website/`. CSS paths work there because the workflow passes the Pages base URL.

## Phase 2: import the old content (~20 min, first real PR)

1. WordPress.com → **Tools → Export → Export all**. A zip is emailed to you or downloaded. Unzip it **outside** the repo.
2. Run the import on a branch:

```powershell
cd "$HOME\source\website"
git switch -c import/wordpress
.\scripts\Convert-WordPressExport.ps1 -XmlPath "$HOME\Downloads\<export>.xml" -WhatIf   # dry run
.\scripts\Convert-WordPressExport.ps1 -XmlPath "$HOME\Downloads\<export>.xml"
hugo server        # check /posts/ and a few old URLs like /2025/09/15/<slug>/
git add content static ; git commit -m "Import posts and images from WordPress.com"
git push -u origin import/wordpress ; gh pr create --fill
```

   The script downloads every image out of WordPress.com, so nothing breaks when the plan ends. Pages land in `import/pages/` (ignored by git). Copy anything worth keeping into `content/` by hand.
3. Merge the PR: `gh pr merge --squash --delete-branch`.
4. While you're in WordPress.com: **export the email subscriber list** if there is one, and import it into Brevo.

## Phase 3: point oregondatacommunity.org at GitHub (any time; no email at risk)

> **Hold until the name is decided.** If the rebrand to *PNW Data Community* goes ahead, do this phase with
> `pnwdatacommunity.org` instead (same records, same steps), and make `oregondatacommunity.org` a 301 redirect
> at Bluehost like `oregonsql.org` in Phase 4. GitHub Pages serves one custom domain per site; every other
> domain is a redirect. **Register `pnwdatacommunity.org` and `.com` now either way**, in the group's account.

1. **Verify the domain first** (it prevents domain takeover):
   GitHub org → **Settings → Pages → Add a domain** → `oregondatacommunity.org`. GitHub shows a TXT record named `_github-pages-challenge-pnwdatacommunity`. Add it at Bluehost (**Domains → oregondatacommunity.org → DNS**), then click *Verify*.
2. In the same Bluehost DNS zone:
   - **Delete** the `@` A record `66.81.203.198` (and any `@` AAAA).
   - **Add** these records:

| Type | Host | Value |
|---|---|---|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| AAAA | @ | 2606:50c0:8000::153 |
| AAAA | @ | 2606:50c0:8001::153 |
| AAAA | @ | 2606:50c0:8002::153 |
| AAAA | @ | 2606:50c0:8003::153 |
| CNAME | www | pnwdatacommunity.github.io |

3. Repo → **Settings → Pages → Custom domain** → `oregondatacommunity.org` → Save. With an Actions deployment this setting is what counts; no `CNAME` file is needed.
4. Check it, then turn on **Enforce HTTPS** once the option appears. The certificate can take up to 24 hours.

```powershell
Resolve-DnsName oregondatacommunity.org -Type A -Server 8.8.8.8
Resolve-DnsName www.oregondatacommunity.org -Type CNAME -Server 8.8.8.8
(Invoke-WebRequest https://oregondatacommunity.org -UseBasicParsing).StatusCode   # 200
```

## Phase 4: after 8 Nov, make oregonsql.org a 301 to the new domain

Old post URLs keep the same path (`/yyyy/mm/dd/slug/`), so a path-preserving redirect sends every old link to the right page.

1. **Email first.** Ask whoever owns the SmarterMail account behind `outreach@` for the full set of records it needs (MX, plus SPF/DKIM if they offer them). Today there is **no SPF record**, which hurts deliverability. Add one while you're in there.
2. **Create the zone at Bluehost before switching anything.** Add `oregonsql.org` to the hosting account as an addon or parked domain, so Bluehost creates a DNS zone and a document root. In that zone:
   - recreate **MX 10 `sm10.internetmailserver.net`** (and anything else the mail owner gave you)
   - leave `@`/`www` pointing at Bluehost hosting
3. Put this `.htaccess` in that domain's document root. It's the same mod_rewrite style that worked on your blog's LiteSpeed host:

```apache
RewriteEngine On
RewriteCond %{HTTP_HOST} ^(www\.)?oregonsql\.org$ [NC]
RewriteRule ^(.*)$ https://oregondatacommunity.org/$1 [R=301,L]
```

4. At the **oregonsql.org registrar**, change the nameservers from `ns1-3.wordpress.com` to `ns1.bluehost.com` / `ns2.bluehost.com`. Wait for propagation, then run AutoSSL for `oregonsql.org` in Bluehost so `https://oregonsql.org/...` also redirects cleanly.
5. Test, with **email first**:

```powershell
Resolve-DnsName oregonsql.org -Type MX -Server 8.8.8.8          # sm10.internetmailserver.net
# send a test message to outreach@oregonsql.org and confirm it arrives
(Invoke-WebRequest https://oregonsql.org/2025/09/15/9-17-25-introduction-to-postgresql-for-the-data-professional/ -MaximumRedirection 0 -UseBasicParsing -ErrorAction SilentlyContinue).Headers.Location
```

6. **Only then** cancel the WordPress.com plan. Keep `oregonsql.org` registered indefinitely: the email, Meetup URLs and years of inbound links depend on it.

> **Unverified:** whether `oregonsql.org` is registered *at* WordPress.com or elsewhere. WordPress.com nameservers point to WordPress.com, but that isn't proof of where it's registered. If it is registered at WordPress.com, the nameserver change is under WordPress.com **Domains → oregonsql.org → Name servers**, and the registration must keep renewing after the hosting plan ends.

Also update the Day of Data listing (dayofdata.org) and both Meetup groups to link to `https://oregondatacommunity.org`.

## Phase 5: make it a tool, not a brochure

| Cadence | Do | Where |
|---|---|---|
| Same day a meeting goes on Meetup | Add it to `meetings.yaml` (one PR) | Home + /meetings |
| After each meeting | Short write-up post: speaker, slides link, 3 takeaways | /posts. These are also MVP `OrganizerUserGroup` evidence |
| Day of Data CFP opens (spring) | Fill `current` in `dayofdata.yaml`, link Sessionize on /speak | Banner starts 120 days out |
| After Day of Data | Move `current` → `past`, post a recap with attendance numbers | /day-of-data |
| Quarterly | Review `community.yaml`: add active groups, drop dead ones | /community |

**Later, if it's worth it:** a scheduled GitHub Action that pulls upcoming events from both Meetup groups into `meetings.yaml`. The Meetup API needs OAuth, so treat that as a phase-2 project, not a launch blocker.
