<#
.SYNOPSIS
    Reads a SharePoint site page and outputs its text content.
.PARAMETER Url
    Full SharePoint page URL (e.g., https://microsoft.sharepoint.com/sites/HRweb/SitePages/DTOPolicy.aspx).
.PARAMETER SiteUrl
    SharePoint site URL (used with -PagePath instead of -Url).
.PARAMETER PagePath
    Server-relative page path within the site (e.g., SitePages/DTOPolicy.aspx).
#>
param(
    [string]$Url = "",
    [string]$SiteUrl = "",
    [string]$PagePath = ""
)

. "$PSScriptRoot\SharePoint-Helper.ps1"

try {
    if (-not $Url -and (-not $SiteUrl -or -not $PagePath)) {
        Write-Host "Usage:"
        Write-Host "  .\Read-SharePointPage.ps1 -Url <full page URL>"
        Write-Host "  .\Read-SharePointPage.ps1 -SiteUrl <site URL> -PagePath <relative path>"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\Read-SharePointPage.ps1 -Url 'https://microsoft.sharepoint.com/sites/HRweb/SitePages/DTOPolicy.aspx'"
        Write-Host "  .\Read-SharePointPage.ps1 -SiteUrl 'https://microsoft.sharepoint.com/sites/HRweb' -PagePath 'SitePages/DTOPolicy.aspx'"
        exit 1
    }

    if ($Url) {
        $resolved = Resolve-SharePointUrl $Url
        $SiteUrl = $resolved.SiteUrl
        $PagePath = $resolved.PagePath
        if (-not $PagePath) {
            throw "Could not extract page path from URL. Ensure the URL points to a SitePages/*.aspx page."
        }
        # Strip leading slash for the API call
        $PagePath = $PagePath.TrimStart('/')
    }

    $session = New-SharePointSession

    Write-Host "Reading: $SiteUrl/$PagePath`n"

    # Use GetByUrl to get clean JSON canvas content
    $apiUrl = "$SiteUrl/_api/sitepages/pages/GetByUrl('$PagePath')?`$select=Title,Description,CanvasContent1,Modified,AuthorByline"
    $page = Invoke-SharePointApi -Session $session -Url $apiUrl

    $title = $page.d.Title
    $description = $page.d.Description
    $modified = $page.d.Modified
    $canvas = $page.d.CanvasContent1

    Write-Host "=== $title ==="
    if ($modified) { Write-Host "Last modified: $modified" }
    if ($description) { Write-Host "Description: $description" }
    Write-Host ""

    if ($canvas) {
        $text = ConvertFrom-CanvasContent $canvas
        Write-Host $text
    }
    else {
        # Fallback for classic pages: fetch raw HTML and strip tags
        Write-Host "(No canvas content. Attempting classic page fallback...)`n"
        try {
            $fullUrl = "$SiteUrl/$PagePath"
            $html = Invoke-WebRequest -Uri $fullUrl -WebSession $session -ErrorAction Stop
            $content = $html.Content
            $content = $content -replace '<script[^>]*>[\s\S]*?</script>', ''
            $content = $content -replace '<style[^>]*>[\s\S]*?</style>', ''
            $content = $content -replace '<nav[^>]*>[\s\S]*?</nav>', ''
            $content = $content -replace '<header[^>]*>[\s\S]*?</header>', ''
            $content = $content -replace '<footer[^>]*>[\s\S]*?</footer>', ''
            $text = ConvertFrom-SharePointHtml $content
            if ($text.Length -gt 50) {
                Write-Host $text
            }
            else {
                Write-Host "(Page has no extractable text content.)"
            }
        }
        catch {
            Write-Host "(Could not fetch classic page content: $($_.Exception.Message))"
        }
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'ECONNREFUSED|Unable to connect|No connection') {
        Write-Host "`nTeams CDP not available. Ensure:" -ForegroundColor Yellow
        Write-Host "1. WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is set to --remote-debugging-port=9222"
        Write-Host "2. Teams has been restarted after setting the variable"
    }
    elseif ($_.Exception.Message -match '404') {
        Write-Host "`nPage not found. Verify the URL is correct and points to a SitePages/*.aspx page." -ForegroundColor Yellow
    }
    exit 1
}
