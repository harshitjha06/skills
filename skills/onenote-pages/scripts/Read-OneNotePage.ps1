<#
.SYNOPSIS
    Reads the full content of a OneNote page by its page ID.

.DESCRIPTION
    Uses the OneNote COM API (GetPageContent) to fetch page content as XML, then extracts
    text and images in document order. Images are saved to a temp directory and their paths
    are printed inline. Must be run with: powershell -STA -NoProfile -File Read-OneNotePage.ps1 -PageID <id>

.PARAMETER PageID
    The OneNote page ID (obtained from Search-OneNotePage.ps1).

.PARAMETER SkipImages
    If set, skips image extraction (faster for text-only analysis).

.EXAMPLE
    powershell -STA -NoProfile -File Read-OneNotePage.ps1 -PageID "{C0A20C63-6A05-0FD8-16F7-42BFBF81ED9D}{1}{E195...}"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PageID,

    [switch]$SkipImages
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$oneNote = $null

try {
    $oneNote = New-Object -ComObject OneNote.Application
} catch {
    Write-Error "Failed to create OneNote COM object. Ensure OneNote desktop app is installed and running."
    exit 1
}

try {

$pageXml = ""
try {
    $oneNote.GetPageContent($PageID, [ref]$pageXml)
} catch {
    Write-Error "GetPageContent failed: $($_.Exception.Message)"
    exit 1
}

[xml]$parsed = $pageXml
$ns = @{ one = "http://schemas.microsoft.com/office/onenote/2013/onenote" }

# Extract title (may have multiple text runs)
$title = Select-Xml -Xml $parsed -XPath "//one:Title//one:T" -Namespace $ns
$titleText = ($title | ForEach-Object { $_.Node.InnerText }) -join ''
Write-Host "=== $titleText ==="

# Extract page metadata
$pageNode = Select-Xml -Xml $parsed -XPath "//one:Page" -Namespace $ns
if ($pageNode) {
    $created = $pageNode.Node.dateTime
    $modified = $pageNode.Node.lastModifiedTime
    if ($created) { Write-Host "Created:  $created" }
    if ($modified) { Write-Host "Modified: $modified" }
}

# Generate page links
try {
    $desktopLink = ""
    $oneNote.GetHyperlinkToObject($PageID, "", [ref]$desktopLink)
    $desktopLink = $desktopLink -replace '\{','%7B' -replace '\}','%7D'
    Write-Host "Desktop:  $desktopLink"
} catch { Write-Verbose "GetHyperlinkToObject failed: $($_.Exception.Message)" }
try {
    $webLink = ""
    $oneNote.GetWebHyperlinkToObject($PageID, "", [ref]$webLink)
    $webLink = $webLink -replace '\{','%7B' -replace '\}','%7D'
    Write-Host "Web:      $webLink"
} catch { Write-Verbose "GetWebHyperlinkToObject failed: $($_.Exception.Message)" }
Write-Host ""

Add-Type -AssemblyName System.Web

# Prepare image/attachment output directory
$imgDir = Join-Path $env:TEMP "onenote-pages"
if (Test-Path -LiteralPath $imgDir) {
    Remove-Item -LiteralPath $imgDir -Recurse -Force
}
if (-not (Test-Path -LiteralPath $imgDir)) {
    New-Item -ItemType Directory -Path $imgDir -Force | Out-Null
}
$imgIndex = 0
$oneNoteCache = Join-Path $env:LOCALAPPDATA "Microsoft\OneNote"
$cacheRoot = $oneNoteCache.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

# Build tag definition lookup from page-level TagDef elements
$tagDefs = @{}
$tagDefNodes = Select-Xml -Xml $parsed -XPath "//one:TagDef" -Namespace $ns
foreach ($td in $tagDefNodes) {
    $tagDefs[$td.Node.index] = $td.Node.name
}

# Convert OneNote HTML-rich text node content to plain text with markdown links
# Detects inline Consolas spans and converts them to backtick-wrapped inline code
function ConvertTo-PlainText($innerText) {
    $t = [regex]::Replace($innerText, '<a\s[^>]*href="([^"]*)"[^>]*>(.*?)</a>', '[$2]($1)')
    $t = [regex]::Replace($t, '<span\s[^>]*font-family:\s*Consolas[^>]*>([^<]*)</span>', '`$1`')
    $t = $t -replace '<[^>]+>', ''
    [System.Web.HttpUtility]::HtmlDecode($t)
}

# Check if an OE element is a full-line Consolas code block element
# OneNote may store the Consolas style as an OE-level style attribute (not in the T inner text)
function Test-CodeBlockOE($oeNode) {
    $textRuns = Select-Xml -Xml $oeNode -XPath "one:T" -Namespace $script:ns
    if (@($textRuns).Count -ne 1) { return $false }
    # Check OE-level style attribute (OneNote rewrites inline spans to OE style)
    $oeStyle = $oeNode.GetAttribute("style")
    if ($oeStyle -match 'font-family:\s*Consolas') { return $true }
    # Also check if T inner text is wrapped in a Consolas span (before OneNote rewrites it)
    $inner = $textRuns[0].Node.InnerText
    return ($inner -match '^\s*<span\s[^>]*font-family:\s*Consolas[^>]*>[^<]*</span>\s*$')
}

# Extract the text content from a Consolas code block OE
function Get-CodeBlockText($oeNode) {
    $textRuns = Select-Xml -Xml $oeNode -XPath "one:T" -Namespace $script:ns
    $inner = $textRuns[0].Node.InnerText
    # If OE has Consolas style, the T inner text is plain text (OneNote stripped the span)
    $oeStyle = $oeNode.GetAttribute("style")
    if ($oeStyle -match 'font-family:\s*Consolas') {
        return [System.Web.HttpUtility]::HtmlDecode($inner)
    }
    # Fallback: extract from span tag
    $m = [regex]::Match($inner, '<span\s[^>]*font-family:\s*Consolas[^>]*>([^<]*)</span>')
    if ($m.Success) {
        return [System.Web.HttpUtility]::HtmlDecode($m.Groups[1].Value)
    }
    return $inner
}

# Walk page body in document order to interleave text and images
# We traverse OEChildren and process OE elements; images and attachments are handled as children of each OE.
$body = Select-Xml -Xml $parsed -XPath "//one:Outline/one:OEChildren" -Namespace $ns

function Process-OEChildren($node, [int]$depth = 0) {
    $indent = '  ' * $depth
    $children = @($node.ChildNodes)
    $i = 0
    while ($i -lt $children.Count) {
        $child = $children[$i]
        $localName = $child.LocalName

        if ($localName -eq "OE") {
            # Detect consecutive code block OEs and group them into a fenced code block.
            # The inner while loop advances $i past all code OEs; continue skips the
            # outer $i++ so the next iteration picks up the first non-code element.
            if (Test-CodeBlockOE $child) {
                Write-Host "${indent}``````"
                while ($i -lt $children.Count -and $children[$i].LocalName -eq "OE" -and (Test-CodeBlockOE $children[$i])) {
                    $codeText = Get-CodeBlockText $children[$i]
                    Write-Host "${indent}${codeText}"
                    $i++
                }
                Write-Host "${indent}``````"
                continue
            }

            # Check for tags (to-do, stars, etc.) on this OE
            $tagPrefix = ""
            $tag = Select-Xml -Xml $child -XPath "one:Tag" -Namespace $ns
            if ($tag) {
                $tagNode = $tag[0].Node
                $tagName = $script:tagDefs[$tagNode.index]
                if ($tagName -eq "To Do") {
                    if ($tagNode.completed -eq "true") { $tagPrefix = "[x] " }
                    else { $tagPrefix = "[ ] " }
                } elseif ($tagName) {
                    $tagPrefix = "[$tagName] "
                }
            }

            # Check for table inside this OE
            $table = Select-Xml -Xml $child -XPath "one:Table" -Namespace $ns
            if ($table) {
                $rows = Select-Xml -Xml $table.Node -XPath "one:Row" -Namespace $ns
                $rowIndex = 0
                foreach ($row in $rows) {
                    $cells = Select-Xml -Xml $row.Node -XPath "one:Cell" -Namespace $ns
                    $cellTexts = @()
                    foreach ($cell in $cells) {
                        $tNodes = Select-Xml -Xml $cell.Node -XPath ".//one:T" -Namespace $ns
                        $cellText = ($tNodes | ForEach-Object { ConvertTo-PlainText $_.Node.InnerText }) -join ' '
                        $cellTexts += $cellText
                    }
                    Write-Host ("${indent}| {0} |" -f ($cellTexts -join ' | '))
                    if ($rowIndex -eq 0) {
                        $sep = ($cellTexts | ForEach-Object { '---' }) -join ' | '
                        Write-Host ("${indent}| {0} |" -f $sep)
                    }
                    $rowIndex++
                }
            } else {
                # Check for text runs — only direct one:T children, not inside nested OEChildren
                $textRuns = Select-Xml -Xml $child -XPath "one:T" -Namespace $ns
                foreach ($t in $textRuns) {
                    $text = $t.Node.InnerText
                    if ($text.Trim()) {
                        $text = ConvertTo-PlainText $text
                        Write-Host "${indent}${tagPrefix}${text}"
                    }
                }
            }

            # Check for images directly in this OE (not nested)
            $images = Select-Xml -Xml $child -XPath "one:Image" -Namespace $ns
            foreach ($img in $images) {
                if (-not $SkipImages) {
                    $cbNode = Select-Xml -Xml $img.Node -XPath "one:CallbackID" -Namespace $ns
                    if ($cbNode) {
                        $script:imgIndex++
                        $cbId = $cbNode.Node.callbackID
                        try {
                            $binaryData = ""
                            $oneNote.GetBinaryPageContent($PageID, $cbId, [ref]$binaryData)
                            $bytes = [Convert]::FromBase64String($binaryData)

                            # Detect format from magic bytes
                            $ext = "bin"
                            if ($bytes -and $bytes.Length -ge 2) {
                                if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) { $ext = "png" }
                                elseif ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { $ext = "jpg" }
                                elseif ($bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49) { $ext = "gif" }
                            }

                            $imgPath = Join-Path $imgDir "onenote-img-$($script:imgIndex.ToString('D3')).$ext"
                            [System.IO.File]::WriteAllBytes($imgPath, $bytes)
                            Write-Host ("{0}[IMAGE: {1}]" -f $indent, $imgPath)
                        } catch {
                            Write-Host ("{0}[IMAGE: extraction failed - {1}]" -f $indent, $_.Exception.Message)
                        }
                    }
                } else {
                    Write-Host "${indent}[IMAGE: skipped]"
                }
            }

            # Check for file attachments directly in this OE
            $attachments = Select-Xml -Xml $child -XPath "one:InsertedFile" -Namespace $ns
            foreach ($att in $attachments) {
                $rawName = [System.IO.Path]::GetFileName($att.Node.preferredName)
                $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
                $fileName = ($rawName.ToCharArray() | ForEach-Object { if ($_ -in $invalidChars) { '_' } else { $_ } }) -join ''
                $cachePath = $att.Node.pathCache
                $resolvedCache = if ($cachePath) { [System.IO.Path]::GetFullPath($cachePath) } else { "" }
                if ($fileName -and $cachePath -and (Test-Path -LiteralPath $cachePath) -and $resolvedCache.StartsWith($cacheRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    try {
                        $destPath = Join-Path $imgDir $fileName
                        if (Test-Path -LiteralPath $destPath) {
                            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                            $ext = [System.IO.Path]::GetExtension($fileName)
                            $script:imgIndex++
                            $destPath = Join-Path $imgDir ("{0}-{1}{2}" -f $baseName, $script:imgIndex.ToString('D3'), $ext)
                        }
                        Copy-Item -LiteralPath $cachePath -Destination $destPath -Force
                        Write-Host ("{0}[ATTACHMENT: {1}]" -f $indent, $destPath)
                    } catch {
                        Write-Host ("{0}[ATTACHMENT: {1} - extraction failed: {2}]" -f $indent, $fileName, $_.Exception.Message)
                    }
                } elseif ($fileName) {
                    Write-Host ("{0}[ATTACHMENT: {1} - cache file not found]" -f $indent, $fileName)
                }
            }

            # Recurse into nested OEChildren
            $nested = Select-Xml -Xml $child -XPath "one:OEChildren" -Namespace $ns
            foreach ($n in $nested) {
                Process-OEChildren $n.Node ($depth + 1)
            }
        }
        $i++
    }
}

foreach ($oeChildren in $body) {
    Process-OEChildren $oeChildren.Node 0
}

} finally {
    if ($oneNote) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($oneNote) | Out-Null
    }
}
