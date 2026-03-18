---
name: word-documents
description: "Reads, edits, and writes Word documents (.docx/.doc) via COM automation. Search for documents, extract full text with heading structure, tables as markdown, edit targeted sections, and create Word documents from markdown content. Requires Windows with Microsoft Word installed."
compatibility: "Requires Windows with Microsoft Word (Office 2016+ / Microsoft 365) and Windows PowerShell 5.1"
metadata:
  author: Azure Core Team
  version: "1.0"
---

# Word Documents Toolkit

Reads, edits, and creates Word documents programmatically via the Word COM API (`Word.Application`). No Graph API or cloud permissions required — talks directly to the locally installed Microsoft Word.

## Prerequisites

- **Windows-only** — uses Word COM automation (`Word.Application`)
- **Microsoft Word** (Office 2016+ / Microsoft 365) must be installed (does NOT need to be running)
- **Windows PowerShell 5.1** (`powershell`) with `-STA` support must be available in `PATH` for image extraction from legacy `.doc` files

## Activation Triggers

- User asks to "read a Word document" or "open a Word doc"
- User asks to "find a Word document about X"
- User asks to "extract tables from a Word doc"
- User provides a path to a `.docx` or `.doc` file
- User asks to analyze, summarize, or review content from a Word document
- User mentions a document name that likely refers to a Word file
- User asks to "create a Word document" or "write a Word doc"
- User asks to "convert markdown to Word" or "export as .docx"
- User asks to "generate a document" or "make a spec/report in Word"
- User provides markdown content and wants it saved as a `.docx` file
- User asks to "edit/update/patch" content inside an existing Word document

## Capabilities

### Reading

1. **Search** — Find Word documents by filename keyword across Documents, OneDrive, Desktop, Downloads ([Search-WordDocument.ps1](./scripts/Search-WordDocument.ps1))
2. **Read** — Extract full document text with heading structure preserved as markdown headings ([Read-WordDocument.ps1](./scripts/Read-WordDocument.ps1))
3. **Tables** — Extract all tables as markdown tables
4. **Metadata** — Get document properties (author, dates, word count, page count)
5. **Comments & Track Changes** — Extract all review comments (with author, date, context) and tracked revisions (insertions, deletions)
6. **Headers/Footers** — Extract document header and footer text
7. **Inline Formatting** — Bold → `**text**`, italic → `*text*`, bold+italic → `***text***`, strikethrough → `~~text~~`, underline → `<u>text</u>`, superscript → `<sup>text</sup>`, subscript → `<sub>text</sub>`
8. **Lists** — Bulleted lists → `- item`, numbered lists → `1. item`, with nesting via indentation
9. **Hyperlinks** — External links converted to markdown `[display text](url)` format. TOC-styled paragraphs and internal-only links (bookmark cross-references, self-referencing navigation) are filtered out.
10. **Section Reading** — Extract only a specific section by heading name with `-Section`
11. **Footnotes & Endnotes** — Extracted as `[^N]: text` reference-style footnotes
12. **Blockquotes** — Quote-styled paragraphs → `> text`
13. **Code Blocks** — Monospace-font paragraphs (Consolas, Courier, etc.) → fenced code blocks

### Writing

1. **Create documents from markdown** ([Write-WordDocument.ps1](./scripts/Write-WordDocument.ps1))
2. **Headings** — `# H1` through `###### H6` → Word Heading styles
3. **Bold / Italic** — `**bold**`, `*italic*`, `***both***` → character formatting
4. **Strikethrough** — `~~text~~` → strikethrough formatting
5. **Underline** — `<u>text</u>` → single underline
6. **Superscript / Subscript** — `<sup>text</sup>`, `<sub>text</sub>` → super/subscript formatting
7. **Inline Code** — `` `code` `` → Consolas font
8. **Bulleted Lists** — `- item` with nesting via indentation → Word bulleted lists
9. **Numbered Lists** — `1. item` with nesting via indentation → Word numbered lists
10. **Hyperlinks** — `[text](url)` → Word hyperlinks; `[text](#heading)` → internal bookmark hyperlinks (headings get auto-generated bookmarks via `ConvertTo-BookmarkName`)
11. **Tables** — `| col | col |` with `|---|---|` separator → Word tables with bold headers
12. **Code Blocks** — Triple-backtick fenced blocks → Consolas 10pt with gray shading
13. **Blockquotes** — `> text` → Quote style (or indented italic fallback)
14. **Horizontal Rules** — `---`, `***`, `___` → bottom border line

