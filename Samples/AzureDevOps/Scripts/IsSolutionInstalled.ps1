param(
    [string]$serverURL = $env:DEPLOYMENT_URL,
    [string]$clientId = $env:DEPLOYMENT_CLIENT_ID,
    [string]$clientSecret = $env:DEPLOYMENT_CLIENT_SECRET,
    [string]$solutionUniqueName = $env:SOLUTION_NAME,
    [string]$solutionFilePath = $env:SOLUTION_FILE_PATH
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PublicationSafety.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DataverseConnection.psm1') -Force
Assert-SolutionName $solutionUniqueName
try {
    $connection = Connect-DeploymentDataverse $serverURL $clientId $clientSecret
    $installed = @(Get-DataverseRecord -Connection $connection -TableName solution -FilterValues @{uniquename=$solutionUniqueName} -Columns version)
    $upgrade = @(Get-DataverseRecord -Connection $connection -TableName solution -FilterValues @{uniquename=($solutionUniqueName+'_Upgrade')} -Columns version)
}
catch { throw 'Solution installation check failed. Private connection details were withheld.' }
if ($installed.Count -gt 1 -or $upgrade.Count -gt 1) { throw 'Ambiguous installed solution.' }
$status = if ($installed.Count) { ([version]$installed[0].version).ToString() } else { 'NotInstalled' }
$upgradeStatus = if ($upgrade.Count) { ([version]$upgrade[0].version).ToString() } else { 'NotInstalled' }
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $solutionFilePath).Path)
try {
    $reader = [IO.StreamReader]::new($zip.GetEntry('solution.xml').Open())
    try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ([string]$manifest.ImportExportXml.SolutionManifest.UniqueName -cne $solutionUniqueName) { throw 'Package belongs to another solution.' }
    $attempted = ([version]$manifest.ImportExportXml.SolutionManifest.Version).ToString()
}
finally { $zip.Dispose() }
Write-Host "##vso[task.setvariable variable=currentSolutionStatus]$status"
Write-Host "##vso[task.setvariable variable=currentUpgradeSolutionStatus]$upgradeStatus"
Write-Host "##vso[task.setvariable variable=attemptedSolutionVersion]$attempted"
Write-Host 'Solution installation status verified; connection details withheld.'
