<#
.SYNOPSIS
    Lists Outlook mail folders and their message counts.

.DESCRIPTION
    Uses the Outlook COM API to enumerate mail folders.
    Must be run with: powershell -STA -NoProfile -File Get-OutlookFolders.ps1

.PARAMETER Depth
    How many levels deep to recurse into subfolders. Default 2.

.EXAMPLE
    powershell -STA -NoProfile -File Get-OutlookFolders.ps1
    powershell -STA -NoProfile -File Get-OutlookFolders.ps1 -Depth 3
#>
param(
    [ValidateRange(1, 10)]
    [int]$Depth = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$outlook = $null
try {
    $outlook = New-Object -ComObject Outlook.Application
} catch {
    Write-Error "Failed to create Outlook COM object. Ensure Outlook is installed and running."
    exit 1
}

try {
    $ns = $outlook.GetNamespace("MAPI")

    function List-Folders($folder, [int]$level = 0, [int]$maxDepth = 2) {
        $indent = "  " * $level
        $count = try { $folder.Items.Count } catch { "?" }
        $unread = try { $folder.UnReadItemCount } catch { "?" }
        Write-Host "${indent}$($folder.Name)  ($count items, $unread unread)"

        if ($level -lt $maxDepth) {
            foreach ($sub in $folder.Folders) {
                List-Folders $sub ($level + 1) $maxDepth
            }
        }
    }

    Write-Host "=== Outlook Mail Folders ===`n"

    # List default store folders
    $store = $ns.DefaultStore
    $root = $store.GetRootFolder()
    foreach ($folder in $root.Folders) {
        List-Folders $folder 0 $Depth
    }

} finally {
    if ($outlook) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null
    }
}
