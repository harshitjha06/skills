---
name: onenote-pages
description: "Access OneNote pages via COM automation. Search by title/keyword, fetch full page content, list notebooks/sections, and create new pages and sections. Activated when users ask to read, search, create, or list OneNote content. Requires Windows with OneNote desktop app running."
compatibility: "Requires Windows with OneNote desktop app (Office 16/M365) and Windows PowerShell 5.1"
metadata:
  author: Azure Core Team
  version: "1.0.0"
---

# OneNote Pages

Reads and creates OneNote pages programmatically via the OneNote COM API (`OneNote.Application`). No Graph API or cloud permissions required — talks directly to the locally running OneNote desktop app.

## Prerequisites

- **Windows-only** — uses OneNote COM automation (`OneNote.Application`) and the Windows OneNote desktop app
- **OneNote desktop app for Windows** (Office 16 / Microsoft 365) must be installed and running
- Notebooks must be synced (open at least once in the app)
- **Windows PowerShell 5.1** (`powershell`) with `-STA` support must be available in `PATH` (PowerShell 7 / `pwsh` is not supported — COM automation via `New-Object -ComObject` requires Windows PowerShell)

## Activation Triggers

- User asks to "read my OneNote page about X"
- User asks to "find a OneNote page" or "search OneNote for X"
- User asks to "list my OneNote notebooks" or "show my OneNote sections"
- User provides a OneNote page title or keyword to look up
- User asks to analyze, summarize, or review content from OneNote
- User asks to "create a OneNote page" or "make a new page in OneNote"
- User asks to "write to OneNote" or "save this to OneNote"
- User asks to "add a page to my notebook"

## Capabilities

1. **Search** — Find pages by title or content keyword across all notebooks ([Search-OneNotePage.ps1](./scripts/Search-OneNotePage.ps1))
2. **Read** — Fetch full page content (text, structure, links) ([Read-OneNotePage.ps1](./scripts/Read-OneNotePage.ps1))
3. **List** — Browse notebook/section/page hierarchy ([Get-OneNoteHierarchy.ps1](./scripts/Get-OneNoteHierarchy.ps1))
4. **Create Page** — Create a new page with markdown content in a specified section ([New-OneNotePage.ps1](./scripts/New-OneNotePage.ps1))
5. **Create Section** — Create a new section in a notebook ([New-OneNoteSection.ps1](./scripts/New-OneNoteSection.ps1))

---

## Technical Details

### Critical: STA Threading

All scripts **MUST** be invoked with `powershell -STA -NoProfile -File <script>`. The OneNote COM object requires Single-Threaded Apartment mode. Without `-STA`, calls will hang or fail silently. PowerShell 7 (`pwsh`) does not support `-STA`.

### COM Object

```powershell
$oneNote = New-Object -ComObject OneNote.Application
```

### Key Methods

| Method | Purpose | Parameters |
|--------|---------|------------|
| `GetHierarchy` | List notebooks/sections/pages | `(startNode, scope, [ref]xml)` — `scope` is the `HierarchyScope` enum: 0=hsNotebooks, 1=hsSections, 2=hsPages, 3=hsSectionsRecursive, 4=hsPagesRecursive |
| `FindPages` | Search by keyword | `(startNode, searchTerm, [ref]xml)` — searches titles AND body text |
| `GetPageContent` | Read full page | `(pageId, [ref]xml)` — returns XML with all text content |
| `CreateNewPage` | Create a new page | `(sectionId, [ref]pageId)` — creates blank page, returns new page ID |
| `UpdatePageContent` | Set page content | `(pageXml)` — sets title, body, and other page-level objects via XML |
| `GetHyperlinkToObject` | Get desktop link | `(objectId, objectIdInPage, [ref]hyperlink)` — returns `onenote:` protocol deep link |
| `GetWebHyperlinkToObject` | Get web link | `(objectId, objectIdInPage, [ref]hyperlink)` — returns SharePoint/OneDrive web URL |

### Page Links

