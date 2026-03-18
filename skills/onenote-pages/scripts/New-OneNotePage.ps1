<#
.SYNOPSIS
    Creates a new OneNote page with optional markdown content.

.DESCRIPTION
    Uses the OneNote COM API (CreateNewPage + UpdatePageContent) to create a new page
    in a specified section. Content can be provided as a markdown string or a markdown file.
    Must be run with: powershell -STA -NoProfile -File New-OneNotePage.ps1 -SectionId <id> -Title <title>

.PARAMETER SectionId
    The OneNote section ID to create the page in (obtained from Get-OneNoteHierarchy.ps1).

.PARAMETER Title
    The title for the new page.

.PARAMETER Content
    Optional markdown content for the page body.

.PARAMETER InputFile
    Optional path to a markdown (.md) file to use as page content.

.EXAMPLE
    powershell -STA -NoProfile -File New-OneNotePage.ps1 -SectionId "{ABC...}" -Title "Meeting Notes"

.EXAMPLE
    powershell -STA -NoProfile -File New-OneNotePage.ps1 -SectionId "{ABC...}" -Title "Notes" -Content "# Summary`n- Item 1`n- Item 2"

.EXAMPLE
    powershell -STA -NoProfile -File New-OneNotePage.ps1 -SectionId "{ABC...}" -Title "Report" -InputFile "C:\notes.md"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SectionId,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Content,

    [string]$InputFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Content -and $InputFile) {
    Write-Error "Specify either -Content or -InputFile, not both."
    exit 1
}

if ($InputFile) {
    if (-not (Test-Path -LiteralPath $InputFile)) {
        Write-Error "Input file not found: $InputFile"
        exit 1
    }
    $Content = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
}

$xmlns = "http://schemas.microsoft.com/office/onenote/2013/onenote"

# Sanitize text for safe CDATA embedding (]]> breaks CDATA sections)
function Protect-CData([string]$text) {
    $text -replace '\]\]>', ']]]]><![CDATA[>'
}

