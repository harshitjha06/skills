<#
.SYNOPSIS
    Helper functions for SharePoint access via Teams CDP cookie extraction.
.DESCRIPTION
    Extracts the SPOIDCRL auth cookie from the Teams WebView2 browser via Chrome
    DevTools Protocol, then provides functions to call the SharePoint REST API.
    Reuses the same CDP approach as Teams-ChatHelper.ps1 but targets SharePoint cookies.
#>

$script:CDP_PORT = if ($env:TEAMS_CDP_PORT) { $env:TEAMS_CDP_PORT } else { 9222 }

function Invoke-CdpCommand {
    param(
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params = @{}
    )

    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = [System.Threading.CancellationToken]::None

    try {
        $ws.ConnectAsync([Uri]$WebSocketUrl, $ct).Wait()

        $cmd = @{ id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList (,$bytes)
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

        $buffer = New-Object byte[] 262144
        $result = New-Object System.Text.StringBuilder
        do {
            $seg = New-Object System.ArraySegment[byte] -ArgumentList (,$buffer)
            $recv = $ws.ReceiveAsync($seg, $ct).Result
            [void]$result.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $recv.Count))
        } while (-not $recv.EndOfMessage)

        return ($result.ToString() | ConvertFrom-Json).result
    }
    finally {
        if ($ws.State -eq 'Open') {
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()
        }
        $ws.Dispose()
    }
}

function Get-SharePointCookie {
    param(
        [string]$Domain = "microsoft.sharepoint.com"
    )

    $targets = Invoke-RestMethod -Uri "http://localhost:$script:CDP_PORT/json" -ErrorAction Stop
    $target = $targets | Where-Object {
        $_.type -eq 'page' -and ($_.url -match 'teams\.microsoft\.com' -or $_.url -match 'teams\.cloud\.microsoft' -or $_.url -match 'microsoft365\.com')
    } | Select-Object -First 1
    if (-not $target) { throw "Teams page not found via CDP on port $script:CDP_PORT" }

    $result = Invoke-CdpCommand -WebSocketUrl $target.webSocketDebuggerUrl -Method 'Network.getAllCookies'
    $cookie = $result.cookies | Where-Object { $_.domain -eq $Domain -and $_.name -eq 'SPOIDCRL' } | Select-Object -First 1
    if (-not $cookie) { throw "SPOIDCRL cookie not found for $Domain. Ensure Teams has accessed SharePoint content." }

    return $cookie.value
}

function New-SharePointSession {
    param(
        [string]$Domain = "microsoft.sharepoint.com"
    )

    $cookieValue = Get-SharePointCookie -Domain $Domain
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $cookie = New-Object System.Net.Cookie("SPOIDCRL", $cookieValue, "/", $Domain)
    $session.Cookies.Add($cookie)
    return $session
}

function Invoke-SharePointApi {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Url
    )

    return Invoke-RestMethod -Uri $Url -WebSession $Session -Headers @{
        Accept = "application/json;odata=verbose"
    } -ErrorAction Stop
}

function ConvertFrom-SharePointHtml {
    param([string]$Html)

    $text = $Html -replace '<br\s*/?>', "`n"
    $text = $text -replace '</(p|div|h[1-6]|li|tr|td|blockquote)>', "`n"
    $text = $text -replace '</?(ul|ol)>', "`n"
    $text = $text -replace '<a[^>]*href="([^"]*)"[^>]*>([^<]*)</a>', '$2 ($1)'
    $text = $text -replace '<[^>]+>', ''
    $text = $text -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
    $text = $text -replace '&quot;', '"' -replace '&#39;', "'" -replace '&#58;', ':' -replace '&#x3A;', ':'
    $text = ($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join "`n"
    return $text
}

function ConvertFrom-CanvasContent {
    param([string]$Canvas)

    $texts = @()

    try {
        $parts = $Canvas | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Regex fallback for malformed JSON
        [regex]::Matches($Canvas, '"innerHTML":"((?:[^"\\]|\\.)*)"') | ForEach-Object {
            $raw = $_.Groups[1].Value -replace '\\n', "`n" -replace '\\/', '/' -replace '\\"', '"'
            $t = ConvertFrom-SharePointHtml $raw
            if ($t.Length -gt 3) { $texts += $t }
        }
        [regex]::Matches($Canvas, '"body":"((?:[^"\\]|\\.)*)"') | ForEach-Object {
            $raw = $_.Groups[1].Value -replace '\\n', "`n" -replace '\\/', '/' -replace '\\"', '"'
            $t = ConvertFrom-SharePointHtml $raw
            if ($t.Length -gt 5) { $texts += $t }
        }
        return ($texts -join "`n`n")
    }

    foreach ($part in $parts) {
        if ($part.innerHTML) {
            $t = ConvertFrom-SharePointHtml $part.innerHTML
            if ($t.Length -gt 3) { $texts += $t }
        }

        if ($part.webPartData.serverProcessedContent) {
            $spc = $part.webPartData.serverProcessedContent

            if ($spc.htmlStrings) {
                $spc.htmlStrings.PSObject.Properties | ForEach-Object {
                    $t = ConvertFrom-SharePointHtml $_.Value
                    if ($t.Length -gt 5) { $texts += $t }
                }
            }

            if ($spc.searchablePlainTexts) {
                $spc.searchablePlainTexts.PSObject.Properties | ForEach-Object {
                    if ($_.Value -and $_.Value.Length -gt 2 -and $_.Name -match 'title') {
                        $texts += $_.Value
                    }
                }
            }
        }
    }

    return ($texts -join "`n`n")
}

function Resolve-SharePointUrl {
    param([Parameter(Mandatory)][string]$Url)

    if ($Url -match '^(https://[^/]+/sites/[^/]+)(.*)$') {
        $siteUrl = $Matches[1]
        $remainder = $Matches[2]
    }
    elseif ($Url -match '^(https://[^/]+/teams/[^/]+)(.*)$') {
        $siteUrl = $Matches[1]
        $remainder = $Matches[2]
    }
    else {
        throw "Cannot parse SharePoint URL: $Url"
    }

    $pagePath = ""
    if ($remainder -match '(/SitePages/[^#?]+\.aspx)') {
        $pagePath = $Matches[1]
    }

    return @{
        SiteUrl  = $siteUrl
        PagePath = $pagePath
    }
}
