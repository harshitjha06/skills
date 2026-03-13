# install.ps1 — Install skills and agents for VS Code Copilot (Windows)
param(
    [switch]$SkillsOnly,
    [switch]$AgentsOnly
)

$skillsDest = Join-Path $HOME ".copilot\skills"
$agentsDest = Join-Path $env:APPDATA "Code\User\prompts"

if (-not $AgentsOnly) {
    if (-not (Test-Path $skillsDest)) { New-Item $skillsDest -ItemType Directory -Force | Out-Null }
    $count = 0
    Get-ChildItem "$PSScriptRoot\skills" -Directory | ForEach-Object {
        Copy-Item $_.FullName "$skillsDest\$($_.Name)" -Recurse -Force
        $count++
    }
    Write-Host "Installed $count skills to $skillsDest"
}

if (-not $SkillsOnly) {
    if (-not (Test-Path $agentsDest)) { New-Item $agentsDest -ItemType Directory -Force | Out-Null }
    $count = 0
    Get-ChildItem "$PSScriptRoot\agents\*.agent.md" | ForEach-Object {
        Copy-Item $_.FullName $agentsDest -Force
        $count++
    }
    Write-Host "Installed $count agents to $agentsDest"
}

Write-Host "Done. Restart VS Code or open a new Copilot chat to use them."
