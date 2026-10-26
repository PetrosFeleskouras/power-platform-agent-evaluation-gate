[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$EnvironmentId,
    [Parameter(Mandatory)][string]$CallerObjectId,
    [Parameter(Mandatory)][string]$ConnectionName,
    [Parameter(Mandatory)][string]$Name
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'BridgeTools.psm1') -Force
$request=New-BridgeRequest -EnvironmentId $EnvironmentId -CallerObjectId $CallerObjectId -ConnectionName $ConnectionName -Name $Name
if (-not $PSCmdlet.ShouldProcess('New, stopped Power Automate flow','Create configured bridge copy')) { return }
$token=az account get-access-token --resource 'https://service.flow.microsoft.com/' --query accessToken -o tsv --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure CLI could not acquire a Flow token. Sign in to the intended tenant with az login.'
}
$base="https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$(([guid]$EnvironmentId).ToString())/flows"
$headers=@{Authorization="Bearer $token";Accept='application/json'}
try {
    $existing=Invoke-RestMethod -Uri "${base}?api-version=2016-11-01" -Headers $headers -MaximumRedirection 0 -TimeoutSec 90
    if ($existing.PSObject.Properties.Name -notcontains 'value' -or
        $existing.PSObject.Properties.Name -contains 'nextLink') {
        throw 'Flow inventory incomplete; duplicate-name protection cannot be verified.'
    }
    if (@($existing.value|Where-Object { $_.properties.displayName -eq $Name }).Count) {
        throw 'A flow with this name already exists. Choose a new name; this installer never updates flows.'
    }
}
catch { throw 'Unable to validate a complete flow inventory or the name already exists. No creation attempted.' }
try {
    $created=Invoke-RestMethod -Method Post -Uri "${base}?api-version=2016-11-01" -Headers $headers `
        -ContentType 'application/json' -Body ($request|ConvertTo-Json -Depth 100) -MaximumRedirection 0 -TimeoutSec 120
}
catch { throw 'Bridge creation failed or timed out. Inspect your private flow list before retrying; raw details withheld.' }
$id=[string]$created.name
Assert-BindingGuid $id
try {
    $readback=Invoke-RestMethod -Uri "$base/${id}?api-version=2016-11-01" -Headers $headers -MaximumRedirection 0 -TimeoutSec 90
    Assert-BridgeReadback $readback $EnvironmentId $CallerObjectId $ConnectionName
}
catch { throw "New flow $id needs private readback inspection. Do not enable it until configuration is verified." }
Write-Host 'New bridge created in Stopped state with restricted caller authentication. No evaluation was started.'
[pscustomobject]@{flowId=$id;state='Stopped'}
