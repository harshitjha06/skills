<#
.SYNOPSIS
    Downloads a file from a SharePoint document library and saves it locally.
.PARAMETER Url
    Full URL to the SharePoint file.
.PARAMETER FolderPath
    Server-relative folder path containing the file (used with -FileName).
.PARAMETER FileName
    Name of the file to download (used with -FolderPath).
.PARAMETER SiteUrl
    SharePoint site URL (used with -FolderPath).
.PARAMETER OutDir
    Local directory to save the file to (default: current directory).
.PARAMETER OutFile
    Full local path for the saved file. Overrides -OutDir and uses this exact path.
#>
param(
    [string]$Url = "",
    [string]$SiteUrl = "",
    [string]$FolderPath = "",
    [string]$FileName = "",
    [string]$OutDir = ".",
    [string]$OutFile = ""
)

. "$PSScriptRoot\SharePoint-Helper.ps1"

try {
    if (-not $Url -and (-not $SiteUrl -or -not $FolderPath -or -not $FileName)) {
        Write-Host "Usage:"
        Write-Host "  .\Download-SharePointFile.ps1 -Url <full file URL>"
        Write-Host "  .\Download-SharePointFile.ps1 -SiteUrl <site> -FolderPath <folder> -FileName <name>"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\Download-SharePointFile.ps1 -Url 'https://microsoft.sharepoint.com/teams/MyTeam/Shared Documents/spec.docx'"
        Write-Host "  .\Download-SharePointFile.ps1 -Url '...' -OutDir 'C:\temp'"
        exit 1
    }

    $session = New-SharePointSession

    if (-not $Url) {
        $encodedFolder = [Uri]::EscapeDataString($FolderPath)
        $encodedFile = [Uri]::EscapeDataString($FileName)
        $Url = "$SiteUrl/_api/web/GetFolderByServerRelativeUrl('$encodedFolder')/Files('$encodedFile')/`$value"
        $downloadName = $FileName
    }
    else {
        $downloadName = $Url.Split('/')[-1].Split('?')[0]
        # URL-decode the filename
        $downloadName = [Uri]::UnescapeDataString($downloadName)
    }

    if ($OutFile) {
        $savePath = $OutFile
    }
    else {
        if (-not (Test-Path $OutDir)) {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        }
        $savePath = Join-Path $OutDir $downloadName
    }

    Write-Host "Downloading: $downloadName"

    $response = Invoke-WebRequest -Uri $Url -WebSession $session -ErrorAction Stop -OutFile $savePath -PassThru

    $sizeKB = [Math]::Round((Get-Item $savePath).Length / 1024)
    Write-Host "Saved: $savePath ($sizeKB KB)"
    Write-Host "Content-Type: $($response.Headers['Content-Type'])"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'ECONNREFUSED|Unable to connect|No connection') {
        Write-Host "`nTeams CDP not available. Ensure:" -ForegroundColor Yellow
        Write-Host "1. WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is set to --remote-debugging-port=9222"
        Write-Host "2. Teams has been restarted after setting the variable"
    }
    elseif ($_.Exception.Message -match '404') {
        Write-Host "`nFile not found. Verify the URL is correct." -ForegroundColor Yellow
    }
    elseif ($_.Exception.Message -match '401|403') {
        Write-Host "`nAccess denied. Verify you have permissions to this file." -ForegroundColor Yellow
    }
    exit 1
}
