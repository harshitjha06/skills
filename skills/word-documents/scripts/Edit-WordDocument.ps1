<#
.SYNOPSIS
    Edits an existing Word document via COM automation using targeted operations.

.DESCRIPTION
    Opens a .docx/.doc document and performs one operation per run:
    - Find/replace text globally
    - Insert text after a heading
    - Replace a section body under a heading
    Saves to a new output path by default (safe), or in-place when -InPlace is provided.

.PARAMETER FilePath
    Full path to the source .docx/.doc file.

.PARAMETER OutputPath
    Optional output path. If omitted and -InPlace is not set, "<name>-edited<ext>" is used.

.PARAMETER InPlace
    Save changes back to the original file path.

.PARAMETER EnableTrackChanges
    If set, enables Word Track Changes while applying edits.

.PARAMETER DryRun
    If set, reports intended edits without saving any file.

.EXAMPLE
    powershell -STA -NoProfile -File Edit-WordDocument.ps1 -FilePath "C:\docs\spec.docx" -FindText "foo" -ReplaceText "bar"

.EXAMPLE
    powershell -STA -NoProfile -File Edit-WordDocument.ps1 -FilePath "C:\docs\spec.docx" -ReplaceSection "Architecture" -SectionContent "Updated architecture details."
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string]$OutputPath,

    [switch]$InPlace,

    [switch]$EnableTrackChanges,

    [switch]$DryRun,

    [string]$FindText,
    [string]$ReplaceText,

    [string]$InsertAfterHeading,
    [string]$InsertContent,

    [string]$ReplaceSection,
    [string]$SectionContent
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Normalize-WordText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return ($Text -replace '[\r\n\a\x07]', '').Trim()
}

