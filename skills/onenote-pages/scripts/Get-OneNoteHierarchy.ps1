<#
.SYNOPSIS
    Lists all OneNote notebooks, sections, and pages.

.DESCRIPTION
    Uses the OneNote COM API (GetHierarchy) to retrieve the full notebook structure.
    Must be run with: powershell -STA -NoProfile -File Get-OneNoteHierarchy.ps1

.PARAMETER IncludeLinks
    If set, generates desktop (onenote:) and web links for each page. This adds 2 COM
    calls per page and may be slow for large notebook collections.

.EXAMPLE
    powershell -STA -NoProfile -File Get-OneNoteHierarchy.ps1
    powershell -STA -NoProfile -File Get-OneNoteHierarchy.ps1 -IncludeLinks
#>
param(
    [switch]$IncludeLinks
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
    $xml = ""
    try {
        # Scope 4 = hsPagesRecursive (full hierarchy including pages in section groups)
        $oneNote.GetHierarchy("", 4, [ref]$xml)
    } catch {
        Write-Error "GetHierarchy failed: $($_.Exception.Message)"
        exit 1
    }

    [xml]$parsed = $xml
    $ns = @{ one = "http://schemas.microsoft.com/office/onenote/2013/onenote" }

    $notebooks = Select-Xml -Xml $parsed -XPath "/one:Notebooks/one:Notebook" -Namespace $ns

    if (@($notebooks).Count -eq 0) {
        Write-Host "No notebooks found. Ensure notebooks are synced in OneNote."
        exit 0
    }

    foreach ($nb in $notebooks) {
        Write-Host "[Notebook] $($nb.Node.name) | ID: $($nb.Node.ID)"
        $sections = Select-Xml -Xml $nb.Node -XPath ".//one:Section[not(@isInRecycleBin)]" -Namespace $ns
        foreach ($s in $sections) {
            Write-Host "  [Section] $($s.Node.name) | ID: $($s.Node.ID)"
            $pages = Select-Xml -Xml $s.Node -XPath "one:Page" -Namespace $ns
            foreach ($pg in $pages) {
                $linkSuffix = ""
                if ($IncludeLinks) {
                    $pgDesktopLink = ""
                    $pgWebLink = ""
                    try {
                        $oneNote.GetHyperlinkToObject($pg.Node.ID, "", [ref]$pgDesktopLink)
                        $pgDesktopLink = $pgDesktopLink -replace '\{','%7B' -replace '\}','%7D'
                    } catch { Write-Verbose "GetHyperlinkToObject failed for '$($pg.Node.name)': $($_.Exception.Message)" }
                    try {
                        $oneNote.GetWebHyperlinkToObject($pg.Node.ID, "", [ref]$pgWebLink)
                        $pgWebLink = $pgWebLink -replace '\{','%7B' -replace '\}','%7D'
                    } catch { Write-Verbose "GetWebHyperlinkToObject failed for '$($pg.Node.name)': $($_.Exception.Message)" }
                    $linkSuffix = " | Desktop: $pgDesktopLink | Web: $pgWebLink"
                }
                Write-Host "    [Page] $($pg.Node.name) | ID: $($pg.Node.ID)$linkSuffix"
            }
        }
    }
} finally {
    if ($oneNote) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($oneNote) | Out-Null
    }
}