function Format-InlineText {
    param([string]$text)

    # Extract inline code to placeholders to protect from further formatting
    $codePattern = [regex]'`(.+?)`'
    $codeMatches = $codePattern.Matches($text)
    $codeReplacements = @{}

    for ($i = $codeMatches.Count - 1; $i -ge 0; $i--) {
        $m = $codeMatches[$i]
        $placeholder = "%%CODE_${i}%%"
        $escapedCode = $m.Groups[1].Value -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
        $codeReplacements[$placeholder] = '<span style="font-family:Consolas;font-size:10pt;background-color:#f4f4f4">' + $escapedCode + '</span>'
        $text = $text.Remove($m.Index, $m.Length).Insert($m.Index, $placeholder)
    }

    # HTML-encode &, <, > in the remaining text so OneNote's HTML-inside-CDATA parser
    # doesn't interpret them as entities or tags. Placeholders (%%CODE_N%%) contain no
    # special chars so they survive encoding. Must run before bold/italic/link regexes
    # since those inject HTML tags (<b>, <i>, <a>) that should NOT be encoded.
    $text = $text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'

    $text = [regex]::Replace($text, '\*\*(.+?)\*\*', '<b>$1</b>')
    $text = [regex]::Replace($text, '(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', '<i>$1</i>')
    $text = [regex]::Replace($text, '~~(.+?)~~', '<s>$1</s>')
    # Escape special chars in URLs for safe HTML attribute embedding
    $text = [regex]::Replace($text, '\[([^\]]+)\]\(([^)]+)\)', {
        param($m)
        $linkText = $m.Groups[1].Value
        $linkUrl = $m.Groups[2].Value -replace '&', '&amp;' -replace '"', '&quot;' -replace '<', '&lt;' -replace '>', '&gt;'
        "<a href=`"$linkUrl`">$linkText</a>"
    })

    foreach ($key in $codeReplacements.Keys) {
        $text = $text.Replace($key, $codeReplacements[$key])
    }

    return $text
}

function Build-NestedListXml {
    param(
        [array]$Items,
        [int]$StartIndex,
        [int]$BaseLevel
    )
    $xml = ""
    $i = $StartIndex
    while ($i -lt $Items.Count) {
        $item = $Items[$i]
        if ($item.Level -lt $BaseLevel) { break }
        if ($item.Level -eq $BaseLevel) {
            if ($item.Type -eq 'bullet') {
                $listTag = '<one:List><one:Bullet bullet="2" fontSize="11.0" /></one:List>'
            } else {
                $listTag = '<one:List><one:Number numberSequence="1" numberFormat="##." fontSize="11.0" /></one:List>'
            }
            $formattedText = Protect-CData (Format-InlineText $item.Text)
            if (($i + 1) -lt $Items.Count -and $Items[$i + 1].Level -gt $BaseLevel) {
                $childResult = Build-NestedListXml -Items $Items -StartIndex ($i + 1) -BaseLevel $Items[$i + 1].Level
                $xml += "<one:OE>${listTag}<one:T><![CDATA[${formattedText}]]></one:T><one:OEChildren>$($childResult.Xml)</one:OEChildren></one:OE>"
                $i = $childResult.NextIndex
            } else {
                $xml += "<one:OE>${listTag}<one:T><![CDATA[${formattedText}]]></one:T></one:OE>"
                $i++
            }
        } else {
            break
        }
    }
    return @{ Xml = $xml; NextIndex = $i }
}

function Build-TableXml {
    param([string[]]$TableLines)
    $dataRows = @()
    foreach ($tl in $TableLines) {
        $trimmed = $tl.Trim()
        if ($trimmed -match '^[\|\-\:\s]+$') { continue }
        $cells = $trimmed.TrimStart('|').TrimEnd('|') -split '\|' | ForEach-Object { $_.Trim() }
        $dataRows += ,@($cells)
    }
    if ($dataRows.Count -eq 0) { return "" }
    $colCount = $dataRows[0].Count
    $xml = '<one:Table bordersVisible="true" hasHeaderRow="true"><one:Columns>'
    for ($c = 0; $c -lt $colCount; $c++) {
        $xml += "<one:Column index=`"$c`" width=`"120`" />"
    }
    $xml += '</one:Columns>'
    for ($r = 0; $r -lt $dataRows.Count; $r++) {
        $xml += '<one:Row>'
        foreach ($cell in $dataRows[$r]) {
            $formattedCell = Protect-CData (Format-InlineText $cell)
            if ($r -eq 0) { $formattedCell = "<b>$formattedCell</b>" }
            $xml += "<one:Cell><one:OEChildren><one:OE><one:T><![CDATA[$formattedCell]]></one:T></one:OE></one:OEChildren></one:Cell>"
        }
        $xml += '</one:Row>'
    }
    $xml += '</one:Table>'
    return "<one:OE>$xml</one:OE>"
}

function ConvertTo-OneNoteXml {
    param([string]$markdown)
    if ([string]::IsNullOrWhiteSpace($markdown)) { return "" }

    $lines = $markdown -split "`r?`n"
    $sb = New-Object System.Text.StringBuilder
    $inCodeBlock = $false
    $listItems = [System.Collections.ArrayList]::new()
    $tableLines = [System.Collections.ArrayList]::new()

    $flushList = {
        if ($listItems.Count -gt 0) {
            # Use the first item's level as base so processing always starts successfully
            $baseLevel = $listItems[0].Level
            $result = Build-NestedListXml -Items $listItems.ToArray() -StartIndex 0 -BaseLevel $baseLevel
            [void]$sb.Append($result.Xml)
            $listItems.Clear()
        }
    }

    $flushTable = {
        if ($tableLines.Count -gt 0) {
            $tableXml = Build-TableXml -TableLines $tableLines.ToArray()
            if ($tableXml) { [void]$sb.Append($tableXml) }
            $tableLines.Clear()
        }
    }

    foreach ($line in $lines) {
        # Code block toggle
        if ($line -match '^```') {
            & $flushList
            & $flushTable
            $inCodeBlock = -not $inCodeBlock
            continue
        }

        if ($inCodeBlock) {
            $escapedLine = $line -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
            $escapedLine = Protect-CData $escapedLine
            [void]$sb.Append("<one:OE><one:T><![CDATA[<span style=`"font-family:Consolas;font-size:10pt`">$escapedLine</span>]]></one:T></one:OE>")
            continue
        }

        # Table line
        if ($line -match '^\s*\|') {
            & $flushList
            [void]$tableLines.Add($line)
            continue
        } elseif ($tableLines.Count -gt 0) {
            & $flushTable
        }

        # Bullet list item — capture $Matches before any flush calls
        if ($line -match '^(\s*)([-*])\s+(.*)$') {
            $indent = $Matches[1]
            $itemText = $Matches[3]
            & $flushTable
            $level = [math]::Floor($indent.Replace("`t", "  ").Length / 2)
            [void]$listItems.Add(@{ Level = $level; Type = 'bullet'; Text = $itemText })
            continue
        }

        # Numbered list item
        if ($line -match '^(\s*)\d+\.\s+(.*)$') {
            $indent = $Matches[1]
            $itemText = $Matches[2]
            & $flushTable
            $level = [math]::Floor($indent.Replace("`t", "  ").Length / 2)
            [void]$listItems.Add(@{ Level = $level; Type = 'number'; Text = $itemText })
            continue
        }

        # Non-list, non-table line
        & $flushList
        & $flushTable

        # Empty line
        if ([string]::IsNullOrWhiteSpace($line)) {
            [void]$sb.Append("<one:OE><one:T><![CDATA[]]></one:T></one:OE>")
            continue
        }

        # Heading
        if ($line -match '^(#{1,3})\s+(.*)$') {
            $headingLevel = $Matches[1].Length
            $headingText = Protect-CData (Format-InlineText $Matches[2])
            switch ($headingLevel) {
                1 { $style = "font-size:16pt;font-weight:bold" }
                2 { $style = "font-size:13pt;font-weight:bold" }
                3 { $style = "font-size:11pt;font-weight:bold" }
            }
            [void]$sb.Append("<one:OE><one:T><![CDATA[<span style=`"$style`">$headingText</span>]]></one:T></one:OE>")
            continue
        }

        # Image on its own line
        if ($line -match '^\!\[([^\]]*)\]\(([^)]+)\)\s*$') {
            $alt = $Matches[1]
            $imgPath = $Matches[2]
            # Validate image path: must be local (no UNC), must exist, must have image extension
            $validExts = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.ico')
            $imgExt = [System.IO.Path]::GetExtension($imgPath).ToLower()
            $isUNC = $imgPath.StartsWith('\\')
            if (-not $isUNC -and (Test-Path -LiteralPath $imgPath) -and ($imgExt -in $validExts)) {
                $bytes = [System.IO.File]::ReadAllBytes($imgPath)
                $base64 = [Convert]::ToBase64String($bytes)
                [void]$sb.Append("<one:OE><one:Image><one:Data>$base64</one:Data></one:Image></one:OE>")
            } else {
                $safeAlt = Protect-CData $alt
                $safeImgPath = Protect-CData $imgPath
                [void]$sb.Append("<one:OE><one:T><![CDATA[![$safeAlt]($safeImgPath)]]></one:T></one:OE>")
            }
            continue
        }

        # Plain text
        $formattedLine = Protect-CData (Format-InlineText $line)
        [void]$sb.Append("<one:OE><one:T><![CDATA[$formattedLine]]></one:T></one:OE>")
    }

    # Final flush
    & $flushList
    & $flushTable

    return $sb.ToString()
}

# --- Main script ---

$oneNote = $null
try {
    $oneNote = New-Object -ComObject OneNote.Application
} catch {
    Write-Error "Failed to create OneNote COM object. Ensure OneNote desktop app is installed and running."
    exit 1
}

try {
    $newPageId = ""
    try {
        $oneNote.CreateNewPage($SectionId, [ref]$newPageId)
    } catch {
        Write-Error "CreateNewPage failed: $($_.Exception.Message)"
        exit 1
    }

    $bodyXml = ""
    if ($Content) {
        $bodyXml = ConvertTo-OneNoteXml $Content
    }

    $safeTitle = $Title -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '\]\]>', ']]]]><![CDATA[>'
    $pageXml = "<one:Page xmlns:one=`"$xmlns`" ID=`"$newPageId`">"
    $pageXml += "<one:Title><one:OE><one:T><![CDATA[$safeTitle]]></one:T></one:OE></one:Title>"
    if ($bodyXml) {
        $pageXml += "<one:Outline><one:OEChildren>$bodyXml</one:OEChildren></one:Outline>"
    }
    $pageXml += "</one:Page>"

    try {
        $oneNote.UpdatePageContent($pageXml)
    } catch {
        Write-Error "UpdatePageContent failed: $($_.Exception.Message)"
        exit 1
    }

    Write-Host "Page created successfully."
    Write-Host "PageID: $newPageId"
} finally {
    if ($oneNote) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($oneNote) | Out-Null
    }
}
