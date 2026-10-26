$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot))
$scripts=Join-Path (Split-Path $PSScriptRoot) 'Scripts'
Import-Module (Join-Path $scripts 'PublicationSafety.psm1') -Force
Import-Module (Join-Path $scripts 'DataverseConnection.psm1') -Force
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

$flowFiles=@(Get-ChildItem -LiteralPath (Join-Path $repo 'PowerAutomate\Solution\src\Workflows') -Filter '*.json' -File)
Assert ($flowFiles.Count-eq 1) 'Expected exactly one solution flow definition.'
$json=Get-Content -LiteralPath $flowFiles[0].FullName -Raw
$flow=$json|ConvertFrom-Json -AsHashtable
$d=$flow.properties.definition
[xml]$flowMetadata=Get-Content -LiteralPath ($flowFiles[0].FullName+'.data.xml') -Raw
Check 'Solution flow is off and has an environment-variable-backed caller restriction' {
    Assert ([string]$flowMetadata.Workflow.StateCode-ceq'0') 'Flow is enabled by default.'
    Assert ($d.triggers.manual.inputs.triggerAuthenticationType-ceq'User') 'Authentication weakened.'
    Assert ($d.triggers.manual.inputs.triggerAllowedUsers-ceq"@parameters('Bridge Allowed Caller Object ID (aeg_AllowedCallerObjectId)')") 'Caller binding absent.'
}
Check 'Solution flow checks the configured source environment before discovery' {
    Assert ($d.actions.Validate_environment.inputs.content.matches-ceq"@equals(triggerBody()?['sourceEnvironmentId'],parameters('Bridge Source Environment ID (aeg_SourceEnvironmentId)'))") 'Source environment comparison is missing.'
    Assert ($d.actions.Validate_environment.inputs.content -is [System.Collections.IDictionary]) 'ParseJson content must be an object, not an unquoted GUID string.'
    Assert ($d.actions.Initialize_result.runAfter.Validate_environment[0]-eq'Succeeded') 'Validation can be bypassed.'
}
Check 'Solution flow uses a portable connector reference and evaluation-profile parameter' {
    $ref=$flow.properties.connectionReferences.shared_microsoftcopilotstudio
    Assert ($ref.connection.connectionReferenceLogicalName-ceq'aeg_CopilotStudio'-and$ref.runtimeSource-ceq'embedded') 'Connector reference mismatch.'
    Assert ($d.actions.Evaluate_and_wait.actions.Start_evaluation.inputs.parameters.body.mcsConnectionId-ceq"@parameters('Bridge Evaluation Connection Name (aeg_EvaluationConnectionName)')") 'Profile parameter mismatch.'
}
Check 'Caller parameter has a safe default and a configuration guard' {
    $caller=$d.parameters['Bridge Allowed Caller Object ID (aeg_AllowedCallerObjectId)']
    Assert ($caller.defaultValue-ceq'00000000-0000-0000-0000-000000000000'-and$caller.metadata.schemaName-ceq'aeg_AllowedCallerObjectId') 'Caller parameter is not portable.'
    Assert ($d.actions.Validate_configuration.inputs.content.ready.Contains("not(equals(parameters('Bridge Allowed Caller Object ID (aeg_AllowedCallerObjectId)'),'00000000-0000-0000-0000-000000000000'))")) 'Unconfigured caller is not guarded.'
}
Check 'Evaluation profile requires a configured connection name' {
    Assert ($d.parameters['Bridge Evaluation Connection Name (aeg_EvaluationConnectionName)'].defaultValue-ceq'CONFIGURE_CONNECTION_NAME') 'Expected unconfigured profile default.'
    Assert ($d.actions.Validate_configuration.inputs.content.ready.Contains("startsWith(parameters('Bridge Evaluation Connection Name (aeg_EvaluationConnectionName)'),'shared-microsoftcopi-')")) 'Connection-name guard is missing.'
}
Check 'Bridge preserves asynchronous responses and contract version' {
    Assert ($d.actions.Evaluation_response.operationOptions-eq'Asynchronous'-and$d.actions.Error_response.operationOptions-eq'Asynchronous') 'Asynchronous response missing.'
    Assert ($d.actions.Evaluation_response.inputs.body.schemaVersion-eq 2) 'Contract version changed.'
}
Check 'Bridge preserves bounded polling and no start retry' {
    $a=$d.actions.Evaluate_and_wait.actions
    Assert ($a.Wait_for_evaluation.limit.timeout-eq'PT20M'-and$a.Wait_for_evaluation.limit.count-eq 80) 'Unbounded polling.'
    Assert ($a.Wait_for_evaluation.operationOptions-eq'FailWhenLimitsReached') 'Polling must fail explicitly on exhausted limits.'
    Assert ($a.Start_evaluation.inputs.retryPolicy.type-eq'none') 'Evaluation starts can be retried.'
}
Check 'Bridge requires exactly one matching active evaluation' {
    $schema=$d.actions.Resolve_evaluation.actions.Validate_match.inputs.schema
    Assert ($schema.minItems-eq 1-and$schema.maxItems-eq 1) 'Ambiguous evaluations could be selected.'
    Assert ($d.actions.Resolve_evaluation.actions.For_each_agent.actions.Filter_named_sets.inputs.where.Contains("'Active'")) 'Inactive evaluations accepted.'
}
Check 'Bridge connector payloads have secure inputs and outputs' {
    $start=$d.actions.Evaluate_and_wait.actions.Start_evaluation
    Assert (($start.runtimeConfiguration.secureData.properties-join',')-eq'inputs,outputs') 'Connector payload history is unprotected.'
}
Check 'Configuration validation runs before environment validation' {
    Assert ($d.actions.Validate_environment.runAfter.Validate_configuration[0]-ceq'Succeeded') 'Configuration guard can be bypassed.'
    Assert ($d.actions.Validate_configuration.inputs.schema.properties.ready.enum[0]-eq$true) 'Configuration guard must require true.'
}
Check 'Source environment parameter is portable and its guard schema is static' {
    $source=$d.parameters['Bridge Source Environment ID (aeg_SourceEnvironmentId)']
    Assert ($source.defaultValue-ceq'00000000-0000-0000-0000-000000000000'-and$source.metadata.schemaName-ceq'aeg_SourceEnvironmentId') 'Source environment default is not portable.'
    Assert ($d.actions.Validate_environment.inputs.schema.properties.matches.enum[0]-eq$true) 'Environment guard must require true.'
    foreach($name in @('Validate_configuration','Validate_environment')){
        $schemaText=$d.actions[$name].inputs.schema|ConvertTo-Json -Depth 15
        Assert ($schemaText-notmatch'@|"pattern"|"patternProperties"') 'Guard schema contains unsupported expressions or patterns.'
    }
}
Check 'Solution definition contains no connection instance or nonzero GUID literal' {
    Assert ($flow.properties.connectionReferences.shared_microsoftcopilotstudio.connection.Keys.Count-eq 1) 'Unexpected connection instance binding.'
    foreach($id in [regex]::Matches($json,'(?i)[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')){
        Assert ($id.Value-ceq'00000000-0000-0000-0000-000000000000') 'Instance GUID in flow definition.'
    }
}
Check 'New commit template has no requester identity or broad forced staging' {
    $text=Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'Templates\commit-solution-template.yml') -Raw
    Assert ($text-notmatch'Build.RequestedFor|git add --all|--force') 'Unsafe commit behavior in new template.'
    Assert ($text-notmatch'clientSecret.+arguments:') 'Secret interpolated into arguments.'
}
Write-Host "$script:count publication regression checks passed."
