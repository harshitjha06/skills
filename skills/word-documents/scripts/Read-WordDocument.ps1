<#
.SYNOPSIS
    Reads the full content of a Word document via COM automation.

.DESCRIPTION
    Opens a Word document using the Word COM API, extracts text content, tables,
    headings, metadata, embedded images, comments, track changes, headers/footers,
    and inline formatting (bold/italic). Lists are rendered as markdown. Hyperlinks
    are converted to markdown link syntax. Returns clean text output suitable for
    LLM consumption.

.PARAMETER FilePath
    Full path to the .docx or .doc file.

.PARAMETER TablesOnly
    If set, only extracts tables from the document.

.PARAMETER MetadataOnly
    If set, only returns document metadata (author, dates, word count, etc.).

.PARAMETER SkipImages
    If set, skips image extraction (faster for text-only analysis).

.PARAMETER MaxChars
    Maximum characters of body text to return. Default 0 (unlimited).

.PARAMETER Section
    If set, only output the body text section matching this heading (partial match).
    Outputs from the matching heading until the next heading of the same or higher level.

.EXAMPLE
    powershell -STA -NoProfile -File Read-WordDocument.ps1 -FilePath "C:\docs\spec.docx"
    powershell -STA -NoProfile -File Read-WordDocument.ps1 -FilePath "C:\docs\spec.docx" -Section "Architecture"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [switch]$TablesOnly,

    [switch]$MetadataOnly,

    [switch]$SkipImages,

    [int]$MaxChars = 0,

    [string]$Section = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

