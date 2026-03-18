<#
.SYNOPSIS
    Creates a new section in a OneNote notebook.

.DESCRIPTION
    Uses the OneNote COM API (UpdateHierarchy) to create a new section in a specified notebook.
    Must be run with: powershell -STA -NoProfile -File New-OneNoteSection.ps1 -NotebookId <id> -Name <name>

.PARAMETER NotebookId
    The OneNote notebook ID to create the section in (obtained from Get-OneNoteHierarchy.ps1).

.PARAMETER Name
    The name for the new section.

.EXAMPLE
    powershell -STA -NoProfile -File New-OneNoteSection.ps1 -NotebookId "{ABC...}" -Name "Meeting Notes"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$NotebookId,

    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$oneNote = $null
try {
    $oneNote = New-Object -ComObject OneNote.Application
} catch {
    Write-Error "Failed to create OneNote COM object. Ensure OneNote desktop app is installed and running."
    exit 1
}

try {
    $xmlns = "http://schemas.microsoft.com/office/onenote/2013/onenote"

    # Get the notebook hierarchy to find the target notebook
    $hierarchyXml = ""
    try {
        # Scope 1 = hsSections
        $oneNote.GetHierarchy($NotebookId, 1, [ref]$hierarchyXml)
    } catch {
        Write-Error "GetHierarchy failed: $($_.Exception.Message)"
        exit 1
    }

    [xml]$parsed = $hierarchyXml
    $ns = @{ one = $xmlns }

    # Find the notebook node
    $notebook = $parsed.DocumentElement
    if (-not $notebook -or $notebook.LocalName -ne "Notebook") {
        # If GetHierarchy with a notebook ID returns Notebooks wrapper, find the notebook
        $nbNode = Select-Xml -Xml $parsed -XPath "//one:Notebook[@ID='$NotebookId']" -Namespace $ns
        if ($nbNode) {
            $notebook = $nbNode.Node
        } else {
            Write-Error "Notebook not found with ID: $NotebookId"
            exit 1
        }
    }

    # Create the new section element — insert before SectionGroups (schema requires sections first)
    $newSection = $parsed.CreateElement("one", "Section", $xmlns)
    $newSection.SetAttribute("name", $Name)
    $firstSectionGroup = Select-Xml -Xml $notebook -XPath "one:SectionGroup" -Namespace $ns | Select-Object -First 1
    if ($firstSectionGroup) {
        $notebook.InsertBefore($newSection, $firstSectionGroup.Node) | Out-Null
    } else {
        $notebook.AppendChild($newSection) | Out-Null
    }

    # Commit the hierarchy change
    try {
        $oneNote.UpdateHierarchy($parsed.OuterXml)
    } catch {
        Write-Error "UpdateHierarchy failed: $($_.Exception.Message)"
        exit 1
    }

    # Re-fetch hierarchy to get the new section's assigned ID
    $sectionId = $null
    try {
        $updatedXml = ""
        $oneNote.GetHierarchy($NotebookId, 1, [ref]$updatedXml)
        [xml]$updatedParsed = $updatedXml
        # Iterate sections instead of XPath to avoid injection from special chars in $Name
        $sections = Select-Xml -Xml $updatedParsed -XPath "//one:Section" -Namespace $ns
        foreach ($sec in $sections) {
            if ($sec.Node.GetAttribute("name") -eq $Name) {
                $sectionId = $sec.Node.ID
            }
        }
    } catch {
        # Section was created but we couldn't retrieve its ID
    }

    if ($sectionId) {
        Write-Host "Section created successfully."
        Write-Host "Name: $Name"
        Write-Host "SectionID: $sectionId"
    } else {
        Write-Host "Section created successfully."
        Write-Host "Name: $Name"
        Write-Host "SectionID: (re-run Get-OneNoteHierarchy.ps1 to retrieve)"
    }
} finally {
    if ($oneNote) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($oneNote) | Out-Null
    }
}
