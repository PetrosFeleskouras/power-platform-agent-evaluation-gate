param(
    [string]$settingsFilePath = $env:SETTINGS_FILE_PATH,
    [string]$environmentVariablesValues = $env:ENVIRONMENT_VARIABLE_VALUES,
    [string]$connectionTokens = $env:CONNECTION_REFERENCE_TOKENS,
    [string]$environmentUrl = $env:DEPLOYMENT_URL,
    [string]$applicationId = $env:DEPLOYMENT_CLIENT_ID,
    [string]$clientSecret = $env:DEPLOYMENT_CLIENT_SECRET,
    [string]$tenantId = $env:DEPLOYMENT_TENANT_ID
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    if ([string]::IsNullOrWhiteSpace($environmentVariablesValues) -or
        [string]::IsNullOrWhiteSpace($connectionTokens) -or
        -not $environmentVariablesValues.Trim().StartsWith('[') -or
        -not $connectionTokens.Trim().StartsWith('[')) { throw 'Mappings must be JSON arrays.' }
    $settings = Get-Content -LiteralPath $settingsFilePath -Raw | ConvertFrom-Json -AsHashtable
    $values = @($environmentVariablesValues | ConvertFrom-Json)
    $connections = @($connectionTokens | ConvertFrom-Json)
    if ($settings.EnvironmentVariables -isnot [array] -or $settings.ConnectionReferences -isnot [array]) {
        throw 'Settings must contain both deployment-setting arrays.'
    }
}
catch { throw 'Invalid target settings or connection mapping JSON. Values and parser details were withheld.' }
foreach ($item in @($settings.EnvironmentVariables)) {
    $matches = @($values | Where-Object { $_.StaticToken -ceq $item.Value })
    if ($matches.Count -ne 1 -or $null -eq $matches[0].Value) {
        throw 'Environment-variable binding is missing or ambiguous; values withheld.'
    }
    $item.Value = $matches[0].Value
}
foreach ($item in @($settings.ConnectionReferences)) {
    $matches = @($connections | Where-Object {
        $_.StaticToken -ceq $item.ConnectionId -and $_.ConnectorId -ceq $item.ConnectorId
    })
    if ($matches.Count -ne 1 -or [string]::IsNullOrWhiteSpace($matches[0].ConnectionId) -or
        $matches[0].ConnectionId -match '\$\(|[<>]') {
        throw 'Supply exactly one explicit target ConnectionId for each connection token; values withheld.'
    }
    $item.ConnectionId = [string]$matches[0].ConnectionId
}
$settings | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $settingsFilePath -Encoding utf8
Write-Host 'Target settings resolved in the working copy; values withheld.'