$FilePath = (Resolve-Path $FilePath).Path

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
    $word.DisplayAlerts = 0  # wdAlertsNone — suppress all dialogs
    # Open read-only (3rd param = $true)
    $doc = $word.Documents.Open($FilePath, $false, $true)

    # --- Metadata ---
    $props = $doc.BuiltInDocumentProperties
    $meta = @{}
    $metaFields = @("Title", "Author", "Last Author", "Creation Date", "Last Save Time", "Number of Words", "Number of Pages", "Number of Characters")
    foreach ($field in $metaFields) {
        try {
            $val = $props.Item($field).Value
            if ($val) { $meta[$field] = $val.ToString() }
        } catch { }
    }

    Write-Host "=== Document: $([System.IO.Path]::GetFileName($FilePath)) ==="
    Write-Host ""

    # Use per-run unique temp dir for image extraction (avoids race with concurrent runs)
    $imgDir = Join-Path $env:TEMP "word-documents-$([System.IO.Path]::GetRandomFileName())"

    # Fallback: compute stats directly if BuiltInDocumentProperties failed
    try {
        if (-not $meta.ContainsKey("Number of Words")) {
            $meta["Number of Words"] = $doc.ComputeStatistics(0, $false).ToString()
        }
        if (-not $meta.ContainsKey("Number of Pages")) {
            $meta["Number of Pages"] = $doc.ComputeStatistics(2, $false).ToString()
        }
        if (-not $meta.ContainsKey("Number of Characters")) {
            $meta["Number of Characters"] = $doc.ComputeStatistics(3, $false).ToString()
        }
    } catch { }

    if ($meta.Count -gt 0) {
        Write-Host "--- Metadata ---"
        foreach ($kv in $meta.GetEnumerator() | Sort-Object Key) {
            Write-Host "$($kv.Key): $($kv.Value)"
        }
        Write-Host ""
    }

    if ($MetadataOnly) { return }

    # --- Comments ---
    if ($doc.Comments.Count -gt 0) {
        Write-Host "--- Comments ($($doc.Comments.Count)) ---"
        foreach ($comment in $doc.Comments) {
            try {
                $author = $comment.Author
                $date = $comment.Date.ToString("yyyy-MM-dd HH:mm")
                $cText = $comment.Range.Text
                $context = $comment.Scope.Text -replace '[\r\n\a\x07]', ' '
                if ($context.Length -gt 100) { $context = $context.Substring(0, 100) + "..." }
                Write-Host "[$author, $date] on `"$context`": $cText"
            } catch { }
        }
        Write-Host ""
    }

    # --- Track Changes ---
    if ($doc.Revisions.Count -gt 0) {
        $revCount = $doc.Revisions.Count
        $revLimit = [Math]::Min($revCount, 50)
        Write-Host "--- Track Changes ($revCount revisions) ---"
        for ($r = 1; $r -le $revLimit; $r++) {
            try {
                $rev = $doc.Revisions.Item($r)
                $type = switch ($rev.Type) { 1 { "INSERT" } 2 { "DELETE" } default { "FORMAT" } }
                $rText = $rev.Range.Text -replace '[\r\n\a\x07]', ' '
                if ($rText.Length -gt 120) { $rText = $rText.Substring(0, 120) + "..." }
                Write-Host "[$type by $($rev.Author)] $rText"
            } catch { }
        }
        if ($revCount -gt 50) { Write-Host "... and $($revCount - 50) more revisions" }
        Write-Host ""
    }

    # --- Headers & Footers (first section only) ---
    $hfOutput = @()
    foreach ($sect in $doc.Sections) {
        for ($hfType = 1; $hfType -le 3; $hfType++) {
            $typeName = switch ($hfType) { 1 { "Primary" } 2 { "First Page" } 3 { "Even Pages" } }
            try {
                $hdr = $sect.Headers.Item($hfType)
                if ($hdr.Exists) {
                    $hText = $hdr.Range.Text.TrimEnd([char]13, [char]7)
                    if (-not [string]::IsNullOrWhiteSpace($hText)) { $hfOutput += "Header ($typeName): $hText" }
                }
            } catch { }
            try {
                $ftr = $sect.Footers.Item($hfType)
                if ($ftr.Exists) {
                    $fText = $ftr.Range.Text.TrimEnd([char]13, [char]7)
                    if (-not [string]::IsNullOrWhiteSpace($fText)) { $hfOutput += "Footer ($typeName): $fText" }
                }
            } catch { }
        }
        break  # first section only
    }
    if ($hfOutput.Count -gt 0) {
        Write-Host "--- Headers/Footers ---"
        foreach ($hf in $hfOutput) { Write-Host $hf }
        Write-Host ""
    }

    # --- Images ---
    $imageFiles = @()
    if (-not $SkipImages -and $doc.InlineShapes.Count -gt 0) {
        New-Item -ItemType Directory -Path $imgDir -Force | Out-Null

        # Try ZIP extraction first (fast, works for true OOXML .docx files)
        $zipExtracted = $false
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
            try {
                $mediaEntries = $zip.Entries | Where-Object { $_.FullName -like "word/media/*" -and $_.Length -gt 0 }
                foreach ($entry in $mediaEntries) {
                    $outPath = Join-Path $imgDir ([System.IO.Path]::GetFileName($entry.Name))
                    $stream = $entry.Open()
                    try {
                        $fileStream = [System.IO.File]::Create($outPath)
                        try { $stream.CopyTo($fileStream) }
                        finally { $fileStream.Close() }
                    } finally { $stream.Close() }
                }
                $zipExtracted = $true
            } finally { $zip.Dispose() }
        } catch {
            # Not a ZIP — old OLE .doc format. Fall back to EnhMetaFileBits (requires STA).
        }

        # Fallback: extract via EnhMetaFileBits (works for OLE .doc files, needs -STA)
        if (-not $zipExtracted) {
            Add-Type -AssemblyName System.Drawing
            for ($i = 1; $i -le $doc.InlineShapes.Count; $i++) {
                try {
                    $emfBytes = $doc.InlineShapes.Item($i).Range.EnhMetaFileBits
                    $ms = New-Object System.IO.MemoryStream(,$emfBytes)
                    $img = [System.Drawing.Image]::FromStream($ms)
                    $outPath = Join-Path $imgDir ("word-img-$($i.ToString('D3')).png")
                    $img.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    $img.Dispose()
                    $ms.Dispose()
                } catch {
                    Write-Host "[IMAGE ${i}: extraction failed - $($_.Exception.Message)]"
                }
            }
        }

        $imageFiles = @(Get-ChildItem $imgDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(png|jpg|jpeg|gif|bmp|emf|wmf|tiff?)' } |
            Sort-Object Name)

        if ($imageFiles.Count -gt 0) {
            Write-Host "--- Images ($($imageFiles.Count) extracted to $imgDir) ---"
            foreach ($imgFile in $imageFiles) {
                Write-Host "[IMAGE: $($imgFile.FullName)]"
            }
            Write-Host ""
        }
    }

    # --- Tables ---
    if ($doc.Tables.Count -gt 0) {
        Write-Host "--- Tables ($($doc.Tables.Count) found) ---"
        Write-Host ""
        $tableIndex = 0
        foreach ($table in $doc.Tables) {
            $tableIndex++
            Write-Host "[Table $tableIndex]: $($table.Rows.Count) rows x $($table.Columns.Count) columns"

            # Build markdown table
            for ($r = 1; $r -le $table.Rows.Count; $r++) {
                $rowCells = @()
                for ($c = 1; $c -le $table.Columns.Count; $c++) {
                    try {
                        $cellText = $table.Cell($r, $c).Range.Text
                        # Word table cells end with \r\a — strip control chars
                        $cellText = $cellText -replace '[\r\n\a\x07]', '' | ForEach-Object { $_.Trim() }
                        $rowCells += $cellText
                    } catch {
                        $rowCells += ""
                    }
                }
                Write-Host ("| " + ($rowCells -join " | ") + " |")

                # Add header separator after first row
                if ($r -eq 1) {
                    $sep = ($rowCells | ForEach-Object { "---" }) -join " | "
                    Write-Host ("| " + $sep + " |")
                }
            }
            Write-Host ""
        }
    }

    if ($TablesOnly) { return }

    # --- Footnotes & Endnotes ---
    $footnoteMap = @{}
    if ($doc.Footnotes.Count -gt 0) {
        Write-Host "--- Footnotes ($($doc.Footnotes.Count)) ---"
        for ($fn = 1; $fn -le $doc.Footnotes.Count; $fn++) {
            try {
                $note = $doc.Footnotes.Item($fn)
                $noteText = $note.Range.Text -replace '[\r\n\a\x07]', ' '
                $footnoteMap[$note.Reference.Start] = $fn
                Write-Host "[^${fn}]: $noteText"
            } catch { }
        }
        Write-Host ""
    }
    if ($doc.Endnotes.Count -gt 0) {
        $offset = $doc.Footnotes.Count
        Write-Host "--- Endnotes ($($doc.Endnotes.Count)) ---"
        for ($en = 1; $en -le $doc.Endnotes.Count; $en++) {
            try {
                $note = $doc.Endnotes.Item($en)
                $noteText = $note.Range.Text -replace '[\r\n\a\x07]', ' '
                $idx = $offset + $en
                Write-Host "[^${idx}]: $noteText"
            } catch { }
        }
        Write-Host ""
    }

    # --- Body Text ---
    Write-Host "--- Content ---"
    Write-Host ""

    # Section filtering state
    $inTargetSection = [string]::IsNullOrEmpty($Section)
    $targetLevel = 0
    $charCount = 0
    $inCodeRun = $false

    $paragraphs = $doc.Paragraphs
    foreach ($para in $paragraphs) {
        $range = $para.Range
        $text = $range.Text.TrimEnd([char]13, [char]7, [char]10, [char]11)

        # Detect horizontal rule (InlineShape HR, border, or box-drawing line)
        $isEmptyish = [string]::IsNullOrWhiteSpace($text) -or ($text -match '^\x01+$')
        if ($isEmptyish -or $text -match '^\u2500+$') {
            if ($inTargetSection) {
                $isHrule = $false
                # Check for InlineShape horizontal line
                try {
                    if ($range.InlineShapes.Count -gt 0) {
                        foreach ($sh in $range.InlineShapes) {
                            if ($sh.Type -eq 6) { $isHrule = $true; break }  # wdInlineShapeHorizontalLine
                        }
                    }
                } catch { }
                # Check for bottom border
                if (-not $isHrule) {
                    try { $isHrule = $para.Format.Borders.Item(4).LineStyle -ne 0 } catch { }
                }
                # Check for box-drawing fallback
                if (-not $isHrule -and $text -match '^\u2500+$') { $isHrule = $true }
                if ($isHrule) {
                    if ($inCodeRun) { Write-Host '```'; $inCodeRun = $false }
                    Write-Host "---"
                }
            }
            continue
        }

        # Detect heading and TOC styles
        $styleName = $para.Style.NameLocal
        $isHeading = $styleName -match "^Heading\s*(\d+)"
        $headingLevel = if ($isHeading) { [int]$Matches[1] } else { 0 }

        # Skip Table of Contents entries (redundant with actual headings, internal bookmark links don't work in markdown)
        if ($styleName -match '^TOC\s*\d+' -or $styleName -eq 'TOC Heading') { continue }

        # Section filtering
        if (-not [string]::IsNullOrEmpty($Section)) {
            $escapedSection = [WildcardPattern]::Escape($Section)
            if ($isHeading) {
                if ($text -like "*${escapedSection}*") {
                    $inTargetSection = $true
                    $targetLevel = $headingLevel
                } elseif ($inTargetSection -and $headingLevel -le $targetLevel) {
                    $inTargetSection = $false
                }
            }
            if (-not $inTargetSection) { continue }
        }

        # --- Inline formatting → markdown ---
        $boldState = $range.Bold
        $italicState = $range.Italic
        $strikeState = try { $range.Font.StrikeThrough } catch { 0 }
        $underState = try { $range.Font.Underline } catch { 0 }
        $supState = try { $range.Font.Superscript } catch { 0 }
        $subState = try { $range.Font.Subscript } catch { 0 }
        $fontName = try { $range.Font.Name } catch { "" }
        $hasMixedFont = [string]::IsNullOrEmpty($fontName)

        # Check if all formatting is uniform across the paragraph
        $allUniform = ($boldState -ne 9999999) -and ($italicState -ne 9999999) -and
                      ($strikeState -ne 9999999) -and ($underState -ne 9999999) -and
                      ($supState -ne 9999999) -and ($subState -ne 9999999) -and
                      (-not $hasMixedFont)

        if ($allUniform -and $boldState -eq 0 -and $italicState -eq 0 -and
            $strikeState -eq 0 -and ($underState -eq 0 -or $underState -eq $false) -and
            $supState -eq 0 -and $subState -eq 0) {
            # No formatting — use text as-is
        } elseif ($allUniform) {
            # Uniform formatting — wrap entire paragraph
            if ($supState -eq -1) { $text = "<sup>${text}</sup>" }
            if ($subState -eq -1) { $text = "<sub>${text}</sub>" }
            if ($strikeState -eq -1) { $text = "~~${text}~~" }
            if ($underState -ne 0 -and $underState -ne $false) { $text = "<u>${text}</u>" }
            if ($boldState -eq -1 -and $italicState -eq -1) { $text = "***${text}***" }
            elseif ($boldState -eq -1) { $text = "**${text}**" }
            elseif ($italicState -eq -1) { $text = "*${text}*" }
        } else {
            # Mixed formatting — iterate words and merge runs
            try {
                $words = $range.Words
                $result = ""
                $curBold = $false
                $curItalic = $false
                $curStrike = $false
                $curUnder = $false
                $curSup = $false
                $curSub = $false
                $curCode = $false
                $curRun = ""

                foreach ($w in $words) {
                    $wText = $w.Text
                    $wBold = ($w.Bold -eq -1)
                    $wItalic = ($w.Italic -eq -1)
                    $wStrike = try { $w.Font.StrikeThrough -eq -1 } catch { $false }
                    $wUnder = try { $w.Font.Underline -ne 0 -and $w.Font.Underline -ne $false } catch { $false }
                    $wSupRaw = try { $w.Font.Superscript } catch { 0 }
                    $wSubRaw = try { $w.Font.Subscript } catch { 0 }
                    $wFont = try { $w.Font.Name } catch { "" }
                    $wCode = [bool]($wFont -match '(?i)^(Consolas|Courier|Lucida Console|Fira Code|Source Code)')

                    # Mixed sub/sup within a word (e.g., "H2O") — drill into characters
                    if ($wSupRaw -eq 9999999 -or $wSubRaw -eq 9999999) {
                        if ($curRun) {
                            $flushed = $curRun
                            if ($curSup) { $flushed = "<sup>${flushed}</sup>" }
                            if ($curSub) { $flushed = "<sub>${flushed}</sub>" }
                            if ($curStrike) { $flushed = "~~${flushed}~~" }
                            if ($curUnder) { $flushed = "<u>${flushed}</u>" }
                            if ($curBold -and $curItalic) { $flushed = "***${flushed}***" }
                            elseif ($curBold) { $flushed = "**${flushed}**" }
                            elseif ($curItalic) { $flushed = "*${flushed}*" }
                            if ($curCode) { $flushed = "``${flushed}``" }
                            $result += $flushed
                            $curRun = ""
                        }
                        foreach ($ch in $w.Characters) {
                            $chText = $ch.Text
                            $chSup = try { $ch.Font.Superscript -eq -1 } catch { $false }
                            $chSub = try { $ch.Font.Subscript -eq -1 } catch { $false }
                            if ($chSup) { $result += "<sup>${chText}</sup>" }
                            elseif ($chSub) { $result += "<sub>${chText}</sub>" }
                            else { $result += $chText }
                        }
                        $curBold = $false; $curItalic = $false
                        $curStrike = $false; $curUnder = $false
                        $curSup = $false; $curSub = $false; $curCode = $false
                        continue
                    }

                    $wSup = ($wSupRaw -eq -1)
                    $wSub = ($wSubRaw -eq -1)

                    if ($wBold -ne $curBold -or $wItalic -ne $curItalic -or
                        $wStrike -ne $curStrike -or $wUnder -ne $curUnder -or
                        $wSup -ne $curSup -or $wSub -ne $curSub -or $wCode -ne $curCode) {
                        # Flush current run
                        if ($curRun) {
                            $flushed = $curRun
                            if ($curSup) { $flushed = "<sup>${flushed}</sup>" }
                            if ($curSub) { $flushed = "<sub>${flushed}</sub>" }
                            if ($curStrike) { $flushed = "~~${flushed}~~" }
                            if ($curUnder) { $flushed = "<u>${flushed}</u>" }
                            if ($curBold -and $curItalic) { $flushed = "***${flushed}***" }
                            elseif ($curBold) { $flushed = "**${flushed}**" }
                            elseif ($curItalic) { $flushed = "*${flushed}*" }
                            if ($curCode) { $flushed = "``${flushed}``" }
                            $result += $flushed
                        }
                        $curRun = $wText
                        $curBold = $wBold; $curItalic = $wItalic
                        $curStrike = $wStrike; $curUnder = $wUnder
                        $curSup = $wSup; $curSub = $wSub; $curCode = $wCode
                    } else {
                        $curRun += $wText
                    }
                }
                # Flush last run
                if ($curRun) {
                    $flushed = $curRun
                    if ($curSup) { $flushed = "<sup>${flushed}</sup>" }
                    if ($curSub) { $flushed = "<sub>${flushed}</sub>" }
                    if ($curStrike) { $flushed = "~~${flushed}~~" }
                    if ($curUnder) { $flushed = "<u>${flushed}</u>" }
                    if ($curBold -and $curItalic) { $flushed = "***${flushed}***" }
                    elseif ($curBold) { $flushed = "**${flushed}**" }
                    elseif ($curItalic) { $flushed = "*${flushed}*" }
                    if ($curCode) { $flushed = "``${flushed}``" }
                    $result += $flushed
                }
                $text = $result.TrimEnd([char]13, [char]7, [char]10, [char]11)
            } catch {
                # Fall back to plain text
            }
        }

        # --- Hyperlinks → markdown links ---
        try {
            $paraLinks = $range.Hyperlinks
            if ($paraLinks.Count -gt 0) {
                # Build replacements by position to avoid corrupting duplicate display text
                $linkReplacements = @()
                foreach ($hl in $paraLinks) {
                    $display = $hl.TextToDisplay
                    $addr = $hl.Address
                    # Skip internal-only links (empty address with bookmark SubAddress) - these are TOC refs, cross-refs, etc.
                    if ($display -and $addr -and -not ($addr -match '^#') -and $addr -ne $FilePath) {
                        $linkReplacements += @{ Display = $display; Addr = $addr; Start = $hl.Range.Start - $range.Start }
                    }
                }
                # Apply in reverse order so positions stay valid
                $linkReplacements = $linkReplacements | Sort-Object { $_.Start } -Descending
                foreach ($lr in $linkReplacements) {
                    $idx = $text.IndexOf($lr.Display)
                    if ($idx -ge 0) {
                        $text = $text.Substring(0, $idx) + "[$($lr.Display)]($($lr.Addr))" + $text.Substring($idx + $lr.Display.Length)
                    }
                }
            }
        } catch { }

        # --- Lists → markdown bullets/numbers ---
        $listPrefix = ""
        try {
            $lf = $range.ListFormat
            if ($lf.ListType -ne 0) {  # 0 = wdListNoNumbering
                $level = $lf.ListLevelNumber
                $indent = "  " * ($level - 1)
                $ls = $lf.ListString
                # Bullet: ListType 2 (simple) or ListString has no alphanumeric (special bullet char)
                if ($lf.ListType -eq 2 -or -not ($ls -match '[a-zA-Z0-9]')) {
                    $listPrefix = "${indent}- "
                } else {
                    $listPrefix = "${indent}${ls} "
                }
            }
        } catch { }

        # --- Output ---
        # Detect Quote style → blockquote
        $isQuote = $styleName -match '(?i)^(Quote|Block\s*Text|Intense\s*Quote)'
        # Detect monospace font → code block (reuses $fontName from formatting check)
        $isCode = ($fontName -match '(?i)^(Consolas|Courier|Lucida Console|Fira Code|Source Code)') -and -not $isHeading -and -not $isQuote

        if ($isHeading) {
            if ($inCodeRun) { Write-Host '```'; $inCodeRun = $false }
            $hPrefix = "#" * $headingLevel
            Write-Host "$hPrefix $text"
        } elseif ($isCode) {
            if (-not $inCodeRun) { Write-Host '```'; $inCodeRun = $true }
            Write-Host $text
        } elseif ($isQuote) {
            if ($inCodeRun) { Write-Host '```'; $inCodeRun = $false }
            Write-Host "> ${listPrefix}${text}"
        } else {
            if ($inCodeRun) { Write-Host '```'; $inCodeRun = $false }
            Write-Host "${listPrefix}${text}"
        }

        # MaxChars limit
        if ($MaxChars -gt 0) {
            $charCount += $text.Length
            if ($charCount -ge $MaxChars) {
                Write-Host "`n[Truncated at $MaxChars characters]"
                break
            }
        }
    }
    if ($inCodeRun) { Write-Host '```' }

} catch {
    Write-Error "Failed to read document: $($_.Exception.Message)"
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
    # Clean up per-run temp image directory
    if ($imgDir -and (Test-Path $imgDir)) {
        Remove-Item $imgDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
