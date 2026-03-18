<#
.SYNOPSIS
    Reads the full content of an Outlook email by EntryID, or reads an entire conversation thread.

.DESCRIPTION
    Uses the Outlook COM API to fetch email content. Can read a single email by EntryID
    or an entire conversation thread by ConversationID. HTML body content is converted
    to readable text and inline image placement is preserved with inline markers.
    Must be run with: powershell -STA -NoProfile -File Read-OutlookMail.ps1 -EntryID <id>

.PARAMETER EntryID
    The Outlook EntryID of a specific email (from Search-OutlookMail.ps1).

.PARAMETER ConversationID
    Read all emails in a conversation thread. Returns messages in chronological order.

.PARAMETER MaxBodyChars
    Maximum characters to return from each email body. Default 5000. Use 0 for unlimited.

.PARAMETER BodyOnly
    Only output the email body text, skip headers/metadata.

.PARAMETER SaveAttachments
    If set, saves attachments to a temp directory and prints their paths.
    Files are saved with unique prefixed names per message to prevent overwrite.

.EXAMPLE
    powershell -STA -NoProfile -File Read-OutlookMail.ps1 -EntryID "<ENTRY_ID>"
    powershell -STA -NoProfile -File Read-OutlookMail.ps1 -ConversationID "<CONV_ID>"
