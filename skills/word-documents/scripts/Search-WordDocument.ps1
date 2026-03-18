<#
.SYNOPSIS
    Searches for Word documents by filename pattern in common locations.

.DESCRIPTION
    Recursively searches Documents, OneDrive, and Desktop folders for .docx/.doc files
    matching a keyword. Returns file paths, sizes, and last modified dates.

.PARAMETER SearchTerm
    Keyword to match against filenames (case-insensitive, partial match).

.PARAMETER Path
    Optional. Override the search root directory. Defaults to common locations.

.PARAMETER MaxResults
    Maximum number of results to return. Default 20.

.EXAMPLE
    powershell -NoProfile -File Search-WordDocument.ps1 -SearchTerm "playbook"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SearchTerm,

    [string]$Path,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxResults = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Determine search roots
if ($Path) {
    $roots = @($Path)
} else {
    $roots = @(
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $env:USERPROFILE "OneDrive - Microsoft"),
        (Join-Path $env:USERPROFILE "OneDrive"),
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:USERPROFILE "Downloads")
    ) | Where-Object { Test-Path $_ } | Select-Object -Unique
}

$allResults = @()

foreach ($root in $roots) {
    try {
        $escapedTerm = [WildcardPattern]::Escape($SearchTerm)
        $files = @(Get-ChildItem -Path $root -Recurse -Include "*.docx","*.doc" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*${escapedTerm}*" -and $_.Name -notlike "~`$*" })
        $allResults += $files
    } catch {
        # Skip inaccessible directories
    }
}

if ($allResults.Count -eq 0) {
    Write-Host "No Word documents found matching '$SearchTerm'"
    exit 0
}

# Deduplicate by full path and sort by last write time
$allResults = @($allResults | Sort-Object -Property FullName -Unique | Sort-Object LastWriteTime -Descending)

if ($MaxResults -gt 0) {
    $allResults = @($allResults | Select-Object -First $MaxResults)
}

Write-Host "Found $($allResults.Count) document(s) matching '$SearchTerm':`n"

$allResults | ForEach-Object {
    [PSCustomObject]@{
        Name     = $_.Name
        Path     = $_.FullName
        Size     = "{0:N0} KB" -f ($_.Length / 1KB)
        Modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    }
} | Format-List
