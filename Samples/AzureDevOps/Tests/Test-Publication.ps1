$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot))
$scripts=Join-Path (Split-Path $PSScriptRoot) 'Scripts'
Import-Module (Join-Path $scripts 'PublicationSafety.psm1') -Force
Import-Module (Join-Path $scripts 'DataverseConnection.psm1') -Force
Import-Module (Join-Path $repo 'PowerAutomate\Bridge\BridgeTools.psm1') -Force
$script:count=0
function Check([string]$Name,[scriptblock]$Body) {
    & $Body
    $script:count++
    Write-Host "PASS: $Name"
}
function Reject([scriptblock]$Body) {
    $failed=$false
    try { & $Body | Out-Null } catch { $failed=$true }
    if(-not $failed){throw 'Invalid input was accepted.'}
}
function Assert([bool]$Value,[string]$Message) { if(-not $Value){throw $Message} }
$environment='22222222-2222-2222-2222-222222222222'
$caller='44444444-4444-4444-4444-444444444444'

Check 'Valid solution name' { Assert-SolutionName 'ExampleSolution' }
Check 'Reject path traversal in solution name' { Reject { Assert-SolutionName '..\other' } }
Check 'Reject user-supplied script syntax in solution name' { Reject { Assert-SolutionName 'name;Write-Host' } }
Check 'Accept expected private repository metadata' {
    Assert-PrivateRepositoryMetadata @{id='repo';project=@{id='project';visibility='private'}} 'repo' 'project'
}
Check 'Reject public runtime repository' {
    Reject { Assert-PrivateRepositoryMetadata @{id='repo';project=@{id='project';visibility='public'}} 'repo' 'project' }
}
Check 'Reject another repository identity' {
    Reject { Assert-PrivateRepositoryMetadata @{id='other';project=@{id='project';visibility='private'}} 'repo' 'project' }
}
Check 'Reject missing project visibility' {
    Reject { Assert-PrivateRepositoryMetadata @{id='repo';project=@{id='project'}} 'repo' 'project' }
}
Check 'Reject GitHub runtime before authentication' {
    $previous=$env:BUILD_REPOSITORY_PROVIDER
    try {$env:BUILD_REPOSITORY_PROVIDER='GitHub';Reject {Assert-PrivateRuntimeRepository}}
    finally {$env:BUILD_REPOSITORY_PROVIDER=$previous}
}
Check 'Clean synthetic source accepted' { Assert-TextPrivacy '{"instruction":"Use the fictional onboarding policy."}' }
Check 'Email fixture rejected without logging its value' {
    $value='sample.person@example.invalid'
    $message=$null
    try { Assert-TextPrivacy $value }
    catch { $message=$_.Exception.Message }
    Assert ($null-ne$message) 'Email was not rejected.'
    Assert (-not $message.Contains($value)) 'Matched email was logged.'
}
Check 'Reject private key marker' { Reject { Assert-TextPrivacy ('-----BEGIN '+'PRIVATE KEY-----') } }
Check 'Reject token-like fixture' { Reject { Assert-TextPrivacy ('ghp_'+('a'*30)) } }
Check 'Reject signed callback URL fixture' { Reject { Assert-TextPrivacy ('https://example.invalid/?sig='+('a'*40)) } }
Check 'Reject user-profile paths' { Reject { Assert-TextPrivacy 'C:\Users\SyntheticUser\file.json' } }
Check 'Reject environment endpoint fixture' { Reject { Assert-TextPrivacy 'https://synthetic.crm.dynamics.com' } }
Check 'Reject literal secret setting' { Reject { Assert-TextPrivacy ('{"clientSecret":"'+('a'*24)+'"}') } }
Check 'Build version advances from the newer committed version' {
    Assert ((Get-NextSolutionVersion ([version]'1.0.1.0') ([version]'1.0.3.2')) -eq '1.0.4.0') 'Incorrect build increment.'
}
Check 'Revision increment preserves major minor and build' {
    Assert ((Get-NextSolutionVersion ([version]'2.1.3.4') ([version]'1.0.3.2') $false $true) -eq '2.1.3.5') 'Incorrect revision increment.'
}
Check 'Conflicting version increment flags reject' {
    Reject {Get-NextSolutionVersion ([version]'1.0.0.0') ([version]'1.0.0.0') $true $true}
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('publication-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
    $solution=Join-Path $temp 'Samples\AzureDevOps\Solutions\ExampleSolution'
    $settings=Join-Path $temp 'Samples\AzureDevOps\Settings\ExampleSolution.json'
    $null=New-Item -ItemType Directory -Path (Join-Path $solution 'Other') -Force
    $null=New-Item -ItemType Directory -Path (Split-Path $settings) -Force
    '<solution>one</solution>' | Set-Content -LiteralPath (Join-Path $solution 'Other\Solution.xml')
    '{"EnvironmentVariables":[],"ConnectionReferences":[]}' | Set-Content -LiteralPath $settings
    'initial' | Set-Content -LiteralPath (Join-Path $temp 'unrelated.txt')
    $null=Invoke-CheckedGit $temp @('init','--initial-branch=main')
    $null=Invoke-CheckedGit $temp @('config','user.name','Test Automation')
    $null=Invoke-CheckedGit $temp @('config','user.email','automation@example.invalid')
    $null=Invoke-CheckedGit $temp @('add','.')
    $null=Invoke-CheckedGit $temp @('commit','-m','Synthetic baseline')
    '<solution>two</solution>' | Set-Content -LiteralPath (Join-Path $solution 'Other\Solution.xml')
    'sample.person@example.invalid' | Set-Content -LiteralPath (Join-Path $temp 'unrelated.txt')
    Check 'Scoped staging excludes unrelated workspace changes' {
        $staged=@(Add-SelectedSource $temp 'ExampleSolution')
        Assert ($staged.Count-eq 1-and$staged[0]-eq'Samples/AzureDevOps/Solutions/ExampleSolution/Other/Solution.xml') 'Incorrect staging scope.'
    }
    $null=Invoke-CheckedGit $temp @('restore','--staged','.')
    Check 'Email in selected source rejected before staging' {
        $file=Join-Path $solution 'Other\private.txt'
        try {
            'sample.person@example.invalid' | Set-Content -LiteralPath $file
            Reject { Add-SelectedSource $temp 'ExampleSolution' }
            Assert (@(Invoke-CheckedGit $temp @('diff','--cached','--name-only')).Count-eq 0) 'Rejected source was staged.'
        } finally {Remove-Item -LiteralPath $file}
    }
    Check 'Binary source is rejected for manual review' {
        $file=Join-Path $solution 'test.png'
        try {[IO.File]::WriteAllBytes($file,[byte[]]@(0,1,2));Reject {Assert-SourceFilesPrivacy $temp 'ExampleSolution'}}
        finally {Remove-Item -LiteralPath $file}
    }
    Check 'Existing staged unrelated file blocks commit' {
        $null=Invoke-CheckedGit $temp @('add','--','unrelated.txt')
        Reject {Add-SelectedSource $temp 'ExampleSolution'}
        $null=Invoke-CheckedGit $temp @('restore','--staged','.')
    }
    Check 'Tokenization retains keys and removes values' {
        '{"EnvironmentVariables":[{"SchemaName":"sample_config","Value":"private-value"}],"ConnectionReferences":[{"LogicalName":"sample_connection","ConnectorId":"connector","ConnectionId":"private-connection"}]}' |
            Set-Content -LiteralPath $settings
        $envTokens='[{"SchemaName":"sample_config","StaticToken":"CONFIG_TOKEN"}]'
        $connTokens='[{"ConnectorId":"connector","StaticToken":"CONNECTION_TOKEN"}]'
        $output=& (Join-Path $scripts 'TokeniseDeploymentSettingsFile.ps1') -settingsFilePath $settings `
            -environmentVariablesTokens $envTokens -connectionReferencesTokens $connTokens 6>&1
        $data=Get-Content -LiteralPath $settings -Raw|ConvertFrom-Json
        Assert ($data.EnvironmentVariables[0].Value-eq'CONFIG_TOKEN'-and$data.ConnectionReferences[0].ConnectionId-eq'CONNECTION_TOKEN') 'Tokenization mismatch.'
        Assert (($output-join' ')-notmatch'private-value|private-connection') 'Private values were logged.'
    }
    Check 'Target transformation uses explicit bindings without logging them' {
        $out=& (Join-Path $scripts 'TransformDeploymentSettingsFile.ps1') -settingsFilePath $settings `
            -environmentVariablesValues '[{"StaticToken":"CONFIG_TOKEN","Value":"private-target-value"}]' `
            -connectionTokens '[{"StaticToken":"CONNECTION_TOKEN","ConnectorId":"connector","ConnectionId":"private-target-connection"}]' 6>&1
        $data=Get-Content -LiteralPath $settings -Raw|ConvertFrom-Json
        Assert ($data.EnvironmentVariables[0].Value-eq'private-target-value'-and$data.ConnectionReferences[0].ConnectionId-eq'private-target-connection') 'Target bindings mismatch.'
        Assert (($out-join' ')-notmatch'private-target') 'Resolved target values were logged.'
    }
    Check 'Missing token bindings reject instead of guessing' {
        Reject {& (Join-Path $scripts 'TokeniseDeploymentSettingsFile.ps1') -settingsFilePath $settings -environmentVariablesTokens '[]' -connectionReferencesTokens '[]'}
    }
    Check 'Malformed target mapping does not echo private values in parser errors' {
        $secretMarker='private-parser-fixture'
        $message=$null
        try { & (Join-Path $scripts 'TransformDeploymentSettingsFile.ps1') -settingsFilePath $settings -environmentVariablesValues "[${secretMarker}" -connectionTokens '[]' }
        catch {$message=$_.Exception.Message}
        Assert ($null-ne$message-and-not$message.Contains($secretMarker)) 'Parser error exposed private input or malformed input was accepted.'
    }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }

$params=@{EnvironmentId=$environment;CallerObjectId=$caller;ConnectionName='shared-microsoftcopi-synthetic';Name='Synthetic bridge'}
$request=New-BridgeRequest @params
Check 'Bridge is stopped and has an explicit caller restriction' {
    Assert ($request.properties.state-eq'Stopped') 'Flow is enabled by default.'
    Assert ($request.properties.definition.triggers.manual.inputs.triggerAuthenticationType-eq'User') 'Authentication weakened.'
    Assert ($request.properties.definition.triggers.manual.inputs.triggerAllowedUsers-eq$caller) 'Caller binding absent.'
}
Check 'Bridge explicitly binds source environment before discovery' {
    $d=$request.properties.definition
    Assert ($d.actions.Validate_environment.inputs.schema.properties.sourceEnvironmentId.enum[0]-eq$environment) 'Source environment is not pinned.'
    Assert ($d.actions.Validate_environment.inputs.content -is [System.Collections.IDictionary]) 'ParseJson content must be an object, not an unquoted GUID string.'
    Assert ($d.actions.Initialize_result.runAfter.Validate_environment[0]-eq'Succeeded') 'Validation can be bypassed.'
}
Check 'Bridge binds connector and evaluation profile consistently' {
    Assert ($request.properties.connectionReferences.shared_microsoftcopilotstudio.connectionName-eq$params.ConnectionName) 'Connector reference mismatch.'
    Assert ($request.properties.definition.actions.Evaluate_and_wait.actions.Start_evaluation.inputs.parameters.body.mcsConnectionId-eq$params.ConnectionName) 'Profile mismatch.'
}
Check 'Missing or empty caller identity rejected' {
    $p=$params.Clone();$p.CallerObjectId=[guid]::Empty.ToString();Reject {New-BridgeRequest @p}
}
Check 'Invalid connector binding rejected' {
    $p=$params.Clone();$p.ConnectionName='__CONNECTION_NAME__';Reject {New-BridgeRequest @p}
}
Check 'Bridge preserves asynchronous responses and contract version' {
    $d=$request.properties.definition
    Assert ($d.actions.Evaluation_response.operationOptions-eq'Asynchronous'-and$d.actions.Error_response.operationOptions-eq'Asynchronous') 'Asynchronous response missing.'
    Assert ($d.actions.Evaluation_response.inputs.body.schemaVersion-eq 2) 'Contract version changed.'
}
Check 'Bridge preserves bounded polling and no start retry' {
    $a=$request.properties.definition.actions.Evaluate_and_wait.actions
    Assert ($a.Wait_for_evaluation.limit.timeout-eq'PT20M'-and$a.Wait_for_evaluation.limit.count-eq 80) 'Unbounded polling.'
    Assert ($a.Wait_for_evaluation.operationOptions-eq'FailWhenLimitsReached') 'Polling must fail explicitly on exhausted limits.'
    Assert ($a.Start_evaluation.inputs.retryPolicy.type-eq'none') 'Evaluation starts can be retried.'
}
Check 'Bridge requires exactly one matching active evaluation' {
    $d=$request.properties.definition
    $schema=$d.actions.Resolve_evaluation.actions.Validate_match.inputs.schema
    Assert ($schema.minItems-eq 1-and$schema.maxItems-eq 1) 'Ambiguous evaluations could be selected.'
    Assert ($d.actions.Resolve_evaluation.actions.For_each_agent.actions.Filter_named_sets.inputs.where.Contains("'Active'")) 'Inactive evaluations accepted.'
}
Check 'Bridge connector payloads have secure inputs and outputs' {
    $start=$request.properties.definition.actions.Evaluate_and_wait.actions.Start_evaluation
    Assert (($start.runtimeConfiguration.secureData.properties-join',')-eq'inputs,outputs') 'Connector payload history is unprotected.'
}
Check 'Stopped readback matches all supplied bindings' {
    Assert-BridgeReadback $request $environment $caller $params.ConnectionName
}
Check 'Readback rejects wrong environment or connector' {
    Reject {Assert-BridgeReadback $request $caller $caller $params.ConnectionName}
    Reject {Assert-BridgeReadback $request $environment $caller 'shared-microsoftcopi-other'}
}
Check 'Public bridge template contains placeholders rather than instance IDs' {
    $json=Get-Content -LiteralPath (Join-Path $repo 'PowerAutomate\Bridge\definition.template.json') -Raw
    Assert ($json-notmatch'(?i)[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}') 'Instance GUID in template.'
    Assert ($json-notmatch'"operationMetadataId"|"authentication"') 'Instance authentication/metadata survived sanitization.'
    Assert ($json.Contains('__CALLER_OBJECT_ID__')-and$json.Contains('__CONNECTION_NAME__')) 'Expected deployment placeholders.'
}
Check 'New commit template has no requester identity or broad forced staging' {
    $text=Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'Templates\commit-solution-template.yml') -Raw
    Assert ($text-notmatch'Build.RequestedFor|git add --all|--force') 'Unsafe commit behavior in new template.'
    Assert ($text-notmatch'clientSecret.+arguments:') 'Secret interpolated into arguments.'
}
Write-Host "$script:count publication regression checks passed."
