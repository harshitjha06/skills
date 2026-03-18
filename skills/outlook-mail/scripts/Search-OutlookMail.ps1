<#
.SYNOPSIS
    Searches Outlook emails by keyword, sender, date range, or folder.

.DESCRIPTION
    Uses the Outlook COM API to search mail items via DASL filters.
    Must be run with: powershell -STA -NoProfile -File Search-OutlookMail.ps1 -SearchTerm <term>

.PARAMETER SearchTerm
    Keyword or phrase to search for in subject and body (case-insensitive).

.PARAMETER Subject
    Search only in email subjects (exact substring match).

.PARAMETER From
    Filter by sender name or email address (substring match).

.PARAMETER Folder
    Outlook folder name to search in. Default is Inbox. Use "All" to search Inbox + SentMail.

.PARAMETER After
    Only return emails received after this date (yyyy-MM-dd format).

.PARAMETER Before
    Only return emails received before this date (yyyy-MM-dd format).

.PARAMETER MaxResults
    Maximum number of results to return. Default 25.

.EXAMPLE
    powershell -STA -NoProfile -File Search-OutlookMail.ps1 -SearchTerm "Project Gold"
    powershell -STA -NoProfile -File Search-OutlookMail.ps1 -Subject "Project Gold" -After "2026-02-01"
    powershell -STA -NoProfile -File Search-OutlookMail.ps1 -From "evgenii" -MaxResults 10
#>
param(
    [string]$SearchTerm,
    [string]$Subject,
    [string]$From,
    [string]$Folder = "Inbox",
    [string]$After,
    [string]$Before,
    [ValidateRange(1, 500)]
    [int]$MaxResults = 25
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $SearchTerm -and -not $Subject -and -not $From) {
    Write-Error "At least one of -SearchTerm, -Subject, or -From must be provided."
    exit 1
}

$outlook = $null
try {
    $outlook = New-Object -ComObject Outlook.Application
} catch {
    Write-Error "Failed to create Outlook COM object. Ensure Outlook is installed and running."
    exit 1
}

try {
    $ns = $outlook.GetNamespace("MAPI")

    # Map folder names to default folder constants
    $folderMap = @{
        "Inbox"    = 6   # olFolderInbox
        "Sent"     = 5   # olFolderSentMail
        "SentMail" = 5
        "Drafts"   = 16  # olFolderDrafts
        "Deleted"  = 3   # olFolderDeletedItems
        "Junk"     = 23  # olFolderJunk
        "Archive"  = 36  # olFolderArchive (Outlook 2016+)
    }

    function Search-Folder($folderObj) {
        $items = $folderObj.Items
        $items.Sort("[ReceivedTime]", $true)

        # Build DASL filter
        $filters = @()

        if ($SearchTerm) {
            $escaped = $SearchTerm -replace "'", "''"
            $filters += "((""urn:schemas:httpmail:subject"" LIKE '%$escaped%') OR (""urn:schemas:httpmail:textdescription"" LIKE '%$escaped%'))"
        }

        if ($Subject) {
            $escaped = $Subject -replace "'", "''"
            $filters += "(""urn:schemas:httpmail:subject"" LIKE '%$escaped%')"
        }

        if ($From) {
            $escaped = $From -replace "'", "''"
            $filters += "((""urn:schemas:httpmail:fromemail"" LIKE '%$escaped%') OR (""urn:schemas:httpmail:fromname"" LIKE '%$escaped%'))"
        }

        if ($After) {
            $afterDate = [datetime]::ParseExact($After, "yyyy-MM-dd", $null)
            $filters += "(""urn:schemas:httpmail:datereceived"" >= '$($afterDate.ToString("yyyy-MM-ddTHH:mm:ssZ"))')"
        }

        if ($Before) {
            $beforeDate = [datetime]::ParseExact($Before, "yyyy-MM-dd", $null)
            $filters += "(""urn:schemas:httpmail:datereceived"" <= '$($beforeDate.ToString("yyyy-MM-ddTHH:mm:ssZ"))')"
        }

        if ($filters.Count -gt 0) {
            $dasl = "@SQL=" + ($filters -join " AND ")
            $results = $items.Restrict($dasl)
        } else {
            $results = $items
        }

        return $results
    }

    $allResults = @()

    if ($Folder -eq "All") {
        $foldersToSearch = @(6, 5)  # Inbox + Sent
    } elseif ($folderMap.ContainsKey($Folder)) {
        $foldersToSearch = @($folderMap[$Folder])
    } else {
        Write-Error "Unknown folder '$Folder'. Valid: Inbox, Sent, SentMail, Drafts, Deleted, Junk, Archive, All"
        exit 1
    }

    foreach ($fid in $foldersToSearch) {
        try {
            $f = $ns.GetDefaultFolder($fid)
            $results = Search-Folder $f
            foreach ($mail in $results) {
                if ($allResults.Count -ge $MaxResults) { break }
                try {
                    $allResults += [PSCustomObject]@{
                        Subject      = $mail.Subject
                        From         = $mail.SenderName
                        To           = $mail.To
                        Date         = $mail.ReceivedTime.ToString("yyyy-MM-dd HH:mm")
                        HasAttach    = $mail.Attachments.Count -gt 0
                        EntryID      = $mail.EntryID
                        ConvID       = $mail.ConversationID
                        ConvTopic    = $mail.ConversationTopic
                        Importance   = $mail.Importance
                    }
                } catch {
                    # Skip non-mail items (meeting requests, etc.)
                    continue
                }
            }
        } catch {
            Write-Warning "Could not search folder $fid : $($_.Exception.Message)"
        }
    }

    if ($allResults.Count -eq 0) {
        Write-Host "No emails found matching the given criteria."
        exit 0
    }

    Write-Host "Found $($allResults.Count) email(s):`n"
    $allResults | Format-List Subject, From, To, Date, HasAttach, ConvTopic, EntryID

} finally {
    if ($outlook) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null
    }
}
