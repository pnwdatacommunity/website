# Oregon Data Community website

Source for **https://oregondatacommunity.org**. It's a [Hugo](https://gohugo.io) static site, built and published to GitHub Pages by GitHub Actions on every push to `main` and once a day.

## The 90% case: edit data, not pages

| To change… | Edit | Notes |
|---|---|---|
| Upcoming / past meetings | `data/meetings.yaml` | Past dates disappear from "upcoming" on the next daily build. |
| Day of Data (date, venue, registration, sponsors) | `data/dayofdata.yaml` | Drives the site-wide banner (120 days out → day after). |
| Partner groups, regional events | `data/community.yaml` | Only add entries with a verified link. |
| Organizers | `data/organizers.yaml` | |
| Page text | `content/<section>/_index.md` | Markdown. |
| News / meeting write-up | `hugo new posts/2026-11-18-my-title.md` | Remove `draft: true` to publish. |

Day of Data timing, past-meeting roll-off and the countdown all work from dates, so the site stays current without anyone touching it.

## Run it locally (Windows)

```powershell
winget install Git.Git GitHub.cli Hugo.Hugo.Extended
cd $HOME\source\website
hugo server        # http://localhost:1313, reloads as you save
```

## GitHub workflow (practice it on real changes)

```powershell
git switch -c meeting/2026-12                 # 1. branch per change
code data\meetings.yaml                       # 2. edit
hugo server                                   # 3. check it locally
git add data\meetings.yaml
git commit -m "Add December meeting"          # 4. small, descriptive commits
git push -u origin meeting/2026-12            # 5. publish the branch
gh pr create --fill                           # 6. open a pull request
gh pr merge --squash --delete-branch          # 7. merge → Actions deploys in ~1 min
git switch main; git pull                     # 8. back to a clean main
```

Then try **Issues** (talk proposals arrive via `.github/ISSUE_TEMPLATE`), **Actions** (watch the deploy, re-run it from *Run workflow*), **branch protection** on `main` (require a PR) and **CODEOWNERS** once a second organizer joins.

## Layout

```
data/          ← meetings, Day of Data, community, organizers (YAML)
content/       ← page text (Markdown) and posts
layouts/       ← HTML templates (Hugo)
static/        ← CSS, images, favicon (served as-is)
scripts/       ← Convert-WordPressExport.ps1 (one-time import from WordPress.com)
docs/RUNBOOK.md← migration, DNS and the oregonsql.org redirect
.github/       ← deploy workflow and issue templates
```

## Rules

- **Never commit the WordPress export XML.** It contains subscriber and commenter email addresses. `.gitignore` blocks `*.xml`.
- Don't describe sponsorships or donations as tax-deductible until ODC's 501(c)(3) status has been confirmed.