### Editing

1. **Targeted document edits** ([Edit-WordDocument.ps1](./scripts/Edit-WordDocument.ps1))
2. **Find/Replace** — replace all matches of exact text globally
3. **Insert After Heading** — insert new content immediately after a matching heading
4. **Replace Section Body** — replace all content under a heading until the next same/higher-level heading
5. **Safe Output Default** — saves to `<name>-edited<ext>` unless explicitly using `-InPlace`
6. **Dry Run** — preview number/type of changes without writing a file

---

## Workflow

### Step 1: Determine Intent

- If user provides a **file path** → go to Step 3 (Read)
- If user wants to **find a document** → go to Step 2 (Search)
- If user wants **tables only** → Read with `-TablesOnly`
- If user wants **metadata only** → Read with `-MetadataOnly`

### Step 2: Search for Documents

```powershell
# From a repo with the skill checked in:
powershell -NoProfile -File .\.github\skills\word-documents\scripts\Search-WordDocument.ps1 -SearchTerm "<KEYWORD>"

# From the user-level skill install:
powershell -NoProfile -File ~\.copilot\skills\word-documents\scripts\Search-WordDocument.ps1 -SearchTerm "<KEYWORD>"
```

Returns matching documents with Name, Path, Size, and Modified date.

**Parameters:**
- `-SearchTerm` (required) — keyword to match against filenames (case-insensitive, partial match)
- `-Path <dir>` (optional) — override search root to a specific directory
- `-MaxResults <int>` — limit results (default 20)

### Step 3: Read Document Content

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\word-documents\scripts\Read-WordDocument.ps1 -FilePath "<FULL_PATH>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\word-documents\scripts\Read-WordDocument.ps1 -FilePath "<FULL_PATH>"
```

Returns document metadata, tables (as markdown), and full text content with headings.

**Parameters:**
- `-FilePath` (required) — full path to the .docx or .doc file
- `-TablesOnly` (switch) — only extract tables
- `-MetadataOnly` (switch) — only return document properties
- `-SkipImages` (switch) — skip image extraction for faster text-only output
- `-Section <string>` (optional) — only output the body text section matching this heading (partial match, case-insensitive). Stops at the next heading of the same or higher level.
- `-MaxChars <int>` — limit body text length (default unlimited)

**Output sections (in order):**
1. Metadata block (author, dates, word/page count)
2. Comments with author, date, and surrounding context
3. Track changes (insertions/deletions with author, capped at 50)
4. Headers/footers (from first section)
5. Embedded images extracted to `$env:TEMP\word-documents\` as PNG/JPG files, paths printed as `[IMAGE: <path>]`
6. Tables rendered as markdown tables with header separators
7. Body text with heading styles → `#`, lists → `- `/`1.`, bold → `**`, italic → `*`, hyperlinks → `[text](url)`

### Step 4: Write a Document

The preferred workflow is to write markdown content to a temp `.md` file, then invoke the script:

```powershell
# 1. Write markdown to a temp file
$mdPath = Join-Path $env:TEMP "word-writer-input.md"
Set-Content -Path $mdPath -Value $markdownContent -Encoding UTF8

# 2. Convert to Word (from a repo with the skill checked in):
powershell -STA -NoProfile -File .\.github\skills\word-documents\scripts\Write-WordDocument.ps1 -InputFile $mdPath -OutputPath "<OUTPUT_PATH>"

# 2. Convert to Word (from the user-level skill install):
powershell -STA -NoProfile -File ~\.copilot\skills\word-documents\scripts\Write-WordDocument.ps1 -InputFile $mdPath -OutputPath "<OUTPUT_PATH>"
```

Or for short content, pass markdown directly:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\word-documents\scripts\Write-WordDocument.ps1 -Content "# Title`n`nHello **world**" -OutputPath "<OUTPUT_PATH>"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\word-documents\scripts\Write-WordDocument.ps1 -Content "# Title`n`nHello **world**" -OutputPath "<OUTPUT_PATH>"
```

**Parameters:**
- `-Content <string>` — raw markdown string (mutually exclusive with `-InputFile`)
- `-InputFile <string>` — path to a `.md` file to convert (preferred for multi-line content)
- `-OutputPath <string>` (required) — full path for the output `.docx` file
- `-Title <string>` (optional) — document title metadata

**Supported Markdown:**
- Headings (`#` through `######`)
- Bold (`**text**`), italic (`*text*`), bold+italic (`***text***`)
- Inline code (`` `code` ``)
- Bulleted lists (`-`, `*`, `+`) with nesting (2-space indent per level)
- Numbered lists (`1.`) with nesting
- Tables (`| col | col |` with separator row)
- Fenced code blocks (triple backtick, with optional language tag)
- Blockquotes (`> text`)
- Hyperlinks (`[text](url)` and `[text](#anchor)` for internal bookmarks)
- Horizontal rules (`---`, `***`, `___`)

