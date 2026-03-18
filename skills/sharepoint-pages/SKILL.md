---
name: sharepoint-pages
description: "Search and read SharePoint site pages and documents via the SharePoint REST API. Search across all SharePoint content with KQL, read modern site pages with full text extraction, list pages and document libraries, and browse folder contents. Activated when users ask to find or read SharePoint content, company policies, internal documentation, or org information. Requires Windows with Microsoft Teams running with CDP enabled."
compatibility: "Requires Windows with Microsoft Teams (new WebView2 version) and Windows PowerShell 5.1"
metadata:
  author: Azure Core Team
  version: "1.0.0"
---

# SharePoint Pages

Searches and reads SharePoint content programmatically via the SharePoint REST API. Authenticates by extracting the `SPOIDCRL` cookie from the Teams WebView2 browser via Chrome DevTools Protocol. No Graph API permissions, no app registrations, no Playwright required.

## Prerequisites

- **Windows-only** — uses Teams WebView2 CDP interface
- **Microsoft Teams** (new version, WebView2-based `MSTeams_8wekyb3d8bbwe`) must be running
- **CDP enabled** — User environment variable `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` must be set to `--remote-debugging-port=9222` and Teams restarted after setting it
- **Windows PowerShell 5.1** (`powershell`)

### One-Time Setup

If CDP is not already enabled, run:

```powershell
[Environment]::SetEnvironmentVariable("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9222", "User")
```

Then restart Teams. Verify CDP is active: `Invoke-RestMethod http://localhost:9222/json`

This is the same prerequisite as the [teams-chat](../teams-chat/SKILL.md) skill. If Teams CDP is already set up, no additional configuration is needed.

## Activation Triggers

- User asks to "search SharePoint for X" or "find a document about X"
- User asks about company policies, HR information, or internal documentation
- User asks to "read this SharePoint page" and provides a URL
- User asks about org charts, team structures, or internal resources
- User asks "what is the policy for X" (time off, parental leave, holidays, etc.)
- User mentions a SharePoint site or page by name
- User asks to list pages or documents on a SharePoint site

## Capabilities

1. **Search** — Full-text search across all SharePoint content with KQL support, file type filtering, site scoping, and pagination ([Search-SharePoint.ps1](./scripts/Search-SharePoint.ps1))
2. **Read Page** — Fetch a modern SharePoint site page by URL and extract readable text from canvas web parts including headings, paragraphs, accordions, quick links, and embedded content. Falls back to HTML stripping for classic pages. ([Read-SharePointPage.ps1](./scripts/Read-SharePointPage.ps1))
3. **Browse Sites** — List site pages, document libraries, folder contents, and discover SharePoint sites by search ([Get-SharePointSites.ps1](./scripts/Get-SharePointSites.ps1))
4. **Download Files** — Download documents (DOCX, PPTX, PDF, etc.) from SharePoint document libraries to a local path ([Download-SharePointFile.ps1](./scripts/Download-SharePointFile.ps1))
5. **Read Lists** — List available SharePoint lists on a site, and read list items with field selection and OData filtering ([Get-SharePointList.ps1](./scripts/Get-SharePointList.ps1))

All scripts use [SharePoint-Helper.ps1](./scripts/SharePoint-Helper.ps1) which connects to CDP via `System.Net.WebSockets.ClientWebSocket`, extracts the `SPOIDCRL` httpOnly cookie via `Network.getAllCookies`, then calls the SharePoint REST API.

---

## Technical Details

### How It Works

1. PowerShell calls `http://localhost:9222/json` to discover CDP targets
2. Connects via `ClientWebSocket` to the Teams page's WebSocket debug URL
3. Sends `Network.getAllCookies` CDP command to read all cookies including httpOnly
4. Extracts the `SPOIDCRL` cookie for `microsoft.sharepoint.com`
5. Calls the SharePoint REST API via `Invoke-RestMethod` with the cookie in a `WebRequestSession`

Teams' embedded browser authenticates to SharePoint automatically (for file tabs, wiki pages, etc.), leaving a valid `SPOIDCRL` cookie that this skill reuses.

### Page Content Structure

Modern SharePoint pages store content as a JSON array of web parts in the `CanvasContent1` field. Each web part has:

- `controlType=4`: Rich text blocks with content in `innerHTML`
- `controlType=3`: Structured web parts (accordions, quick links, images) with content in `webPartData.serverProcessedContent.htmlStrings` and `searchablePlainTexts`

The `GetByUrl` SitePages API returns clean JSON that PowerShell's `ConvertFrom-Json` handles natively. A regex fallback handles edge cases where JSON parsing fails.

---

## Workflow

### Step 1: Determine Intent

- If user wants to **find content** → Step 2 (Search)
- If user wants to **read a specific page** by URL → Step 3 (Read Page)
- If user wants to **browse a site** → Step 4 (Browse Site)
- If user wants to **download a file** → Step 5 (Download File)
- If user wants to **read list data** → Step 6 (Read List)
- If user wants to **find a SharePoint site** → Step 7 (Discover Sites)

### Step 2: Search SharePoint

```powershell
# From a repo with the skill installed:
powershell -NoProfile -File .\.github\skills\sharepoint-pages\scripts\Search-SharePoint.ps1 -Query "<SEARCH TERMS>"

# From the user-level skill install:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Search-SharePoint.ps1 -Query "<SEARCH TERMS>"
```

**Parameters:**
- `-Query <string>` — search query (required). Supports KQL syntax.
- `-Site <string>` — restrict search to a specific site URL
- `-FileType <string>` — filter by file extension (e.g., `pptx`, `docx`, `pdf`, `aspx`)
- `-MaxResults <int>` — limit results (default 10)
- `-StartRow <int>` — starting row for pagination (default 0)