#>
param(
    [string]$EntryID,
    [string]$ConversationID,
    [ValidateRange(0, 1000000)]
    [int]$MaxBodyChars = 5000,
    [switch]$BodyOnly,
    [switch]$SaveAttachments
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $EntryID -and -not $ConversationID) {
    Write-Error "Either -EntryID or -ConversationID must be provided."
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
    try { Add-Type -AssemblyName System.Web | Out-Null } catch {}

    $attachmentRootDir = $null
    if ($SaveAttachments) {
        $attachmentRootDir = Join-Path $env:TEMP "outlook-mail"
        if (-not (Test-Path -LiteralPath $attachmentRootDir)) {
            New-Item -ItemType Directory -Path $attachmentRootDir -Force | Out-Null
        }
    }

    function Decode-Html {
        param([AllowNull()][string]$Text)
        if ($null -eq $Text) { return "" }
        try {
            return [System.Web.HttpUtility]::HtmlDecode($Text)
        } catch {
            return $Text
        }
    }

    function New-SafeFileName {
        param(
            [AllowNull()][string]$Name,
            [int]$MaxLength = 120
        )

        $result = if ([string]::IsNullOrWhiteSpace($Name)) { "attachment" } else { $Name }
        $result = $result -replace '[\\/:*?"<>|]', '_'
        $result = $result.Trim('. ')

        if ([string]::IsNullOrWhiteSpace($result)) {
            $result = "attachment"
        }

        if ($result.Length -gt $MaxLength) {
            $result = $result.Substring(0, $MaxLength)
        }

        return $result
    }

    function Normalize-ReferenceKey {
        param([AllowNull()][string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

        $normalized = $Value.Trim()
        if ($normalized.StartsWith("cid:", [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(4)
        }

        $normalized = $normalized.Trim().Trim('<', '>', '"', "'")
        if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }

        return $normalized.ToLowerInvariant()
    }

    function Get-AttachmentPropertyString {
        param(
            $Attachment,
            [string]$PropertyTag
        )

        try {
            $value = $Attachment.PropertyAccessor.GetProperty($PropertyTag)
            if ($null -eq $value) { return $null }
            return [string]$value
        } catch {
            return $null
        }
    }

    function Get-HtmlAttributeValue {
        param(
            [AllowNull()][string]$Tag,
            [string]$AttributeName
        )

        if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }

        $pattern = "(?is)\b$([regex]::Escape($AttributeName))\s*=\s*(?:""([^""]*)""|'([^']*)'|([^\s>]+))"
        $match = [regex]::Match($Tag, $pattern)
        if (-not $match.Success) { return $null }
        if ($match.Groups[1].Success) { return $match.Groups[1].Value }
        if ($match.Groups[2].Success) { return $match.Groups[2].Value }
        if ($match.Groups[3].Success) { return $match.Groups[3].Value }
        return $null
    }

    function Convert-HtmlFragmentToText {
        param([AllowNull()][string]$HtmlFragment)
        if ([string]::IsNullOrWhiteSpace($HtmlFragment)) { return "" }

        $text = [regex]::Replace($HtmlFragment, '(?is)<[^>]+>', '')
        return (Decode-Html $text).Trim()
    }

    function New-MessageAttachmentDirectory {
        param(
            [string]$RootPath,
            $Mail
        )

        $receivedPart = try { $Mail.ReceivedTime.ToString("yyyyMMdd-HHmmss") } catch { (Get-Date).ToString("yyyyMMdd-HHmmss") }
        $subjectPart = try { New-SafeFileName -Name ([string]$Mail.Subject) -MaxLength 40 } catch { "message" }
        $entryPart = try {
            $entry = [string]$Mail.EntryID
            if ($entry.Length -gt 8) { $entry.Substring($entry.Length - 8) } else { $entry }
        } catch {
            [guid]::NewGuid().ToString("N").Substring(0, 8)
        }
        $entryPart = New-SafeFileName -Name $entryPart -MaxLength 12

        $baseName = "$receivedPart-$subjectPart-$entryPart"
        $candidatePath = Join-Path $RootPath $baseName
        $suffix = 1
        while (Test-Path -LiteralPath $candidatePath) {
            $candidatePath = Join-Path $RootPath ("$baseName-$suffix")
            $suffix++
        }

        New-Item -ItemType Directory -Path $candidatePath -Force | Out-Null
        return $candidatePath
    }

    function Get-MailAttachmentContext {
        param(
            $Mail,
            [AllowNull()][string]$MessageAttachmentDir,
            [switch]$SaveToDisk
        )

        $ctx = [PSCustomObject]@{
            Attachments = @()
            CidMap = @{}
            NameMap = @{}
            LocationMap = @{}
        }

        $count = try { [int]$Mail.Attachments.Count } catch { 0 }
        for ($i = 1; $i -le $count; $i++) {
            $att = $Mail.Attachments.Item($i)
            $rawName = try { [string]$att.FileName } catch { "attachment-$i.bin" }
            if ([string]::IsNullOrWhiteSpace($rawName)) {
                $rawName = "attachment-$i.bin"
            }

            $sizeBytes = try { [int]$att.Size } catch { 0 }
            $contentId = Normalize-ReferenceKey (Get-AttachmentPropertyString -Attachment $att -PropertyTag "http://schemas.microsoft.com/mapi/proptag/0x3712001F")
            if (-not $contentId) {
                $contentId = Normalize-ReferenceKey (Get-AttachmentPropertyString -Attachment $att -PropertyTag "http://schemas.microsoft.com/mapi/proptag/0x3712001E")
            }

            $contentLocation = Normalize-ReferenceKey (Get-AttachmentPropertyString -Attachment $att -PropertyTag "http://schemas.microsoft.com/mapi/proptag/0x3713001F")
            if (-not $contentLocation) {
                $contentLocation = Normalize-ReferenceKey (Get-AttachmentPropertyString -Attachment $att -PropertyTag "http://schemas.microsoft.com/mapi/proptag/0x3713001E")
            }

            $extension = [System.IO.Path]::GetExtension($rawName).ToLowerInvariant()
            $isImage = $extension -in @(".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".tif", ".tiff", ".svg", ".ico")

            $savedPath = $null
            $saveError = $null
            if ($SaveToDisk -and $MessageAttachmentDir) {
                $safeName = New-SafeFileName -Name $rawName
                $destName = "{0:D2}-{1}" -f $i, $safeName
                $destPath = Join-Path $MessageAttachmentDir $destName
                try {
                    $att.SaveAsFile($destPath)
                    $savedPath = $destPath
                } catch {
                    $saveError = $_.Exception.Message
                }
            }

            $attachmentInfo = [PSCustomObject]@{
                Index = $i
                Name = $rawName
                SizeBytes = $sizeBytes
                ContentId = $contentId
                ContentLocation = $contentLocation
                IsImage = $isImage
                SavedPath = $savedPath
                SaveError = $saveError
                ReferencedInline = $false
            }

            $ctx.Attachments += $attachmentInfo

            if ($contentId -and -not $ctx.CidMap.ContainsKey($contentId)) {
                $ctx.CidMap[$contentId] = $attachmentInfo
            }

            if ($contentLocation -and -not $ctx.LocationMap.ContainsKey($contentLocation)) {
                $ctx.LocationMap[$contentLocation] = $attachmentInfo
            }

            $nameKey = Normalize-ReferenceKey $rawName
            if ($nameKey -and -not $ctx.NameMap.ContainsKey($nameKey)) {
                $ctx.NameMap[$nameKey] = $attachmentInfo
            }
        }

        return $ctx
    }

    function Resolve-InlineAttachment {
        param(
            [AllowNull()][string]$Source,
            $AttachmentContext
        )

        if ([string]::IsNullOrWhiteSpace($Source)) { return $null }

        $sourceTrim = (Decode-Html $Source).Trim()
        $sourceKey = Normalize-ReferenceKey $sourceTrim
        if ($sourceKey -and $AttachmentContext.CidMap.ContainsKey($sourceKey)) {
            return $AttachmentContext.CidMap[$sourceKey]
        }

        if ($sourceKey -and $AttachmentContext.LocationMap.ContainsKey($sourceKey)) {
            return $AttachmentContext.LocationMap[$sourceKey]
        }

        $sourceNoQuery = $sourceTrim -split '\?', 2 | Select-Object -First 1
        $sourceFileName = try { [System.IO.Path]::GetFileName($sourceNoQuery) } catch { $null }
        $fileKey = Normalize-ReferenceKey $sourceFileName
        if ($fileKey -and $AttachmentContext.NameMap.ContainsKey($fileKey)) {
            return $AttachmentContext.NameMap[$fileKey]
        }

        return $null
    }

    function Save-DataUriImage {
        param(
            [string]$DataUri,
            [string]$OutputDirectory,
            [int]$ImageNumber
        )

        if ([string]::IsNullOrWhiteSpace($DataUri)) { return $null }
        if (-not $DataUri.StartsWith("data:image/", [System.StringComparison]::OrdinalIgnoreCase)) { return $null }

        $match = [regex]::Match($DataUri, '^data:image/(?<type>[a-zA-Z0-9.+-]+);base64,(?<data>.+)$')
        if (-not $match.Success) { return $null }

        $imgType = $match.Groups["type"].Value.ToLowerInvariant()
        $ext = switch ($imgType) {
            "jpeg" { "jpg" }
            "svg+xml" { "svg" }
            default { $imgType }
        }

        try {
            $bytes = [System.Convert]::FromBase64String($match.Groups["data"].Value)
        } catch {
            return $null
        }

        $fileName = "{0:D2}-inline-data-{1}.{2}" -f $ImageNumber, (Get-Random -Minimum 100000 -Maximum 999999), $ext
        $path = Join-Path $OutputDirectory $fileName
        [System.IO.File]::WriteAllBytes($path, $bytes)
        return $path
    }

    function New-InlineImageMarker {
        param(
            [AllowNull()][string]$AltText,
            [AllowNull()][string]$Source,
            $AttachmentInfo,
            [AllowNull()][string]$DataUriPath
        )

        $parts = @()
        if ($AttachmentInfo) {
            $parts += "file=$($AttachmentInfo.Name)"
        }
        if ($DataUriPath) {
            $parts += "file=inline-data-image"
            $parts += "path=$DataUriPath"
        }
        if (-not [string]::IsNullOrWhiteSpace($AltText)) {
            $parts += "alt=$AltText"
        }
        if ($AttachmentInfo -and $AttachmentInfo.SavedPath) {
            $parts += "path=$($AttachmentInfo.SavedPath)"
        }

        if (-not $AttachmentInfo -and -not $DataUriPath -and -not [string]::IsNullOrWhiteSpace($Source)) {
            if ($Source.StartsWith("data:image/", [System.StringComparison]::OrdinalIgnoreCase)) {
                $parts += "src=embedded-data-uri"
            } else {
                $parts += "src=$Source"
            }
        }

        if ($parts.Count -eq 0) {
            return "[INLINE IMAGE]"
        }

        return "[INLINE IMAGE: $($parts -join ' | ')]"
    }

    function Convert-HtmlBodyToText {
        param(
            [AllowNull()][string]$HtmlBody,
            $AttachmentContext,
            [AllowNull()][string]$MessageAttachmentDir,
            [switch]$SaveToDisk
        )

        if ([string]::IsNullOrWhiteSpace($HtmlBody)) { return "" }

        $content = $HtmlBody
        $content = [regex]::Replace($content, '(?is)<!--.*?-->', '')
        $content = [regex]::Replace($content, '(?is)<(script|style)\b.*?>.*?</\1>', '')

        $inlineCounter = 0
        $content = [regex]::Replace($content, '(?is)<img\b[^>]*>', [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)

            $tag = $match.Value
            $src = Decode-Html (Get-HtmlAttributeValue -Tag $tag -AttributeName "src")
            $alt = Convert-HtmlFragmentToText (Get-HtmlAttributeValue -Tag $tag -AttributeName "alt")
            $attachment = Resolve-InlineAttachment -Source $src -AttachmentContext $AttachmentContext
            $dataUriPath = $null

            if ($attachment) {
                $attachment.ReferencedInline = $true
            } elseif ($SaveToDisk -and $MessageAttachmentDir -and $src -and $src.StartsWith("data:image/", [System.StringComparison]::OrdinalIgnoreCase)) {
                $inlineCounter++
                $dataUriPath = Save-DataUriImage -DataUri $src -OutputDirectory $MessageAttachmentDir -ImageNumber $inlineCounter
            }

            $marker = New-InlineImageMarker -AltText $alt -Source $src -AttachmentInfo $attachment -DataUriPath $dataUriPath
            return "`n$marker`n"
        })

        $content = [regex]::Replace($content, '(?is)<a\b[^>]*>(.*?)</a>', [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)

            $tag = $match.Value
            $href = Decode-Html (Get-HtmlAttributeValue -Tag $tag -AttributeName "href")
            $innerText = Convert-HtmlFragmentToText $match.Groups[1].Value

            if ([string]::IsNullOrWhiteSpace($href)) { return $innerText }
            if ([string]::IsNullOrWhiteSpace($innerText)) { return $href }
            return "[$innerText]($href)"
        })

        $content = [regex]::Replace($content, '(?is)<br\s*/?>', "`n")
        $content = [regex]::Replace($content, '(?is)</(p|div|h[1-6]|tr|table|blockquote|section|article|ul|ol)>', "`n")
        $content = [regex]::Replace($content, '(?is)<li\b[^>]*>', "`n- ")
        $content = [regex]::Replace($content, '(?is)</t[dh]>', "`t")
        $content = [regex]::Replace($content, '(?is)<[^>]+>', '')

        $content = Decode-Html $content
        $content = $content -replace "\r\n?", "`n"
        $content = [regex]::Replace($content, "[ \t]+`n", "`n")
        $content = [regex]::Replace($content, "`n{3,}", "`n`n")

        return $content.Trim()
    }

    function Get-RenderedMailBody {
        param(
            $Mail,
            $AttachmentContext,
            [AllowNull()][string]$MessageAttachmentDir,
            [switch]$SaveToDisk
        )

        $htmlBody = try { [string]$Mail.HTMLBody } catch { "" }
        if (-not [string]::IsNullOrWhiteSpace($htmlBody)) {
            try {
                $renderedHtml = Convert-HtmlBodyToText -HtmlBody $htmlBody -AttachmentContext $AttachmentContext -MessageAttachmentDir $MessageAttachmentDir -SaveToDisk:$SaveToDisk
                if (-not [string]::IsNullOrWhiteSpace($renderedHtml)) {
                    return $renderedHtml
                }
            } catch {
                Write-Warning "Failed to parse HTML body. Falling back to plain text body: $($_.Exception.Message)"
            }
        }

        return try { [string]$Mail.Body } catch { "(could not read body)" }
    }

    function Write-RenderedBody {
        param([AllowNull()][string]$BodyText)

        if ($null -eq $BodyText) {
            Write-Host ""
            return
        }

        if ($MaxBodyChars -gt 0 -and $BodyText.Length -gt $MaxBodyChars) {
            Write-Host $BodyText.Substring(0, $MaxBodyChars)
            Write-Host "`n... [truncated at $MaxBodyChars of $($BodyText.Length) chars]"
        } else {
            Write-Host $BodyText
        }
    }

    function Format-Email {
        param(
            $Mail,
            [int]$Index = 0
        )

        $subject = try { [string]$Mail.Subject } catch { "(no subject)" }
        $from = try { [string]$Mail.SenderName } catch { "(unknown)" }
        $fromAddr = try { [string]$Mail.SenderEmailAddress } catch { "" }
        $to = try { [string]$Mail.To } catch { "" }
        $cc = try { [string]$Mail.CC } catch { "" }
        $date = try { $Mail.ReceivedTime.ToString("yyyy-MM-dd HH:mm:ss") } catch { "" }

        $messageAttachmentDir = $null
        if ($SaveAttachments -and $attachmentRootDir) {
            $messageAttachmentDir = New-MessageAttachmentDirectory -RootPath $attachmentRootDir -Mail $Mail
        }

        $attachmentContext = Get-MailAttachmentContext -Mail $Mail -MessageAttachmentDir $messageAttachmentDir -SaveToDisk:$SaveAttachments
        $body = Get-RenderedMailBody -Mail $Mail -AttachmentContext $attachmentContext -MessageAttachmentDir $messageAttachmentDir -SaveToDisk:$SaveAttachments

        if ($Index -gt 0) {
            Write-Host "`n============ MESSAGE $Index ============"
        }

        if (-not $BodyOnly) {
            Write-Host "Subject: $subject"
            Write-Host "From: $from <$fromAddr>"
            Write-Host "To: $to"
            if ($cc) { Write-Host "CC: $cc" }
            Write-Host "Date: $date"

            $attachments = @($attachmentContext.Attachments)
            if ($attachments.Count -gt 0) {
                Write-Host "Attachments: $($attachments.Name -join ', ')"

                $inlineReferencedCount = @($attachments | Where-Object { $_.ReferencedInline }).Count
                if ($inlineReferencedCount -gt 0) {
                    Write-Host "Inline images referenced in body: $inlineReferencedCount"
                }

                if ($SaveAttachments) {
                    foreach ($att in $attachments) {
                        if ($att.SavedPath) {
                            if ($att.ReferencedInline) {
                                Write-Host "[INLINE IMAGE SAVED: $($att.SavedPath)]"
                            } else {
                                Write-Host "[ATTACHMENT SAVED: $($att.SavedPath)]"
                            }
                        } elseif ($att.SaveError) {
                            Write-Host "[ATTACHMENT: $($att.Name) - save failed: $($att.SaveError)]"
                        }
                    }
                }
            }

            Write-Host "-------- BODY --------"
        }

        Write-RenderedBody -BodyText $body
    }

    if ($EntryID) {
        $mail = $ns.GetItemFromID($EntryID)
        if (-not $mail) {
            Write-Error "No email found with EntryID: $EntryID"
            exit 1
        }

        Format-Email -Mail $mail
    }

    if ($ConversationID) {
        # Search Inbox and Sent for all messages in this conversation.
        $allMails = @()
        $seenEntryIds = @{}
        $foldersToSearch = @(6, 5)  # Inbox, Sent

        foreach ($fid in $foldersToSearch) {
            try {
                $folder = $ns.GetDefaultFolder($fid)
                $items = $folder.Items

                foreach ($item in $items) {
                    try {
                        if ($item.ConversationID -eq $ConversationID) {
                            $itemEntryId = [string]$item.EntryID
                            if (-not $seenEntryIds.ContainsKey($itemEntryId)) {
                                $seenEntryIds[$itemEntryId] = $true
                                $allMails += $item
                            }
                        }
                    } catch {
                        continue
                    }
                }
            } catch {
                Write-Warning "Could not search folder $fid : $($_.Exception.Message)"
            }
        }

        if ($allMails.Count -eq 0) {
            Write-Host "No emails found for ConversationID: $ConversationID"
            exit 0
        }

        $sorted = $allMails | Sort-Object { $_.ReceivedTime }
        $convTopic = try { [string]$sorted[0].ConversationTopic } catch { "(unknown)" }

        Write-Host "=== Thread: $convTopic ==="
        Write-Host "Messages: $($sorted.Count)"
        Write-Host ""

        $idx = 0
        foreach ($mail in $sorted) {
            $idx++
            Format-Email -Mail $mail -Index $idx
        }
    }

} finally {
    if ($outlook) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null
    }
}
