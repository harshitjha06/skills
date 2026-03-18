<#
.SYNOPSIS
    Creates a Word document from markdown content via COM automation.

.DESCRIPTION
    Parses markdown text and generates a .docx file using the Word COM API.
    Supports headings, bold/italic, inline code, bulleted/numbered lists (with nesting),
    tables, code blocks, blockquotes, hyperlinks, and horizontal rules.

.PARAMETER Content
    Raw markdown string. Mutually exclusive with -InputFile.

.PARAMETER InputFile
    Path to a .md file to convert. Mutually exclusive with -Content.

.PARAMETER OutputPath
    Full path for the output .docx file.

.PARAMETER Title
    Optional document title metadata.

.EXAMPLE
    powershell -STA -NoProfile -File Write-WordDocument.ps1 -InputFile "spec.md" -OutputPath "spec.docx"

.EXAMPLE
    powershell -STA -NoProfile -File Write-WordDocument.ps1 -Content "# Hello`nWorld" -OutputPath "out.docx"
#>
param(
    [string]$Content,
    [string]$InputFile,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$Title = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Validation ---
if (-not $Content -and -not $InputFile) {
    Write-Error "Provide -Content or -InputFile."
    exit 1
}
if ($Content -and $InputFile) {
    Write-Error "Provide -Content or -InputFile, not both."
    exit 1
}
if ($InputFile) {
    if (-not (Test-Path -LiteralPath $InputFile)) {
        Write-Error "File not found: $InputFile"
        exit 1
    }
    $Content = Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8
}
if (-not $Content) {
    Write-Error "No content to write."
    exit 1
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# --- Inline formatting: parse markdown inline syntax and write via Selection ---

# Convert markdown anchor text to a valid Word bookmark name (letters, digits, underscores; must start with letter/underscore)
function ConvertTo-BookmarkName {
    param([string]$Text)
    $bm = ($Text.Trim().ToLowerInvariant() -replace '\*+|~~|`|<[^>]+>|\[([^\]]+)\]\([^)]+\)', '$1')
    $bm = ($bm -replace '[^a-zA-Z0-9_\s-]', '' -replace '[\s-]+', '_').Trim('_')
    if ($bm -match '^\d') { $bm = "_$bm" }
    return $bm
}

function Write-InlineFormatted {
    param(
        [object]$Sel,
        [object]$Doc,
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return }

    # Order matters: bold+italic before bold before italic; code before links; strikethrough and underline
    $pattern = '\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*|`([^`]+)`|\[([^\]]+)\]\(([^\)]+)\)|~~(.+?)~~|<u>(.+?)</u>|<sup>(.+?)</sup>|<sub>(.+?)</sub>'

    $lastEnd = 0
    $allMatches = [regex]::Matches($Text, $pattern)

    foreach ($m in $allMatches) {
        # Plain text before this match
        if ($m.Index -gt $lastEnd) {
            $Sel.TypeText($Text.Substring($lastEnd, $m.Index - $lastEnd))
        }

        if ($m.Groups[1].Success) {
            # ***bold+italic***
            $Sel.Font.Bold = -1; $Sel.Font.Italic = -1
            $Sel.TypeText($m.Groups[1].Value)
            $Sel.Font.Bold = 0; $Sel.Font.Italic = 0
        }
        elseif ($m.Groups[2].Success) {
            # **bold**
            $Sel.Font.Bold = -1
            $Sel.TypeText($m.Groups[2].Value)
            $Sel.Font.Bold = 0
        }
        elseif ($m.Groups[3].Success) {
            # *italic*
            $Sel.Font.Italic = -1
            $Sel.TypeText($m.Groups[3].Value)
            $Sel.Font.Italic = 0
        }
        elseif ($m.Groups[4].Success) {
            # `inline code` — Consolas, keep current size
            $prevName = $Sel.Font.Name
            $Sel.Font.Name = "Consolas"
            $Sel.TypeText($m.Groups[4].Value)
            $Sel.Font.Name = $prevName
        }
        elseif ($m.Groups[5].Success) {
            # [display](url)
            $display = $m.Groups[5].Value
            $url = $m.Groups[6].Value
            $anchor = $Sel.Range
            if ($url.StartsWith('#')) {
                # Internal link — normalize anchor to Word bookmark name, use SubAddress
                $bmTarget = ConvertTo-BookmarkName ($url.Substring(1))
                $Doc.Hyperlinks.Add($anchor, "", $bmTarget, "", $display) | Out-Null
            } else {
                $Doc.Hyperlinks.Add($anchor, $url, "", "", $display) | Out-Null
            }
        }
        elseif ($m.Groups[7].Success) {
            # ~~strikethrough~~
            $Sel.Font.StrikeThrough = -1
            $Sel.TypeText($m.Groups[7].Value)
            $Sel.Font.StrikeThrough = 0
        }
        elseif ($m.Groups[8].Success) {
            # <u>underline</u>
            $Sel.Font.Underline = 1  # wdUnderlineSingle
            $Sel.TypeText($m.Groups[8].Value)
            $Sel.Font.Underline = 0
        }
        elseif ($m.Groups[9].Success) {
            # <sup>superscript</sup>
            $Sel.Font.Superscript = -1
            $Sel.TypeText($m.Groups[9].Value)
            $Sel.Font.Superscript = 0
        }
        elseif ($m.Groups[10].Success) {
            # <sub>subscript</sub>
            $Sel.Font.Subscript = -1
            $Sel.TypeText($m.Groups[10].Value)
            $Sel.Font.Subscript = 0
        }

        $lastEnd = $m.Index + $m.Length
    }

    # Trailing plain text
    if ($lastEnd -lt $Text.Length) {
        $Sel.TypeText($Text.Substring($lastEnd))
    }
}

# --- Render a markdown table as a Word table ---
function Render-Table {
    param(
        [object]$Sel,
        [object]$Doc,
        [string[]]$Lines
    )
    # Filter out separator rows (|---|---|)
    $dataRows = @($Lines | Where-Object { $_ -notmatch '^\|[\s\-:|]+\|$' })
    if ($dataRows.Count -eq 0) { return }

    # Parse columns from first row
    $headerCells = @($dataRows[0] -split '\|' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
    $colCount = $headerCells.Count
    if ($colCount -eq 0) { return }

    $rowCount = $dataRows.Count
    $table = $Doc.Tables.Add($Sel.Range, $rowCount, $colCount)
    $table.Borders.Enable = $true
    try { $table.Style = "Table Grid" } catch { }

    for ($r = 0; $r -lt $rowCount; $r++) {
        $cells = @($dataRows[$r] -split '\|' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
        for ($c = 0; $c -lt [Math]::Min($cells.Count, $colCount); $c++) {
            $cell = $table.Cell($r + 1, $c + 1)
            if ($cells[$c]) {
                $Sel.SetRange($cell.Range.Start, $cell.Range.Start)
                Write-InlineFormatted $Sel $Doc $cells[$c]
            }
            if ($r -eq 0) { $cell.Range.Font.Bold = -1 }
        }
    }

    # Move cursor past the table
    $Sel.EndKey(6) | Out-Null  # wdStory
}

# --- End list formatting ---
function End-List {
    param([object]$Sel)
    try { $Sel.Range.ListFormat.RemoveNumbers() } catch { }
    try { $Sel.ClearFormatting() } catch { $Sel.Style = "Normal" }
}

# --- Create Word application ---
$word = $null
$doc = $null

try {
    $word = New-Object -ComObject Word.Application
} catch {
    Write-Error "Failed to create Word COM object. Ensure Microsoft Word is installed."
    exit 1
}

try {
    $word.Visible = $false
    $word.DisplayAlerts = 0  # wdAlertsNone
    $doc = $word.Documents.Add()
    $sel = $word.Selection

    # Multi-level list templates (outline gallery supports ListIndent/ListOutdent)
    $outlineGallery = $word.ListGalleries.Item(3)  # wdOutlineNumberGallery
    $bulletTemplate = $outlineGallery.ListTemplates.Item(3)
    $numberTemplate = $outlineGallery.ListTemplates.Item(1)

    if ($Title) {
        try { $doc.BuiltInDocumentProperties.Item("Title").Value = $Title } catch { }
    }

    # Disable spellcheck/grammar redlines — generated docs with code trigger too many false positives
    $doc.ShowSpellingErrors = $false
    $doc.ShowGrammaticalErrors = $false

    # --- State machine ---
    $lines = $Content -split "`r?`n"
    $inCodeBlock = $false
    $codeLines = @()
    $inTable = $false
    $tableLines = @()
    $inList = $false
    $listType = ""   # "bullet" or "number"
    $listLevel = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # ---- Code block delimiter ----
        if ($line -match '^```') {
            if ($inCodeBlock) {
                # Render accumulated code
                if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
                foreach ($cl in $codeLines) {
                    $sel.Font.Name = "Consolas"
                    $sel.Font.Size = 10
                    $sel.ParagraphFormat.SpaceBefore = 0
                    $sel.ParagraphFormat.SpaceAfter = 0
                    $sel.ParagraphFormat.Shading.BackgroundPatternColor = 15790320  # RGB(240,240,240)
                    $sel.TypeText($(if ([string]::IsNullOrEmpty($cl)) { " " } else { $cl }))
                    $sel.TypeParagraph()
                }
                try { $sel.ClearFormatting() } catch { $sel.Style = "Normal" }
                $inCodeBlock = $false
                $codeLines = @()
            } else {
                $inCodeBlock = $true
                $codeLines = @()
            }
            continue
        }
        if ($inCodeBlock) { $codeLines += $line; continue }

        # ---- Table row ----
        if ($line -match '^\|.+\|$') {
            if (-not $inTable) {
                if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
                $inTable = $true
                $tableLines = @()
            }
            $tableLines += $line
            continue
        }
        if ($inTable) {
            # End of table block — render and fall through to process current line
            Render-Table $sel $doc $tableLines
            try { $sel.ClearFormatting() } catch { $sel.Style = "Normal" }
            $inTable = $false
            $tableLines = @()
        }

        # ---- Blank line ----
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
            continue
        }

        # ---- Horizontal rule (---, ***, ___) ----
        if ($line -match '^(\-{3,}|\*{3,}|_{3,})\s*$') {
            if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
            $sel.Style = "Normal"
            try {
                $sel.InlineShapes.AddHorizontalLineStandard() | Out-Null
            } catch {
                # Fallback: insert a visible text line
                $sel.TypeText([string]([char]0x2500) * 40)
            }
            $sel.TypeParagraph()
            continue
        }

        # ---- Heading ----
        if ($line -match '^(#{1,6})\s+(.+)$') {
            $level = $Matches[1].Length
            $headingText = $Matches[2]
            if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
            try { $sel.ClearFormatting() } catch { }
            $sel.Style = "Heading $level"
            $bmStart = $sel.Range.Start
            Write-InlineFormatted $sel $doc $headingText
            # Create bookmark for internal links (markdown anchor convention)
            try {
                $bm = ConvertTo-BookmarkName $headingText
                if ($bm.Length -gt 40) { $bm = $bm.Substring(0, 40).TrimEnd('_') }
                if ($bm) {
                    $bmRange = $doc.Range($bmStart, $sel.Range.Start)
                    $doc.Bookmarks.Add($bm, $bmRange) | Out-Null
                }
            } catch { }
            $sel.TypeParagraph()
            try { $sel.ClearFormatting() } catch { }
            continue
        }

        # ---- Blockquote ----
        if ($line -match '^>\s?(.*)$') {
            $quoteText = $Matches[1]
            if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
            try { $sel.ClearFormatting() } catch { }
            try {
                $sel.Style = "Quote"
            } catch {
                $sel.Style = "Normal"
                $sel.ParagraphFormat.LeftIndent = 36
                $sel.Font.Italic = -1
                $sel.Font.Color = 8421504
            }
            Write-InlineFormatted $sel $doc $quoteText
            $sel.TypeParagraph()
            try { $sel.ClearFormatting() } catch { }
            continue
        }

        # ---- Bulleted list ----
        if ($line -match '^(\s*)([-*+])\s+(.+)$') {
            $indent = $Matches[1]
            $itemText = $Matches[3]
            $newLevel = [Math]::Floor($indent.Length / 2)
            $newType = "bullet"

            if (-not $inList -or $listType -ne $newType) {
                if ($inList) { End-List $sel }
                $sel.Range.ListFormat.ApplyListTemplate($bulletTemplate, $false, 1)
                $listLevel = 0
            }

            $diff = $newLevel - $listLevel
            for ($n = 0; $n -lt [Math]::Abs($diff); $n++) {
                if ($diff -gt 0) { $sel.Range.ListFormat.ListIndent() }
                else { $sel.Range.ListFormat.ListOutdent() }
            }

            Write-InlineFormatted $sel $doc $itemText
            $sel.TypeParagraph()
            $inList = $true; $listType = $newType; $listLevel = $newLevel
            continue
        }

        # ---- Numbered list ----
        if ($line -match '^(\s*)\d+\.\s+(.+)$') {
            $indent = $Matches[1]
            $itemText = $Matches[2]
            $newLevel = [Math]::Floor($indent.Length / 2)
            $newType = "number"

            if (-not $inList -or $listType -ne $newType) {
                if ($inList) { End-List $sel }
                $sel.Range.ListFormat.ApplyListTemplate($numberTemplate, $false, 1)
                $listLevel = 0
            }

            $diff = $newLevel - $listLevel
            for ($n = 0; $n -lt [Math]::Abs($diff); $n++) {
                if ($diff -gt 0) { $sel.Range.ListFormat.ListIndent() }
                else { $sel.Range.ListFormat.ListOutdent() }
            }

            Write-InlineFormatted $sel $doc $itemText
            $sel.TypeParagraph()
            $inList = $true; $listType = $newType; $listLevel = $newLevel
            continue
        }

        # ---- Normal paragraph ----
        if ($inList) { End-List $sel; $inList = $false; $listType = ""; $listLevel = 0 }
        $sel.Style = "Normal"
        Write-InlineFormatted $sel $doc $line
        $sel.TypeParagraph()
    }

    # --- Flush remaining state ---
    if ($inCodeBlock -and $codeLines.Count -gt 0) {
        foreach ($cl in $codeLines) {
            $sel.Font.Name = "Consolas"; $sel.Font.Size = 10
            $sel.TypeText($(if ([string]::IsNullOrEmpty($cl)) { " " } else { $cl }))
            $sel.TypeParagraph()
        }
        try { $sel.ClearFormatting() } catch { }
    }
    if ($inTable -and $tableLines.Count -gt 0) {
        Render-Table $sel $doc $tableLines
        try { $sel.ClearFormatting() } catch { }
    }
    if ($inList) { End-List $sel }

    # --- Save ---
    $doc.SaveAs2($OutputPath, 16)  # wdFormatDocumentDefault (.docx)

    $pageCount = $doc.ComputeStatistics(2)  # wdStatisticPages
    $wordCount = $doc.ComputeStatistics(0)  # wdStatisticWords
    Write-Host "Document saved: $OutputPath ($pageCount pages, $wordCount words)"

} catch {
    Write-Error "Failed to create document: $($_.Exception.Message)"
    exit 1
} finally {
    if ($doc) {
        try { $doc.Close($false) } catch { }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null } catch { }
    }
    if ($word) {
        try { $word.Quit() } catch { }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch { }
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