**Search tips:**
- Use KQL operators for precision: `"exact phrase"`, `body:"keyword"`, `author:"name"`
- Use `-Site` to narrow results to a known site
- Use `-FileType aspx` to find only site pages, `-FileType pptx` for presentations
- Use `-StartRow` to page through results (e.g., `-StartRow 10` for the second page of 10)

### Step 3: Read a SharePoint Page

```powershell
# By full URL:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Read-SharePointPage.ps1 -Url "<FULL PAGE URL>"

# By site and page path:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Read-SharePointPage.ps1 -SiteUrl "<SITE URL>" -PagePath "SitePages/MyPage.aspx"
```

**Parameters:**
- `-Url <string>` — full SharePoint page URL
- `-SiteUrl <string>` — site URL (used with `-PagePath`)
- `-PagePath <string>` — relative page path within the site

### Step 4: Browse a SharePoint Site

```powershell
# List recent pages:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointSites.ps1 -SiteUrl "<SITE URL>"

# List document libraries:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointSites.ps1 -SiteUrl "<SITE URL>" -Action libraries

# List files in a folder:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointSites.ps1 -SiteUrl "<SITE URL>" -Action files -FolderPath "/sites/MySite/Shared Documents/MyFolder"
```

**Parameters:**
- `-SiteUrl <string>` — SharePoint site URL (required except for `sites` action)
- `-Action <string>` — what to list: `pages` (default), `libraries`, `files`, `sites`
- `-FolderPath <string>` — server-relative folder path (required for `files` action)
- `-MaxResults <int>` — limit results (default 20)

### Step 5: Download a File

```powershell
# By full URL:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Download-SharePointFile.ps1 -Url "<FILE URL>"

# Save to a specific directory:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Download-SharePointFile.ps1 -Url "<FILE URL>" -OutDir "C:\temp"
```

**Parameters:**
- `-Url <string>` — full URL to the SharePoint file
- `-SiteUrl <string>` — site URL (used with `-FolderPath` and `-FileName`)
- `-FolderPath <string>` — server-relative folder path
- `-FileName <string>` — name of the file to download
- `-OutDir <string>` — local directory to save to (default: current directory)
- `-OutFile <string>` — exact local path for the saved file

**Download tips:**
- After downloading a DOCX, use the word-documents skill to read its content
- After downloading a PPTX, use the word-documents skill or open in PowerPoint to review content

### Step 6: Read a SharePoint List

```powershell
# List all lists on a site:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointList.ps1 -SiteUrl "<SITE URL>" -ListAll

# Read items from a specific list:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointList.ps1 -SiteUrl "<SITE URL>" -ListName "<LIST NAME>"

# Read with filters:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointList.ps1 -SiteUrl "<SITE URL>" -ListName "<LIST NAME>" -Filter "Status eq 'Active'" -OrderBy "Modified desc"
```

**Parameters:**
- `-SiteUrl <string>` — SharePoint site URL (required)
- `-ListName <string>` — name of the list to read
- `-ListAll` (switch) — list all available lists on the site
- `-Fields <string>` — comma-separated field names to retrieve
- `-Filter <string>` — OData filter expression
- `-MaxResults <int>` — limit results (default 25)
- `-OrderBy <string>` — sort expression (e.g., `Modified desc`)

### Step 7: Discover SharePoint Sites

```powershell
# Search for sites by keyword:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointSites.ps1 -Action sites -SiteUrl "Azure Core"

# List all discoverable sites:
powershell -NoProfile -File ~\.copilot\skills\sharepoint-pages\scripts\Get-SharePointSites.ps1 -Action sites
```

When using `-Action sites`, the `-SiteUrl` parameter is repurposed as a search term to find sites by name.

---

## Rules

1. **DO NOT** modify, upload, or delete any SharePoint content. This skill is **read-only** (download saves to local disk only).
2. **MUST** search first to locate content before attempting to read specific pages.
3. **MUST** check CDP availability before reporting errors — suggest setup steps if connection fails.
4. **MAY** combine with other skills (e.g., download a DOCX then read with word-documents skill).
5. For search results with many matches, present the top results and offer to refine or paginate.
6. When the user asks about a policy or topic, **search first** to find the relevant page, then **read** it.
7. **DO NOT** expose raw API URLs or site paths to the user — use them internally for lookups.
8. When reading pages with many sections, summarize key points and offer to show specific sections.
9. When the user doesn't know the site URL, use `-Action sites` to discover sites first.
10. When downloading files, prefer saving to a temp directory unless the user specifies a path.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Unable to connect to localhost:9222 | CDP not enabled or Teams not running | Set env var and restart Teams |
| Teams page not found | CDP active but no Teams page detected | Ensure Teams is fully loaded |
| SPOIDCRL cookie not found | Teams hasn't accessed SharePoint | Open any SharePoint page in Teams, then retry |
| API 401/403 | Cookie expired or no access to site | Restart Teams to refresh cookies, or verify site permissions |
| Page not found (404) | Wrong URL or page deleted | Verify the URL, try searching instead |
| Query throttled | Search query too broad | Add filters: `-Site`, `-FileType`, or more specific terms |

## Limitations

- **Read-only**: Cannot create, edit, or delete SharePoint content (download is the only write operation, to local disk)
- **Classic pages**: Falls back to HTML stripping which may produce noisier output than modern page extraction
- **Cookie lifetime**: SPOIDCRL refreshes automatically while Teams runs, but expires if Teams is closed
- **No OneDrive**: Personal OneDrive (`microsoft-my.sharepoint.com`) requires separate authentication not covered by this skill
- **Search is server-side**: Uses SharePoint's enterprise search index, so recently published content may take a few minutes to appear