### Step 5: Edit an Existing Document

Use targeted edit operations against an existing file:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\word-documents\scripts\Edit-WordDocument.ps1 -FilePath "<FULL_PATH>" -FindText "old" -ReplaceText "new"

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\word-documents\scripts\Edit-WordDocument.ps1 -FilePath "<FULL_PATH>" -FindText "old" -ReplaceText "new"
```

Section replacement:

```powershell
# From a repo with the skill checked in:
powershell -STA -NoProfile -File .\.github\skills\word-documents\scripts\Edit-WordDocument.ps1 -FilePath "<FULL_PATH>" -ReplaceSection "Architecture" -SectionContent "Updated section text."

# From the user-level skill install:
powershell -STA -NoProfile -File ~\.copilot\skills\word-documents\scripts\Edit-WordDocument.ps1 -FilePath "<FULL_PATH>" -ReplaceSection "Architecture" -SectionContent "Updated section text."
```

**Parameters:**
- `-FilePath <string>` (required) — source .docx/.doc file
- `-OutputPath <string>` (optional) — output file path (defaults to `<name>-edited<ext>`)
- `-InPlace` (switch) — save back to source file
- `-EnableTrackChanges` (switch) — apply edits with Word track changes enabled
- `-DryRun` (switch) — preview edits without saving
- `-FindText` + `-ReplaceText` — find/replace operation (must be used together)
- `-InsertAfterHeading` + `-InsertContent` — insert operation (must be used together)
- `-ReplaceSection` + `-SectionContent` — section body replacement operation (must be used together)

---

## Rules

1. **MUST** always invoke scripts with `powershell -STA -NoProfile -File` to ensure COM operations work correctly.
2. **DO NOT** modify any Word document when reading — documents are always opened with `ReadOnly = $true`.
3. **MUST** always clean up COM objects — the scripts handle this in `finally` blocks.
4. **MUST** present search results to user for disambiguation if multiple documents match before reading.
5. **DO NOT** attempt to read password-protected documents — inform the user if access fails.
6. **MAY** combine with other skills (e.g., read a spec doc, then investigate related IcM incidents).
7. **DO NOT** use `-SkipImages` unless the user explicitly requests text-only output. Images often contain critical diagrams and architecture visuals.
8. For large documents, summarize first, then offer to show specific sections.
9. When the user mentions a document by name without a path, **search first** to locate it.
10. When writing, prefer `-InputFile` over `-Content` for multi-line markdown to avoid escaping issues.
11. When writing, always specify the full output path including `.docx` extension.
12. When writing, save the markdown to a temp file first (`$env:TEMP\word-writer-input.md`), then pass via `-InputFile`.
13. When editing, perform one operation per run (`find/replace`, `insert-after-heading`, or `replace-section`).
14. When editing, default to a separate output file; use `-InPlace` only when explicitly requested.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| COM object creation fails | Word not installed | Tell user to install Microsoft Word |
| File not found | Wrong path or file moved | Search for the document by name |
| Document open fails | File locked by another process or password-protected | Tell user to close the file in Word or provide password |
| Table extraction error | Merged cells or complex table layout | Some cells may show empty — inform user |
| Image extraction fails | Old .doc format (OLE) without `-STA` flag | Ensure script is invoked with `powershell -STA` |
| Write save fails | Output directory doesn't exist or path is invalid | Check output path; script auto-creates parent dirs |
| Write content empty | Neither `-Content` nor `-InputFile` provided | Provide one of the two parameters |
| Edit validation fails | Missing operation parameters or multiple operations requested | Provide exactly one valid operation with its required parameter pair |

## Output Guidelines

- Preserve document structure using markdown headings
- Render tables as markdown for readability
- For very long documents (>5000 words), summarize key sections first
- When user asks to "analyze" a document, read it and provide structured insights
