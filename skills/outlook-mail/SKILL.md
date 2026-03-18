---
name: outlook-mail
description: "Search and read Outlook emails via COM automation. Find emails by keyword, sender, date range, or subject. Read full email content or entire conversation threads. List mail folders. Activated when users ask to find, read, or summarize emails. Requires Windows with Microsoft Outlook installed."
compatibility: "Requires Windows with Microsoft Outlook (Office 2016+ / Microsoft 365) and Windows PowerShell 5.1"
metadata:
  author: Azure Core Team
  version: "1.0.0"
---

# Outlook Mail

Searches and reads Outlook emails programmatically via the Outlook COM API (`Outlook.Application`). No Graph API or cloud permissions required — talks directly to the locally running Outlook desktop app.

## Prerequisites

- **Windows-only** — uses Outlook COM automation (`Outlook.Application`)
- **Microsoft Outlook** (Office 2016+ / Microsoft 365) must be installed and running
- Mailbox must be synced (emails available in local cache/OST)
- **Windows PowerShell 5.1** (`powershell`) with `-STA` support must be available in `PATH`

## Activation Triggers

- User asks to "find an email about X" or "search my email for X"
- User asks to "read an email" or "show me the email from X"
- User asks to "summarize an email thread"
- User asks about email content from a specific person or topic
- User asks to "list my mail folders" or "show my Outlook folders"
- User mentions an email subject line or asks about a conversation
- User asks "what did X say in email about Y"

## Capabilities

1. **Search** — Find emails by keyword, subject, sender, date range ([Search-OutlookMail.ps1](./scripts/Search-OutlookMail.ps1))
2. **Read** — Fetch full email content by EntryID, or read an entire conversation thread by ConversationID; converts HTML body to readable text, preserves inline image placement with `[INLINE IMAGE: ...]` markers, and keeps links in markdown format ([Read-OutlookMail.ps1](./scripts/Read-OutlookMail.ps1))
3. **List Folders** — Browse Outlook folder hierarchy with message counts ([Get-OutlookFolders.ps1](./scripts/Get-OutlookFolders.ps1))

---

## Technical Details

### Critical: STA Threading

All scripts **MUST** be invoked with `powershell -STA -NoProfile -File <script>`. The Outlook COM object requires Single-Threaded Apartment mode. Without `-STA`, calls may hang or fail.

### COM Object

```powershell
$outlook = New-Object -ComObject Outlook.Application
$ns = $outlook.GetNamespace("MAPI")
```

### Default Folder Constants

| Constant | Value | Folder |
|----------|-------|--------|
| olFolderInbox | 6 | Inbox |
| olFolderSentMail | 5 | Sent Items |
| olFolderDrafts | 16 | Drafts |
| olFolderDeletedItems | 3 | Deleted Items |
| olFolderJunk | 23 | Junk Email |

### Key Properties (MailItem)

| Property | Type | Description |
|----------|------|-------------|
| Subject | String | Email subject line |
| SenderName | String | Display name of sender |
| SenderEmailAddress | String | Email address of sender |
| To | String | Recipients |
| CC | String | CC recipients |
| Body | String | Plain text body |
| HTMLBody | String | HTML body |
| ReceivedTime | DateTime | When email was received |
| EntryID | String | Unique ID for this email |
| ConversationID | String | Thread/conversation ID |
| ConversationTopic | String | Thread subject |
| Attachments | Collection | File attachments |

---

## Workflow

### Step 1: Determine Intent

- If user wants to **find emails** → go to Step 2 (Search)
- If user wants to **read a specific email** → go to Step 3 (Read by EntryID)
- If user wants to **read a thread** → Search first to get ConversationID, then Read by ConversationID
- If user wants to **browse folders** → go to Step 4 (List Folders)

