<#
.SYNOPSIS
    Searches OneNote pages by keyword across all synced notebooks.

.DESCRIPTION
    Uses the OneNote COM API (FindPages) to search page titles and body content.
    Must be run with: powershell -STA -NoProfile -File Search-OneNotePage.ps1 -SearchTerm <term>

.PARAMETER SearchTerm
    The keyword or phrase to search for. Case-insensitive, searches titles and body text.

.EXAMPLE
    powershell -STA -NoProfile -File Search-OneNotePage.ps1 -SearchTerm "Kusto table"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SearchTerm,

    [switch]$TitleOnly,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxResults = 0
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
    $results = ""
    try {
        $oneNote.FindPages("", $SearchTerm, [ref]$results)
    } catch {
        Write-Error "FindPages failed: $($_.Exception.Message)"
        exit 1
    }

    [xml]$parsed = $results
    $ns = @{ one = "http://schemas.microsoft.com/office/onenote/2013/onenote" }

    $pages = Select-Xml -Xml $parsed -XPath "//one:Page" -Namespace $ns

    if (@($pages).Count -eq 0) {
        Write-Host "No pages found matching '$SearchTerm'"
        exit 0
    }

    $output = $pages | ForEach-Object {
        $p = $_.Node
        $section = $p.ParentNode
        $notebook = $section.ParentNode
        while ($notebook.LocalName -ne "Notebook" -and $notebook.ParentNode) {
            $notebook = $notebook.ParentNode
        }
        $desktopLink = ""
        $webLink = ""
        try {
            $oneNote.GetHyperlinkToObject($p.ID, "", [ref]$desktopLink)
            $desktopLink = $desktopLink -replace '\{','%7B' -replace '\}','%7D'
        } catch { Write-Verbose "GetHyperlinkToObject failed: $($_.Exception.Message)"; $desktopLink = "" }
        try {
            $oneNote.GetWebHyperlinkToObject($p.ID, "", [ref]$webLink)
            $webLink = $webLink -replace '\{','%7B' -replace '\}','%7D'
        } catch { Write-Verbose "GetWebHyperlinkToObject failed: $($_.Exception.Message)"; $webLink = "" }
        [PSCustomObject]@{
            Notebook    = $notebook.name
            Section     = $section.name
            Page        = $p.name
            Created     = $p.dateTime
            Modified    = $p.lastModifiedTime
            PageID      = $p.ID
            DesktopLink = $desktopLink
            WebLink     = $webLink
        }
    }

    if ($TitleOnly) {
        $output = $output | Where-Object { $_.Page -match [regex]::Escape($SearchTerm) }
    }

    Write-Host "Found $(@($output).Count) page(s) matching '$SearchTerm':`n"

    if ($MaxResults -gt 0) {
        $output = $output | Select-Object -First $MaxResults
    }

    $output | Format-List
} finally {
    if ($oneNote) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($oneNote) | Out-Null
    }
}