function Resolve-HeadingMatch {
    param(
        [object]$Doc,
        [string]$HeadingText
    )

    for ($i = 1; $i -le $Doc.Paragraphs.Count; $i++) {
        $para = $Doc.Paragraphs.Item($i)
        $level = [int]$para.OutlineLevel
        if ($level -ge 1 -and $level -le 9) {
            $text = Normalize-WordText $para.Range.Text
            if ($text.IndexOf($HeadingText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return [pscustomobject]@{
                    Index = $i
                    Level = $level
                    Text  = $text
                    Para  = $para
                }
            }
        }
    }

    Write-Error "Heading not found: $HeadingText"
    exit 1
}

function Resolve-SectionBodyRange {
    param(
        [object]$Doc,
        [object]$HeadingMatch
    )

    $start = $HeadingMatch.Para.Range.End
    $end = $Doc.Content.End
    for ($i = $HeadingMatch.Index + 1; $i -le $Doc.Paragraphs.Count; $i++) {
        $nextPara = $Doc.Paragraphs.Item($i)
        $nextLevel = [int]$nextPara.OutlineLevel
        if ($nextLevel -ge 1 -and $nextLevel -le $HeadingMatch.Level) {
            $end = $nextPara.Range.Start
            break
        }
    }
    return $Doc.Range($start, $end)
}

if (-not (Test-Path -LiteralPath $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

$FilePath = (Resolve-Path $FilePath).Path

$hasFind = $PSBoundParameters.ContainsKey('FindText') -or $PSBoundParameters.ContainsKey('ReplaceText')
if ($hasFind -and [string]::IsNullOrWhiteSpace($FindText)) {
    Write-Error "Find/replace requires -FindText to be non-empty. -ReplaceText may be empty to delete matches."
    exit 1
}
if ($hasFind -and -not $PSBoundParameters.ContainsKey('ReplaceText')) {
    Write-Error "Find/replace requires both -FindText and -ReplaceText. Use -ReplaceText '' to delete matches."
    exit 1
}

$hasInsert = (-not [string]::IsNullOrWhiteSpace($InsertAfterHeading)) -or (-not [string]::IsNullOrWhiteSpace($InsertContent))
if ($hasInsert -and ([string]::IsNullOrWhiteSpace($InsertAfterHeading) -or [string]::IsNullOrWhiteSpace($InsertContent))) {
    Write-Error "Insert operation requires both -InsertAfterHeading and -InsertContent."
    exit 1
}

$hasSectionReplace = (-not [string]::IsNullOrWhiteSpace($ReplaceSection)) -or (-not [string]::IsNullOrWhiteSpace($SectionContent))
if ($hasSectionReplace -and ([string]::IsNullOrWhiteSpace($ReplaceSection) -or [string]::IsNullOrWhiteSpace($SectionContent))) {
    Write-Error "Section replace operation requires both -ReplaceSection and -SectionContent."
    exit 1
}

$operationCount = ([int]$hasFind + [int]$hasInsert + [int]$hasSectionReplace)
if ($operationCount -ne 1) {
    Write-Error "Specify exactly one operation: find/replace, insert-after-heading, or replace-section."
    exit 1
}

if ($InPlace -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Error "Use either -InPlace or -OutputPath, not both."
    exit 1
}

if (-not $InPlace) {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $dir = [System.IO.Path]::GetDirectoryName($FilePath)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $ext = [System.IO.Path]::GetExtension($FilePath)
        $OutputPath = Join-Path $dir "$name-edited$ext"
    }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
}

$word = $null
$doc = $null

try {
    $word = New-Object -ComObject Word.Application
} catch {
    Write-Error "Failed to create Word COM object. Ensure Microsoft Word is installed."
    exit 1
}

try {
    $word.Visible = $false
    $word.DisplayAlerts = 0  # wdAlertsNone
    $doc = $word.Documents.Open($FilePath, $false, $false)
    $doc.TrackRevisions = [bool]$EnableTrackChanges

    $changeCount = 0
    $actionSummary = ""

    if ($hasFind) {
        # Count matches using the same COM Find engine that performs the replacement.
        $counter = $doc.Content.Find
        $counter.ClearFormatting()
        while ($counter.Execute($FindText, $false, $false, $false, $false, $false, $true, 0, $false, "", 0)) {  # wdFindStop + wdReplaceNone
            $changeCount++
        }

        if (-not $DryRun -and $changeCount -gt 0) {
            $findAll = $doc.Content.Find
            $findAll.ClearFormatting()
            $findAll.Replacement.ClearFormatting()
            [void]$findAll.Execute($FindText, $false, $false, $false, $false, $false, $true, 1, $false, $ReplaceText, 2)  # wdFindContinue + wdReplaceAll
        }
        $actionSummary = "find/replace"
    }
    elseif ($hasInsert) {
        $heading = Resolve-HeadingMatch -Doc $doc -HeadingText $InsertAfterHeading
        $insertAt = $heading.Para.Range.End
        if (-not $DryRun) {
            $insertRange = $doc.Range($insertAt, $insertAt)
            $insertRange.Text = "$InsertContent`r"
        }
        $changeCount = 1
        $actionSummary = "insert after heading '$($heading.Text)'"
    }
    elseif ($hasSectionReplace) {
        $heading = Resolve-HeadingMatch -Doc $doc -HeadingText $ReplaceSection
        $bodyRange = Resolve-SectionBodyRange -Doc $doc -HeadingMatch $heading
        if (-not $DryRun) {
            $bodyRange.Text = "$SectionContent`r"
        }
        $changeCount = 1
        $actionSummary = "replace section '$($heading.Text)'"
    }

    if ($DryRun) {
        Write-Host "Dry run complete: $actionSummary; changes detected: $changeCount"
        return
    }

    if ($InPlace) {
        $doc.Save()
        Write-Host "Document updated in place: $FilePath (operation: $actionSummary, changes: $changeCount)"
    } else {
        $doc.SaveAs2($OutputPath)
        Write-Host "Document saved: $OutputPath (operation: $actionSummary, changes: $changeCount)"
    }
} catch {
    Write-Error "Failed to edit document: $($_.Exception.Message)"
    exit 1
} finally {
    if ($doc) {
        try { $doc.Close($false) } catch { }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null } catch { }
    }
    if ($word) {
        try { $word.Quit() } catch { }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch { }
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