Search, Read, and Hierarchy scripts include `onenote:` desktop links and SharePoint web links for each page. Braces (`{`/`}`) in URLs are percent-encoded (`%7B`/`%7D`) so they render correctly as clickable markdown links in terminals and chat UIs.

### XML Namespace

All XML parsing requires the OneNote namespace:
```powershell
$ns = @{ one = "http://schemas.microsoft.com/office/onenote/2013/onenote" }
```

---

## Workflow

### Step 1: Determine Intent

- If user wants a **specific page** → go to Step 2 (Search)
- If user wants to **browse** → go to Step 4 (List Hierarchy)
- If user wants to **analyze/summarize** → Search first, then Read, then analyze
- If user wants to **create a page** → go to Step 5 (Create Page)
- If user wants to **create a section** → go to Step 6 (Create Section)

### Step 2: Search for Pages

Run `Search-OneNotePage.ps1` to find pages matching a keyword:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\onenote-pages\scripts\Search-OneNotePage.ps1 -SearchTerm "<KEYWORD>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\onenote-pages\scripts\Search-OneNotePage.ps1 -SearchTerm "<KEYWORD>"
```

Returns a `Format-List` of matching pages with Notebook, Section, Page name, PageID, DesktopLink (`onenote:` protocol), and WebLink (SharePoint/OneDrive URL).

**Parameters:**
- `-SearchTerm` (required) — keyword or phrase to search for (case-insensitive)
- `-TitleOnly` (switch) — only return pages whose *title* contains the search term (filters out body-only matches)
- `-MaxResults <int>` — limit the number of results returned (0 = unlimited, default)

**Search tips:**
- Use `-TitleOnly` when looking for a specific page by name to avoid noisy body-text matches
- Use distinctive keywords, not common words
- If too many results, refine with more specific terms or add `-MaxResults 10`
- The search is case-insensitive

### Step 3: Read Page Content

Once you have a `PageID` from search results, fetch the full content:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\onenote-pages\scripts\Read-OneNotePage.ps1 -PageID "<PAGE_ID>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\onenote-pages\scripts\Read-OneNotePage.ps1 -PageID "<PAGE_ID>"
```

**Note:** The script automatically converts `<a>` tags to `[text](url)` markdown links, strips remaining HTML tags, and decodes HTML entities. Images are extracted to `$env:TEMP\onenote-pages\` as image files (typically PNG/JPG/GIF; unknown formats use a `.bin` extension) and printed inline as `[IMAGE: <path>]`. File attachments are extracted with their original filenames as `[ATTACHMENT: <path>]`. Use the `view` tool on image or attachment paths to analyze their contents. Pass `-SkipImages` for faster text-only output (attachments are still extracted).

### Step 4: List Hierarchy (Browse)

To show the user their notebook structure:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\onenote-pages\scripts\Get-OneNoteHierarchy.ps1

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\onenote-pages\scripts\Get-OneNoteHierarchy.ps1
```

**Parameters:**
- `-IncludeLinks` (switch) — generate desktop and web links for each page. Off by default because it adds 2 COM calls per page, which is slow for large notebook collections.

### Step 5: Create Page