### Step 2: Search for Emails

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\outlook-mail\scripts\Search-OutlookMail.ps1 -SearchTerm "<KEYWORD>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\outlook-mail\scripts\Search-OutlookMail.ps1 -SearchTerm "<KEYWORD>"
```

Returns matching emails with Subject, From, To, Date, ConversationID, and EntryID.

**Parameters:**
- `-SearchTerm <string>` — keyword to search in subject AND body (case-insensitive)
- `-Subject <string>` — search only in subject lines
- `-From <string>` — filter by sender name or email (substring match)
- `-Folder <string>` — which folder to search: Inbox (default), Sent, Drafts, Deleted, Junk, Archive, or All (Inbox + Sent)
- `-After <yyyy-MM-dd>` — only emails after this date
- `-Before <yyyy-MM-dd>` — only emails before this date
- `-MaxResults <int>` — limit results (default 25)

**Search tips:**
- Use `-Subject` for exact thread lookups (faster, less noise)
- Use `-From` to find emails from a specific person
- Combine `-SearchTerm` with `-After` to narrow date ranges
- Use `-Folder All` to include sent emails in results

### Step 3: Read Email Content

**Single email by EntryID:**

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\outlook-mail\scripts\Read-OutlookMail.ps1 -EntryID "<ENTRY_ID>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\outlook-mail\scripts\Read-OutlookMail.ps1 -EntryID "<ENTRY_ID>"
```

**Entire conversation thread by ConversationID:**

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\outlook-mail\scripts\Read-OutlookMail.ps1 -ConversationID "<CONV_ID>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\outlook-mail\scripts\Read-OutlookMail.ps1 -ConversationID "<CONV_ID>"
```

**Parameters:**
- `-EntryID <string>` — read a single email by its EntryID
- `-ConversationID <string>` — read all emails in a conversation thread (chronological order)
- `-MaxBodyChars <int>` — truncate body at N chars (default 5000, use 0 for unlimited)
- `-BodyOnly` (switch) — skip headers, only output body text
- `-SaveAttachments` (switch) — save attachments to a per-message directory under `$env:TEMP\outlook-mail\` with unique prefixed filenames (prevents overwrite when duplicate names exist)

**Reading tips:**
- For thread summaries, use `-ConversationID` to get all messages at once
- For long emails, increase `-MaxBodyChars` or set to 0
- Use `-SaveAttachments` when the user asks about attached files
- Inline/embedded images are emitted in body order as `[INLINE IMAGE: ...]` markers so image context stays aligned with nearby text

### Step 4: List Folders

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\outlook-mail\scripts\Get-OutlookFolders.ps1

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\outlook-mail\scripts\Get-OutlookFolders.ps1
```

**Parameters:**
- `-Depth <int>` — how many levels deep to recurse (default 2)

---

## Rules

1. **MUST** always invoke scripts with `powershell -STA -NoProfile -File` to ensure COM operations work correctly.
2. **DO NOT** modify, send, delete, or move any emails. This skill is **read-only**.
3. **MUST** present search results to user for disambiguation if multiple emails match before reading full content.
4. **MUST** clean up COM objects — the scripts handle this in `finally` blocks.
5. **DO NOT** attempt to access password-protected or encrypted emails — inform the user if access fails.
6. **MAY** combine with other skills (e.g., read an email about an incident, then investigate with IcM tools).
7. For long email threads (>10 messages), summarize key points and offer to show specific messages.
8. When the user mentions an email by subject or sender, **search first** to locate it.
9. When reading a thread, prefer `-ConversationID` over reading individual messages one by one.
10. **DO NOT** expose raw EntryIDs or ConversationIDs to the user — use them internally for lookups.
11. When summarizing HTML-heavy emails, use inline image markers to connect image evidence to the surrounding narrative.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| COM object creation fails | Outlook not installed or not running | Tell user to open Outlook |
| No emails found | Search terms too specific or wrong folder | Broaden search, try `-Folder All` |
| GetItemFromID fails | Invalid EntryID (email moved/deleted) | Re-search to get current EntryID |
| ConversationID iteration slow | Large mailbox with many items | Use `-MaxResults` on search, or add date filters |
| Body is empty | Email is HTML-only with no plain text part | Script renders `HTMLBody` first, then falls back to `Body` |
| Attachment save fails | Permission or disk space issue | Check temp directory permissions |

## Output Guidelines

- When showing search results, display Subject, From, Date, and whether attachments exist
- When reading threads, show messages in chronological order with clear separators
- For long threads, summarize the key points, decisions, and action items
- When user asks to "analyze" an email, read it and provide structured insights
- Strip email signatures and excessive quoted replies when summarizing
- Keep inline image markers in summaries when they carry evidence (charts, dashboards, screenshots)
