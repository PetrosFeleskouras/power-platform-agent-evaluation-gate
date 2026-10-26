[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Validate','Commit')][string]$Action,
    [string]$SolutionName = $env:SOLUTION_NAME,
    [string]$Root = $env:BUILD_SOURCESDIRECTORY
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PublicationSafety.psm1') -Force
Assert-SolutionName $SolutionName
Assert-PrivateRuntimeRepository
if ($Action -eq 'Validate') {
    if (@(Invoke-CheckedGit $Root @('status','--porcelain')).Count) { throw 'Start with a clean private checkout.' }
    Write-Host 'Private repository, main branch and solution input verified.'
    return
}
$staged = @(Add-SelectedSource $Root $SolutionName)
if (-not $staged.Count) { Write-Host 'Selected solution source is unchanged; no commit needed.'; return }
$null = Invoke-CheckedGit $Root @('config','user.name','ALM Automation')
$null = Invoke-CheckedGit $Root @('config','user.email','alm-automation@example.invalid')
$null = Invoke-CheckedGit $Root @('commit','-m','Update selected Power Platform solution source')
$null = Invoke-CheckedGit $Root @('fetch','origin','main')
$null = Invoke-CheckedGit $Root @('rebase','origin/main')
Assert-SourceFilesPrivacy $Root $SolutionName
$null = Invoke-CheckedGit $Root @('push','origin','HEAD:refs/heads/main')
Write-Host 'Selected source passed automated privacy checks and was committed to the private repository.'
