<#
.SYNOPSIS
    Reads items from a SharePoint list.
.PARAMETER SiteUrl
    SharePoint site URL (required).
.PARAMETER ListName
    Name of the SharePoint list to read (required unless -ListAll is specified).
.PARAMETER ListAll
    List all available lists on the site instead of reading items.
.PARAMETER Fields
    Comma-separated list of field names to retrieve (default: all fields).
.PARAMETER Filter
    OData filter expression (e.g., "Status eq 'Active'").
.PARAMETER MaxResults
    Maximum number of items to return (default 25).
.PARAMETER OrderBy
    Field name to sort by (e.g., "Modified desc").
#>
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$ListName = "",
    [switch]$ListAll,
    [string]$Fields = "",
    [string]$Filter = "",
    [int]$MaxResults = 25,
    [string]$OrderBy = ""
)

. "$PSScriptRoot\SharePoint-Helper.ps1"

try {
    $session = New-SharePointSession

    if ($ListAll -or -not $ListName) {
        $url = "$SiteUrl/_api/web/lists?`$select=Title,ItemCount,LastItemModifiedDate,BaseTemplate,Hidden&`$filter=Hidden eq false&`$orderby=LastItemModifiedDate desc&`$top=50"
        $result = Invoke-SharePointApi -Session $session -Url $url

        $lists = $result.d.results
        if (-not $lists -or $lists.Count -eq 0) {
            Write-Host "No lists found on this site."
            exit 0
        }

        Write-Host "=== Lists on $(($SiteUrl -split '/')[-1]) ==="
        Write-Host ""

        $templateNames = @{
            100 = 'Custom List'
            101 = 'Document Library'
            104 = 'Announcements'
            106 = 'Calendar'
            107 = 'Tasks'
            108 = 'Discussion Board'
            119 = 'Wiki'
            851 = 'Asset Library'
        }

        foreach ($list in $lists) {
            $typeName = if ($templateNames.ContainsKey([int]$list.BaseTemplate)) { $templateNames[[int]$list.BaseTemplate] } else { "Template $($list.BaseTemplate)" }
            Write-Host "  $($list.Title) ($($list.ItemCount) items, $typeName)"
        }
        Write-Host ""
        Write-Host "Use -ListName '<name>' to read items from a specific list."
        exit 0
    }

    # Build the items query
    $encodedList = [Uri]::EscapeDataString($ListName)
    $url = "$SiteUrl/_api/web/lists/getbytitle('$encodedList')/items?`$top=$MaxResults"

    if ($Fields) {
        $url += "&`$select=$Fields"
    }
    if ($Filter) {
        $url += "&`$filter=$Filter"
    }
    if ($OrderBy) {
        $url += "&`$orderby=$OrderBy"
    }

    $result = Invoke-SharePointApi -Session $session -Url $url

    $items = $result.d.results
    if (-not $items -or $items.Count -eq 0) {
        Write-Host "No items found in list '$ListName'."
        exit 0
    }

    Write-Host "=== $ListName ($($items.Count) items) ==="
    Write-Host ""

    # Determine which fields to display
    $skipFields = @('__metadata', 'FileSystemObjectType', 'ServerRedirectedEmbedUri', 'ServerRedirectedEmbedUrl',
        'ContentTypeId', 'ComplianceAssetId', 'OData__UIVersionString', 'GUID', 'Attachments',
        'AuthorId', 'EditorId', 'OData__ColorTag', 'OData__IsRecord')

    foreach ($item in $items) {
        $props = $item.PSObject.Properties | Where-Object {
            $_.Name -notin $skipFields -and
            $_.Name -notmatch '^OData__' -and
            $_.Value -ne $null -and
            $_.Value -ne '' -and
            $_.MemberType -eq 'NoteProperty'
        }

        $idProp = $props | Where-Object { $_.Name -eq 'Id' -or $_.Name -eq 'ID' } | Select-Object -First 1
        $titleProp = $props | Where-Object { $_.Name -eq 'Title' } | Select-Object -First 1

        if ($titleProp) {
            Write-Host "--- $($titleProp.Value) (ID: $($idProp.Value)) ---"
        }
        elseif ($idProp) {
            Write-Host "--- Item $($idProp.Value) ---"
        }

        foreach ($prop in $props) {
            if ($prop.Name -in @('Id', 'ID', 'Title')) { continue }
            $val = $prop.Value
            if ($val -is [PSCustomObject]) { continue }
            if ("$val".Length -gt 200) { $val = "$val".Substring(0, 200) + "..." }
            Write-Host "  $($prop.Name): $val"
        }
        Write-Host ""
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'does not exist|404') {
        Write-Host "`nList '$ListName' not found. Use -ListAll to see available lists." -ForegroundColor Yellow
    }
    elseif ($_.Exception.Message -match 'ECONNREFUSED|Unable to connect|No connection') {
        Write-Host "`nTeams CDP not available. Ensure:" -ForegroundColor Yellow
        Write-Host "1. WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is set to --remote-debugging-port=9222"
        Write-Host "2. Teams has been restarted after setting the variable"
    }
    exit 1
}
