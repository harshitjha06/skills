<#
.SYNOPSIS
    Searches SharePoint content using the SharePoint Search REST API.
.PARAMETER Query
    Search query text (required). Supports KQL syntax.
.PARAMETER Site
    Restrict search to a specific site URL (e.g., https://microsoft.sharepoint.com/sites/HRweb).
.PARAMETER FileType
    Filter results by file extension (e.g., pptx, docx, pdf, aspx).
.PARAMETER MaxResults
    Maximum number of results to return (default 10).
.PARAMETER StartRow
    Starting row index for pagination (default 0). Use with MaxResults to page through results.
#>
param(
    [Parameter(Mandatory)][string]$Query,
    [string]$Site = "",
    [string]$FileType = "",
    [int]$MaxResults = 10,
    [int]$StartRow = 0
)

. "$PSScriptRoot\SharePoint-Helper.ps1"

try {
    $session = New-SharePointSession

    $queryText = $Query
    if ($Site) {
        $queryText = "$queryText site:$Site"
    }

    $encoded = [Uri]::EscapeDataString($queryText)
    $props = "Title,Path,Description,LastModifiedTime,Author,HitHighlightedSummary"
    $url = "https://microsoft.sharepoint.com/_api/search/query?querytext='$encoded'&rowlimit=$MaxResults&startrow=$StartRow&selectproperties='$props'"

    if ($FileType) {
        $url += "&refinementfilters='FileType:equals(""$FileType"")'"
    }

    $result = Invoke-SharePointApi -Session $session -Url $url
    $rows = $result.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results
    $total = $result.d.query.PrimaryQueryResult.RelevantResults.TotalRows

    Write-Host "Found $total result(s) for `"$Query`"$(if ($Site) { " in $Site" })$(if ($FileType) { " (.$FileType)" })`n"

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Host "No results. Try broader search terms."
        exit 0
    }

    foreach ($row in $rows) {
        $cells = @{}
        $row.Cells.results | ForEach-Object { $cells[$_.Key] = $_.Value }

        $title = $cells['Title']
        $path = $cells['Path']
        $author = $cells['Author']
        $modified = $cells['LastModifiedTime']
        $summary = $cells['HitHighlightedSummary']

        if ($summary) {
            $summary = $summary -replace '<[^>]+>', ''
            if ($summary.Length -gt 200) {
                $summary = $summary.Substring(0, 200) + "..."
            }
        }

        Write-Host "Title: $title"
        Write-Host "Path:  $path"
        if ($author) { Write-Host "Author: $author" }
        if ($modified) { Write-Host "Modified: $modified" }
        if ($summary) { Write-Host "Summary: $summary" }
        Write-Host ""
    }

    if ($rows.Count -lt $total) {
        $nextStart = $StartRow + $rows.Count
        Write-Host "(Showing $($StartRow + 1)-$nextStart of $total. Use -StartRow $nextStart to see next page.)"
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'ECONNREFUSED|Unable to connect|No connection') {
        Write-Host "`nTeams CDP not available. Ensure:" -ForegroundColor Yellow
        Write-Host "1. WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is set to --remote-debugging-port=9222"
        Write-Host "2. Teams has been restarted after setting the variable"
    }
    exit 1
}