First, use `Get-OneNoteHierarchy.ps1` (Step 4) to find the target section ID. Then create the page:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\onenote-pages\scripts\New-OneNotePage.ps1 -SectionId "<SECTION_ID>" -Title "<PAGE_TITLE>" -Content "<MARKDOWN>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\onenote-pages\scripts\New-OneNotePage.ps1 -SectionId "<SECTION_ID>" -Title "<PAGE_TITLE>" -Content "<MARKDOWN>"
```

Returns the new page's PageID on success.

**Parameters:**
- `-SectionId` (required) — the section ID from `Get-OneNoteHierarchy.ps1`
- `-Title` (required) — the page title
- `-Content` (optional) — markdown string for the page body
- `-InputFile` (optional) — path to a `.md` file to use as page content (alternative to `-Content`)

**Content format:** The script accepts markdown and converts it to OneNote formatting. Supported syntax:
- Headings (`#`, `##`, `###`)
- Bold (`**text**`), italic (`*text*`), strikethrough (`~~text~~`)
- Inline code (`` `text` ``), fenced code blocks (` ``` `)
- Bullet lists (`-` / `*`), numbered lists (`1.`), nested lists (indented)
- Links (`[text](url)`), images (`![alt](local-path)`)
- Pipe-delimited tables

**Tips:**
- For long content, write markdown to a temp file and pass via `-InputFile` to avoid escaping issues
- Use `Read-OneNotePage.ps1` with the returned PageID to verify the created page
- If the user doesn't specify a section, use `Get-OneNoteHierarchy.ps1` to show options and ask

### Step 6: Create Section

First, use `Get-OneNoteHierarchy.ps1` (Step 4) to find the target notebook ID. Then create the section:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\onenote-pages\scripts\New-OneNoteSection.ps1 -NotebookId "<NOTEBOOK_ID>" -Name "<SECTION_NAME>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\onenote-pages\scripts\New-OneNoteSection.ps1 -NotebookId "<NOTEBOOK_ID>" -Name "<SECTION_NAME>"
```

Returns the new section's SectionID on success. Use this ID with `New-OneNotePage.ps1` to create pages in the new section.

**Parameters:**
- `-NotebookId` (required) — the notebook ID from `Get-OneNoteHierarchy.ps1`
- `-Name` (required) — the name for the new section

---

## Rules

1. **MUST** always invoke scripts with `powershell -STA -NoProfile -File` — never run COM calls in a regular PowerShell session or background job.
2. **MUST** check if OneNote is running first if COM fails. Prompt user to open the OneNote app.
3. **MUST** present search results to user for disambiguation if multiple pages match before reading content.
4. **MUST** strip/interpret HTML tags in page content for clean output when summarizing.
5. **MUST** use `Get-OneNoteHierarchy.ps1` to discover section IDs before creating pages. Do not ask the user for raw section IDs.
6. **DO NOT** attempt to access pages from notebooks that aren't synced locally.
7. **MAY** combine with other skills when the OneNote content informs a technical investigation.
8. **DO NOT** use `-SkipImages` unless the user explicitly requests text-only output. Images often contain critical context (diagrams, screenshots, settings).
9. **DO NOT** edit, modify, or append to existing OneNote pages. This skill only supports creating new pages and sections. If a user asks to update, edit, or change an existing page, explain that editing is not supported and offer to create a new page with the updated content instead.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| COM object creation fails | OneNote not installed or not the desktop version | Tell user to install Office 365 OneNote desktop app |
| `GetHierarchy` hangs | OneNote not running, or MTA threading | Ensure `-STA` flag and that OneNote app is open |
| `GetPageContent` returns empty | Page not synced locally | Tell user to open the page in OneNote first to sync it |
| `Unexpected HRESULT` | Wrong threading model (MTA instead of STA) | Ensure using `powershell -STA` |
| `CreateNewPage` fails | Invalid section ID or section is read-only | Verify section ID from `Get-OneNoteHierarchy.ps1`; check notebook isn't read-only |
| `UpdatePageContent` fails | Malformed page XML | Check content for unusual characters; try with simpler content to isolate |
| `UpdateHierarchy` fails | Invalid notebook ID or notebook is read-only | Verify notebook ID from `Get-OneNoteHierarchy.ps1`; check notebook isn't read-only |

## Output Guidelines

- When showing page content, clean up HTML tags for readability
- Preserve links — show them as `[text](url)` markdown format
- For long pages, summarize first, then offer to show full content
- When user asks to "analyze" a page, read it and provide structured insights relevant to their question
- **Page links:** When presenting search results or page content that includes `DesktopLink` or `WebLink` fields, render them as clickable markdown links: `🖥️ [Open in Desktop](<DesktopLink>)` and `🌐 [Open in Web](<WebLink>)`. Display both links on the same line or as a short list beneath the page title.
