<#
.SYNOPSIS
    Lists pages, document libraries, and folder contents on a SharePoint site.
.PARAMETER SiteUrl
    SharePoint site URL (e.g., https://microsoft.sharepoint.com/sites/HRweb). Required.
.PARAMETER Action
    What to list: pages (default), libraries, files, sites.
.PARAMETER FolderPath
    Server-relative folder path for the 'files' action (e.g., /sites/AzureCore/Shared Documents/folder).
.PARAMETER MaxResults
    Maximum number of items to return (default 20).
#>
param(
    [string]$SiteUrl = "",
    [ValidateSet('pages', 'libraries', 'files', 'sites')]
    [string]$Action = "pages",
    [string]$FolderPath = "",
    [int]$MaxResults = 20
)

. "$PSScriptRoot\SharePoint-Helper.ps1"

try {
    $session = New-SharePointSession

    if ($Action -ne 'sites' -and -not $SiteUrl) {
        Write-Host "ERROR: -SiteUrl is required for the '$Action' action." -ForegroundColor Red
        Write-Host "Use -Action sites to discover SharePoint sites first."
        exit 1
    }

    switch ($Action) {
        "sites" {
            # Search for SharePoint sites
            $searchTerm = if ($SiteUrl) { $SiteUrl } else { "*" }
            $encoded = [Uri]::EscapeDataString("contentclass:STS_Site $searchTerm")
            $url = "https://microsoft.sharepoint.com/_api/search/query?querytext='$encoded'&rowlimit=$MaxResults&selectproperties='Title,Path,Description,LastModifiedTime,WebTemplate'"
            $result = Invoke-SharePointApi -Session $session -Url $url

            $rows = $result.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results
            $total = $result.d.query.PrimaryQueryResult.RelevantResults.TotalRows

            if (-not $rows -or $rows.Count -eq 0) {
                Write-Host "No sites found. Try a different search term."
                exit 0
            }

            Write-Host "=== SharePoint Sites ($($rows.Count) of $total) ==="
            Write-Host ""
            foreach ($row in $rows) {
                $cells = @{}
                $row.Cells.results | ForEach-Object { $cells[$_.Key] = $_.Value }
                Write-Host "  $($cells['Title'])"
                Write-Host "    URL: $($cells['Path'])"
                if ($cells['Description']) { Write-Host "    Description: $($cells['Description'])" }
                Write-Host ""
            }
        }

        "pages" {
            $url = "$SiteUrl/_api/web/lists/getbytitle('Site Pages')/items?`$select=Title,FileRef,Modified&`$top=$MaxResults&`$orderby=Modified desc"
            $result = Invoke-SharePointApi -Session $session -Url $url

            $items = $result.d.results
            if (-not $items -or $items.Count -eq 0) {
                Write-Host "No site pages found."
                exit 0
            }

            Write-Host "=== Site Pages ($($items.Count)) ==="
            Write-Host ""
            foreach ($item in $items) {
                $modified = if ($item.Modified) { "$($item.Modified)".Substring(0, [Math]::Min(19, "$($item.Modified)".Length)) } else { "" }
                Write-Host "  $($item.Title)"
                Write-Host "    Path: $($item.FileRef)"
                Write-Host "    Modified: $modified"
                Write-Host ""
            }
        }

        "libraries" {
            $url = "$SiteUrl/_api/web/lists?`$filter=BaseTemplate eq 101&`$select=Title,ItemCount,LastItemModifiedDate&`$top=$MaxResults"
            $result = Invoke-SharePointApi -Session $session -Url $url

            $libs = $result.d.results
            if (-not $libs -or $libs.Count -eq 0) {
                Write-Host "No document libraries found."
                exit 0
            }

            Write-Host "=== Document Libraries ($($libs.Count)) ==="
            Write-Host ""
            foreach ($lib in $libs) {
                Write-Host "  $($lib.Title) ($($lib.ItemCount) items)"
                Write-Host "    Last modified: $($lib.LastItemModifiedDate)"
                Write-Host ""
            }
        }

        "files" {
            if (-not $FolderPath) {
                Write-Host "ERROR: -FolderPath is required for the 'files' action." -ForegroundColor Red
                Write-Host "Example: -FolderPath '/sites/AzureCore/Shared Documents/My Folder'"
                exit 1
            }

            $encodedPath = [Uri]::EscapeDataString($FolderPath)
            $url = "$SiteUrl/_api/web/GetFolderByServerRelativeUrl('$encodedPath')"

            # Get subfolders and files
            $foldersUrl = "$url/Folders?`$select=Name,ItemCount,TimeLastModified&`$top=$MaxResults"
            $filesUrl = "$url/Files?`$select=Name,Length,TimeLastModified&`$top=$MaxResults"

            Write-Host "=== $FolderPath ==="
            Write-Host ""

            try {
                $folders = Invoke-SharePointApi -Session $session -Url $foldersUrl
                foreach ($f in $folders.d.results) {
                    if ($f.Name -eq 'Forms') { continue }
                    Write-Host "  [DIR] $($f.Name) ($($f.ItemCount) items)"
                }
            }
            catch { }

            try {
                $files = Invoke-SharePointApi -Session $session -Url $filesUrl
                foreach ($f in $files.d.results) {
                    $sizeKB = [Math]::Round($f.Length / 1024)
                    $modified = if ($f.TimeLastModified) { "$($f.TimeLastModified)".Substring(0, [Math]::Min(19, "$($f.TimeLastModified)".Length)) } else { "" }
                    Write-Host "  $($f.Name) (${sizeKB}KB, $modified)"
                }
            }
            catch { }

            Write-Host ""
        }
    }

    # Show site info
    if ($Action -eq "pages" -or $Action -eq "libraries") {
        try {
            $siteInfo = Invoke-SharePointApi -Session $session -Url "$SiteUrl/_api/web?`$select=Title,Description"
            Write-Host "Site: $($siteInfo.d.Title)"
            if ($siteInfo.d.Description) {
                Write-Host "Description: $($siteInfo.d.Description)"
            }
        }
        catch { }
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
