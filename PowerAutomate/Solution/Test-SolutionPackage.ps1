[CmdletBinding()]
param(
    [string]$PackagePath = (Join-Path $PSScriptRoot 'AgentEvaluationGateBridge_1_0_0_0_unmanaged.zip')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath).Path)
function Read-Entry([string]$Name) {
    $entry=$zip.GetEntry($Name)
    if($null-eq$entry){throw "Missing required package entry: $Name"}
    $reader=[IO.StreamReader]::new($entry.Open(),[Text.UTF8Encoding]::new($false,$true))
    try{$reader.ReadToEnd()}finally{$reader.Dispose()}
}
function Assert([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
try {
    Assert ($zip.Entries.Count-eq 7) 'Unexpected package content; review every additional entry.'
    [xml]$solution=Read-Entry 'solution.xml'
    $manifest=$solution.ImportExportXml.SolutionManifest
    Assert ([string]$manifest.UniqueName-ceq'AgentEvaluationGateBridge') 'Wrong solution unique name.'
    Assert ([string]$manifest.Managed-ceq'0') 'Expected an unmanaged solution.'
    Assert ([string]$manifest.Version-ceq'1.0.0.0') 'Unexpected release version.'
    $roots=@($manifest.RootComponents.RootComponent)
    Assert ($roots.Count-eq 1-and[string]$roots[0].type-ceq'29') 'Expected exactly one workflow root.'
    $flowId=([guid]$roots[0].id.Trim('{}')).ToString()
    $workflows=@($zip.Entries|Where-Object FullName -Match '^Workflows/[^/]+\.json$')
    Assert ($workflows.Count-eq 1) 'Expected exactly one flow definition.'
    $flow=Read-Entry $workflows[0].FullName|ConvertFrom-Json -AsHashtable
    $refs=$flow.properties.connectionReferences
    Assert ($refs.Count-eq 1) 'Expected one connection reference.'
    $ref=$refs.shared_microsoftcopilotstudio
    Assert ($ref.connection.Keys.Count-eq 1-and$ref.connection.connectionReferenceLogicalName-ceq'aeg_CopilotStudio') 'Connection reference contains an instance binding.'
    Assert ($ref.api.name-ceq'shared_microsoftcopilotstudio'-and$ref.runtimeSource-ceq'embedded') 'Unexpected connector configuration.'
    $d=$flow.properties.definition
    Assert ($d.triggers.manual.inputs.triggerAuthenticationType-ceq'User') 'HTTP trigger must use restricted authentication.'
    Assert ($d.triggers.manual.inputs.triggerAllowedUsers-ceq"@parameters('Bridge Allowed Caller Object ID (aeg_AllowedCallerObjectId)')") 'Caller allowlist is not environment-variable-backed.'
    $variables=@{
        aeg_AllowedCallerObjectId='00000000-0000-0000-0000-000000000000'
        aeg_SourceEnvironmentId='00000000-0000-0000-0000-000000000000'
        aeg_EvaluationConnectionName='CONFIGURE_CONNECTION_NAME'
    }
    foreach($name in $variables.Keys){
        [xml]$definition=Read-Entry "environmentvariabledefinitions/$name/environmentvariabledefinition.xml"
        Assert ([string]$definition.environmentvariabledefinition.defaultvalue-ceq$variables[$name]) 'Package contains an unsafe variable default.'
        Assert ([string]$definition.environmentvariabledefinition.isrequired-ceq'1') 'Environment variable should be required.'
        $parameters=@($d.parameters.Values|Where-Object { $_.Contains('metadata') -and $_.metadata.schemaName-ceq$name })
        Assert ($parameters.Count-eq 1-and$parameters[0].defaultValue-ceq$variables[$name]) 'Flow parameter/default is not portable.'
    }
    $guard=$d.actions.Validate_configuration
    Assert ($guard.inputs.schema.properties.ready.enum[0]-eq$true) 'Missing configuration guard.'
    Assert ($d.actions.Validate_environment.runAfter.Validate_configuration[0]-ceq'Succeeded') 'Configuration guard can be bypassed.'
    Assert ($d.actions.Validate_environment.inputs.schema.properties.matches.enum[0]-eq$true) 'Missing source-environment guard.'
    Assert ($d.actions.Evaluation_response.inputs.body.schemaVersion-eq 2) 'Response contract version changed.'
    Assert ($d.actions.Evaluation_response.operationOptions-ceq'Asynchronous'-and$d.actions.Error_response.operationOptions-ceq'Asynchronous') 'Response paths must be asynchronous.'
    [xml]$customizations=Read-Entry 'customizations.xml'
    $workflow=@($customizations.ImportExportXml.Workflows.Workflow)
    Assert ($workflow.Count-eq 1-and[string]$workflow[0].StateCode-ceq'0') 'Exported flow must be off.'
    Assert (([guid]$workflow[0].WorkflowId.Trim('{}')).ToString()-eq$flowId) 'Workflow identities differ.'
    $connections=@($customizations.ImportExportXml.connectionreferences.connectionreference)
    Assert ($connections.Count-eq 1-and[string]$connections[0].connectionreferencelogicalname-ceq'aeg_CopilotStudio') 'Expected the portable Copilot Studio reference.'
    $connectionInstance=$connections[0].SelectSingleNode('connectionid')
    Assert ($null-eq$connectionInstance-or[string]::IsNullOrWhiteSpace($connectionInstance.InnerText)) 'Connection reference contains an instance ID.'
    foreach($entry in $zip.Entries){
        Assert ($entry.FullName-notmatch'\.\.|^[\\/]|:') 'Unsafe ZIP entry path.'
        $text=Read-Entry $entry.FullName
        Assert ($text-notmatch'(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|[?&]sig=|shared-microsoftcopi-[a-f0-9]{8}-|github_pat_|ghp_[a-z0-9]{25,}|[a-z]:\\Users\\|\.crm(?:[0-9]+)?\.dynamics\.com|\.onmicrosoft\.com') 'Potential personal data, environment binding or secret in package.'
        foreach($m in [regex]::Matches($text,'(?i)\b[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\b')){
            Assert ($m.Value-ieq$flowId-or$m.Value-eq'00000000-0000-0000-0000-000000000000') 'Unexpected instance GUID in package.'
        }
    }
    foreach($field in @('EMailAddress','SupportingWebsiteUrl')){
        Assert ([string]::IsNullOrWhiteSpace($manifest.Publisher.SelectSingleNode($field).InnerText)) 'Publisher contact information is present.'
    }
    foreach($address in $manifest.Publisher.Addresses.Address){
        foreach($field in @('Name','PrimaryContactName','Line1','Line2','Line3','City','Country','PostalCode','Telephone1','Telephone2','Telephone3','Fax')){
            Assert ([string]::IsNullOrWhiteSpace($address.SelectSingleNode($field).InnerText)) 'Publisher address/contact information is present.'
        }
    }
    Write-Host 'Unmanaged package verified: one off flow, one unbound reference, three safe variable definitions, no unexpected identifiers or contact data.'
    [pscustomobject]@{solution='AgentEvaluationGateBridge';version='1.0.0.0';managed=$false;sha256=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash}
}
finally{$zip.Dispose()}
