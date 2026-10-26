Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Assert-BindingGuid {
    param([string]$Value)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($Value,[ref]$id) -or $id -eq [guid]::Empty) {
        throw 'A nonempty environment/caller GUID is required before flow creation.'
    }
}

function New-BridgeRequest {
    param(
        [Parameter(Mandatory)][string]$EnvironmentId,
        [Parameter(Mandatory)][string]$CallerObjectId,
        [Parameter(Mandatory)][string]$ConnectionName,
        [Parameter(Mandatory)][string]$Name
    )
    Assert-BindingGuid $EnvironmentId
    Assert-BindingGuid $CallerObjectId
    if ($ConnectionName -cnotmatch '^shared-microsoftcopi[a-z0-9-]+$' -or
        [string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 100 -or $Name -match '[\x00-\x1f]') {
        throw 'Supply an existing Copilot Studio connection name and a valid new flow display name.'
    }
    $definition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'definition.template.json') -Raw | ConvertFrom-Json -AsHashtable
    $definition.triggers.manual.inputs.triggerAllowedUsers=([guid]$CallerObjectId).ToString()
    $definition.actions.Validate_environment.inputs.schema.properties.sourceEnvironmentId.enum=@(([guid]$EnvironmentId).ToString())
    $definition.actions.Evaluate_and_wait.actions.Start_evaluation.inputs.parameters.body.mcsConnectionId=$ConnectionName
    if (($definition|ConvertTo-Json -Depth 100) -match '__[A-Z_]+__') { throw 'Bridge still has unresolved binding placeholders.' }
    @{
        properties=@{
            displayName=$Name
            state='Stopped'
            definition=$definition
            connectionReferences=@{
                shared_microsoftcopilotstudio=@{
                    connectionName=$ConnectionName
                    source='Embedded'
                    id='/providers/Microsoft.PowerApps/apis/shared_microsoftcopilotstudio'
                }
            }
        }
    }
}

function Assert-BridgeReadback {
    param($Flow,[string]$EnvironmentId,[string]$CallerObjectId,[string]$ConnectionName)
    $properties=$Flow.properties
    $definition=$properties.definition
    if ($properties.state -cne 'Stopped' -or
        $definition.triggers.manual.inputs.triggerAuthenticationType -cne 'User' -or
        $definition.triggers.manual.inputs.triggerAllowedUsers -ine $CallerObjectId -or
        $definition.actions.Validate_environment.inputs.schema.properties.sourceEnvironmentId.enum[0] -ine $EnvironmentId -or
        $properties.connectionReferences.shared_microsoftcopilotstudio.connectionName -cne $ConnectionName -or
        $properties.connectionReferences.shared_microsoftcopilotstudio.source -cne 'Embedded' -or
        $definition.actions.Evaluate_and_wait.actions.Start_evaluation.inputs.parameters.body.mcsConnectionId -cne $ConnectionName -or
        $definition.actions.Evaluation_response.operationOptions -cne 'Asynchronous' -or
        $definition.actions.Error_response.operationOptions -cne 'Asynchronous') {
        throw 'Bridge readback does not match the stopped, restricted configuration. Do not enable it.'
    }
}

Export-ModuleMember -Function Assert-BindingGuid,New-BridgeRequest,Assert-BridgeReadback
