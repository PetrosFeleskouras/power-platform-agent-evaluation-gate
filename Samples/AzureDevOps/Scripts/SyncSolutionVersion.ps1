param(
    [string]$serverURL = $env:DEPLOYMENT_URL,
    [string]$clientId = $env:DEPLOYMENT_CLIENT_ID,
    [string]$clientSecret = $env:DEPLOYMENT_CLIENT_SECRET,
    [string]$solutionUniqueName = $env:SOLUTION_NAME,
    [bool]$incrementBuild = $true,
    [bool]$incrementRevision = $false,
    [string]$startingFilePath = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PublicationSafety.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DataverseConnection.psm1') -Force
Assert-SolutionName $solutionUniqueName
if ($incrementBuild -eq $incrementRevision) { throw 'Choose exactly one version increment.' }
try {
    $connection = Connect-DeploymentDataverse $serverURL $clientId $clientSecret
    $solutions = @(Get-DataverseRecord -Connection $connection -TableName solution `
        -FilterValues @{uniquename=$solutionUniqueName} -Columns version)
}
catch { throw 'Unable to read the source version. Check the private environment and service connection.' }
if ($solutions.Count -ne 1) { throw 'Expected exactly one source solution.' }
$current = [version]$solutions[0].version
$manifestPath = Join-Path $startingFilePath "..\Solutions\$solutionUniqueName\Other\Solution.xml"
$previous = $current
if (Test-Path -LiteralPath $manifestPath) {
    [xml]$xml = Get-Content -LiteralPath $manifestPath -Raw
    $previous = [version]$xml.ImportExportXml.SolutionManifest.Version
}
$next = Get-NextSolutionVersion $current $previous $incrementBuild $incrementRevision
Write-Host "##vso[task.setvariable variable=newSolutionVersion]$next"
Write-Host 'Source solution version increment calculated.'
