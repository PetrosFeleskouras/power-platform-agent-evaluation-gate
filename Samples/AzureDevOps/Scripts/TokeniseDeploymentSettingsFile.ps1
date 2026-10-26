param(
    [Parameter(Mandatory)][string]$settingsFilePath,
    [string]$environmentVariablesTokens = $env:ENVIRONMENT_VARIABLE_TOKENS,
    [string]$connectionReferencesTokens = $env:CONNECTION_REFERENCE_TOKENS
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    if ([string]::IsNullOrWhiteSpace($environmentVariablesTokens) -or
        [string]::IsNullOrWhiteSpace($connectionReferencesTokens) -or
        -not $environmentVariablesTokens.Trim().StartsWith('[') -or
        -not $connectionReferencesTokens.Trim().StartsWith('[')) { throw 'Mappings must be JSON arrays.' }
    $settings = Get-Content -LiteralPath $settingsFilePath -Raw | ConvertFrom-Json -AsHashtable
    $envTokens = @($environmentVariablesTokens | ConvertFrom-Json)
    $connectionTokens = @($connectionReferencesTokens | ConvertFrom-Json)
    if ($settings.EnvironmentVariables -isnot [array] -or $settings.ConnectionReferences -isnot [array]) {
        throw 'Settings must contain both deployment-setting arrays.'
    }
}
catch { throw 'Invalid source settings or token mapping JSON. Values and parser details were withheld.' }
foreach ($item in @($settings.EnvironmentVariables)) {
    $matches = @($envTokens | Where-Object { $_.SchemaName -ceq $item.SchemaName })
    if ($matches.Count -ne 1 -or [string]::IsNullOrWhiteSpace($matches[0].StaticToken)) {
        throw 'An environment-variable token mapping is missing or ambiguous. Values were not logged.'
    }
    $item.Value = [string]$matches[0].StaticToken
}
foreach ($item in @($settings.ConnectionReferences)) {
    $matches = @($connectionTokens | Where-Object { $_.ConnectorId -ceq $item.ConnectorId })
    if ($matches.Count -ne 1 -or [string]::IsNullOrWhiteSpace($matches[0].StaticToken)) {
        throw 'A connection-reference token mapping is missing or ambiguous. Values were not logged.'
    }
    $item.ConnectionId = [string]$matches[0].StaticToken
}
$settings | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $settingsFilePath -Encoding utf8
Write-Host 'Deployment settings tokenized; values withheld.'
