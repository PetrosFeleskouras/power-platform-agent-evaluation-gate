Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GateConfig {
    $map = @{
        sourceUrl='SOURCE_ENVIRONMENT_URL'; sourceEnvironmentId='SOURCE_ENVIRONMENT_ID'
        sourceTenantId='SOURCE_TENANT_ID'; targetUrl='TARGET_ENVIRONMENT_URL'
        targetEnvironmentId='TARGET_ENVIRONMENT_ID'; targetTenantId='TARGET_TENANT_ID'
        bridgeUrl='EVALUATION_BRIDGE_URL'; bridgeWorkflowId='EVALUATION_BRIDGE_WORKFLOW_ID'
    }
    $config = @{}
    foreach ($key in $map.Keys) {
        $value = [Environment]::GetEnvironmentVariable($map[$key])
        if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains('$(')) { throw "Configure pipeline variable $($map[$key])." }
        $config[$key] = $value.Trim()
    }
    foreach ($key in 'sourceEnvironmentId','targetEnvironmentId','sourceTenantId','targetTenantId') {
        $id = [guid]::Empty
        if (-not [guid]::TryParse($config[$key], [ref]$id) -or $id -eq [guid]::Empty) { throw "Invalid configured GUID: $key" }
        $config[$key] = $id.ToString()
    }
    foreach ($key in 'sourceUrl','targetUrl') {
        $uri = [uri]$config[$key]
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or -not $uri.IsDefaultPort -or
            $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') { throw "Invalid environment root URL: $key" }
        $config[$key] = $uri.GetLeftPart([UriPartial]::Authority).TrimEnd('/')
    }
    if ($config.sourceUrl -eq $config.targetUrl -or $config.sourceEnvironmentId -eq $config.targetEnvironmentId) {
        throw 'Source and target must be different environments.'
    }
    if ($config.bridgeWorkflowId -notmatch '^[A-Fa-f0-9]{32}$') { throw 'Invalid bridge workflow ID.' }
    Assert-PollUri ([uri]$config.bridgeUrl) $config
    $config
}

function Assert-SolutionName {
    param([string]$Name)
    if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Provide a valid solution unique name (letters, digits and underscores).' }
}

function Get-TextHash {
    param([string]$Text)
    $normalized = $Text.Replace("`r`n", "`n").TrimEnd()
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($normalized)))
}

function Get-PayloadKind {
    param([string]$Data)
    $match = [regex]::Match($Data, '(?m)^kind:\s*([^\r\n]+)\s*$')
    if (-not $match.Success) { return $null }
    $match.Groups[1].Value.Trim()
}

function Get-ServiceToken {
    param([string]$Resource)
    $config = Get-GateConfig
    foreach ($key in 'GATE_CLIENT_ID', 'GATE_CLIENT_SECRET', 'GATE_TENANT_ID') {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key))) {
            throw "Missing credential environment variable: $key"
        }
    }
    $tenant = if ($Resource -ceq $config.targetUrl) { $config.targetTenantId } else { $config.sourceTenantId }
    if ($Resource -cnotin @($config.sourceUrl,$config.targetUrl,'https://service.flow.microsoft.com/')) { throw 'Unapproved token resource.' }
    if ($env:GATE_TENANT_ID -ne $tenant) { throw 'Service connection tenant does not match the configured environment.' }
    try {
        $token = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token" `
            -Body @{client_id=$env:GATE_CLIENT_ID; client_secret=$env:GATE_CLIENT_SECRET; grant_type='client_credentials'; scope="$Resource/.default"} `
            -TimeoutSec 60 -MaximumRedirection 0
    }
    catch { throw 'Service-principal token acquisition failed. Check the service connection and API audience; credentials were not logged.' }
    if (-not $token.access_token) { throw 'Token response contained no access token.' }
    $token.access_token
}

function Invoke-DataverseRead {
    param([string]$BaseUrl, [string]$RelativePath)
    $token = Get-ServiceToken $BaseUrl
    try {
        Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/data/v9.2/$RelativePath" `
            -Headers @{Authorization="Bearer $token"; Accept='application/json'; 'OData-Version'='4.0'} `
            -TimeoutSec 90 -MaximumRedirection 0
    }
    catch { throw "Dataverse read failed for $($RelativePath.Split('?')[0]). Verify permissions and environment; response details were not logged." }
}

function Get-DataverseRows {
    param([string]$BaseUrl, [string]$RelativePath)
    $result = Invoke-DataverseRead $BaseUrl $RelativePath
    if ($result.PSObject.Properties.Name -notcontains 'value') { throw 'Dataverse response has no collection.' }
    if ($result.PSObject.Properties.Name -contains '@odata.nextLink') {
        throw 'Snapshot query exceeded a page. Refusing an incomplete source fingerprint.'
    }
    @($result.value)
}

function Get-SourceStamp {
    param([hashtable]$Config, [string]$SolutionName)
    Assert-SolutionName $SolutionName
    $solutions = @(Get-DataverseRows $Config.sourceUrl "solutions?`$select=solutionid,uniquename,version&`$filter=uniquename eq '$SolutionName'")
    if ($solutions.Count -ne 1) { throw 'Expected exactly one source solution.' }
    if ($solutions[0].uniquename -cne $SolutionName) { throw "Use the exact solution unique name: $($solutions[0].uniquename)" }
    $solutionId = ([guid]$solutions[0].solutionid).ToString()
    $members = @(Get-DataverseRows $Config.sourceUrl "solutioncomponents?`$select=objectid,componenttype&`$filter=_solutionid_value eq $solutionId")
    $memberIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $members) { $null = $memberIds.Add([string]$member.objectid) }
    $fetch = "<fetch><entity name='bot'><attribute name='botid'/><attribute name='schemaname'/><link-entity name='solutioncomponent' from='objectid' to='botid'><filter><condition attribute='solutionid' operator='eq' value='$solutionId'/></filter></link-entity></entity></fetch>"
    $bots = @(Get-DataverseRows $Config.sourceUrl ('bots?fetchXml=' + [uri]::EscapeDataString($fetch)) | Sort-Object botid -Unique)
    if ($bots.Count -ne 1) { throw 'The solution must contain exactly one agent to evaluate.' }
    $agents = @()
    $snapshots = @()
    foreach ($bot in $bots) {
        $id = ([guid]$bot.botid).ToString()
        $record = Invoke-DataverseRead $Config.sourceUrl "bots($id)?`$select=botid,schemaname,configuration"
        $components = @(Get-DataverseRows $Config.sourceUrl "botcomponents?`$select=botcomponentid,name,schemaname,componenttype,data,modifiedon,versionnumber,_parentbotcomponentid_value&`$filter=_parentbotid_value eq $id")
        $skills = @($components | Where-Object componenttype -eq 9 | Sort-Object schemaname)
        foreach ($skill in $skills) {
            if (@($members | Where-Object { $_.objectid -eq $skill.botcomponentid }).Count -ne 1) {
                throw "Skill is not explicitly included in the source solution: $($skill.schemaname)"
            }
        }
        $testComponents = @($components | Where-Object {
            $_.componenttype -eq 19 -and $memberIds.Contains([string]$_.botcomponentid)
        })
        $evaluationSets = @($testComponents | Where-Object { (Get-PayloadKind $_.data) -eq 'EvaluationSet' })
        if ($evaluationSets.Count -ne 1) {
            throw "The solution must contain exactly one Test case evaluation set; found $($evaluationSets.Count)."
        }
        $evaluationSet = $evaluationSets[0]
        $testCases = @($testComponents | Where-Object {
            (Get-PayloadKind $_.data) -eq 'MultiTurnEvaluationCase' -and
            $_._parentbotcomponentid_value -eq $evaluationSet.botcomponentid
        } | Sort-Object schemaname)
        if ($testCases.Count -eq 0) { throw 'The packaged evaluation set contains no test cases.' }
        $unrelatedCases = @($testComponents | Where-Object {
            (Get-PayloadKind $_.data) -eq 'MultiTurnEvaluationCase' -and
            $_._parentbotcomponentid_value -ne $evaluationSet.botcomponentid
        })
        if ($unrelatedCases.Count -gt 0) {
            throw 'The solution contains Test case components that do not belong to its sole evaluation set.'
        }
        $agents += @{
            agentId=$id; schemaName=$record.schemaname
            configurationHash=Get-TextHash $record.configuration
            skills=@($skills | ForEach-Object {
                @{schemaName=$_.schemaname; name=$_.name; dataHash=Get-TextHash $_.data}
            })
            evaluation=@{
                testSetId=([guid]$evaluationSet.botcomponentid).ToString()
                name=$evaluationSet.name
                schemaName=$evaluationSet.schemaname
                dataHash=Get-TextHash $evaluationSet.data
                cases=@($testCases | ForEach-Object {
                    @{
                        testCaseId=([guid]$_.botcomponentid).ToString()
                        name=$_.name
                        schemaName=$_.schemaname
                        dataHash=Get-TextHash $_.data
                    }
                })
            }
        }
        $snapshots += [ordered]@{
            agentId=$id
            configurationHash=Get-TextHash $record.configuration
            components=@($components | Where-Object { $memberIds.Contains([string]$_.botcomponentid) } |
                Sort-Object botcomponentid | ForEach-Object {
                [ordered]@{
                    botcomponentid=$_.botcomponentid
                    schemaname=$_.schemaname
                    componenttype=$_.componenttype
                    dataHash=Get-TextHash ([string]$_.data)
                    modifiedon=$_.modifiedon
                    versionnumber=$_.versionnumber
                }
            })
        }
    }
    $stamp = [ordered]@{
        agents = $snapshots
        solutionId = $solutionId
        solutionVersion = $solutions[0].version
        membership = @($members | Sort-Object componenttype,objectid | Select-Object objectid,componenttype)
    }
    @{
        fingerprint = Get-TextHash ($stamp | ConvertTo-Json -Depth 15 -Compress)
        solutionVersion = $solutions[0].version
        agents = $agents
        solutionName = $SolutionName
    }
}

function Read-SolutionPackage {
    param([string]$Path, [hashtable]$Selected)
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        $entry = $zip.GetEntry('solution.xml')
        if ($null -eq $entry) { throw 'Package has no solution.xml.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $manifest = $xml.ImportExportXml.SolutionManifest
        if ([string]$manifest.UniqueName -cne $Selected.solutionName -or [string]$manifest.Managed -ne '1') {
            throw 'Expected the approved managed solution package.'
        }
        $expectedTestSchemas = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($agent in $Selected.agents) {
          if ($null -eq $zip.GetEntry("bots/$($agent.schemaName)/bot.xml")) { throw "Exported agent missing: $($agent.schemaName)" }
          $configurationEntry = $zip.GetEntry("bots/$($agent.schemaName)/configuration.json")
          if ($null -eq $configurationEntry) { throw "Exported agent configuration missing: $($agent.schemaName)" }
          $configurationReader = [IO.StreamReader]::new($configurationEntry.Open())
          try { $configuration = $configurationReader.ReadToEnd() } finally { $configurationReader.Dispose() }
          if ((Get-TextHash $configuration) -cne $agent.configurationHash) {
              throw "Packaged agent configuration differs from the evaluated source: $($agent.schemaName)"
          }
          foreach ($skill in $agent.skills) {
            $metadataEntries = @($zip.Entries | Where-Object { $_.FullName -ceq "botcomponents/$($skill.schemaName)/botcomponent.xml" })
            if ($metadataEntries.Count -ne 1) { throw "Export must contain exactly one skill component: $skill" }
            $r = [IO.StreamReader]::new($metadataEntries[0].Open())
            try { [xml]$metadata = $r.ReadToEnd() } finally { $r.Dispose() }
            $component = $metadata.botcomponent
            $schema = [string]$component.schemaname
            if ([string]$component.componenttype -cne '9' -or
                [string]$component.name -cne $skill.name -or
                [string]$component.parentbotid.schemaname -cne $agent.schemaName -or
                $metadataEntries[0].FullName -cne "botcomponents/$schema/botcomponent.xml") {
                throw "Exported skill identity/type/parent does not match: $skill"
            }
            $payloadEntry = $zip.GetEntry("botcomponents/$schema/data")
            if ($null -eq $payloadEntry -or $payloadEntry.Length -eq 0) { throw "Exported skill has no payload: $skill" }
            $payloadReader = [IO.StreamReader]::new($payloadEntry.Open())
            try { $payload = $payloadReader.ReadToEnd() } finally { $payloadReader.Dispose() }
            if ((Get-TextHash $payload) -cne $skill.dataHash) {
                throw "Packaged skill differs from the evaluated source: $($skill.schemaName)"
            }
          }
          $evaluationComponents = @($agent.evaluation) + @($agent.evaluation.cases)
          foreach ($evaluationComponent in $evaluationComponents) {
            $null = $expectedTestSchemas.Add([string]$evaluationComponent.schemaName)
            $metadataPath = "botcomponents/$($evaluationComponent.schemaName)/botcomponent.xml"
            $payloadPath = "botcomponents/$($evaluationComponent.schemaName)/data"
            $metadataEntry = $zip.GetEntry($metadataPath)
            $payloadEntry = $zip.GetEntry($payloadPath)
            if ($null -eq $metadataEntry -or $null -eq $payloadEntry -or $payloadEntry.Length -eq 0) {
                throw "Packaged Test case component is missing metadata or data: $($evaluationComponent.schemaName)"
            }
            $metadataReader = [IO.StreamReader]::new($metadataEntry.Open())
            try { [xml]$metadata = $metadataReader.ReadToEnd() } finally { $metadataReader.Dispose() }
            if ([string]$metadata.botcomponent.componenttype -cne '19' -or
                [string]$metadata.botcomponent.name -cne $evaluationComponent.name) {
                throw "Packaged Test case component identity differs from the source: $($evaluationComponent.schemaName)"
            }
            $payloadReader = [IO.StreamReader]::new($payloadEntry.Open())
            try { $payload = $payloadReader.ReadToEnd() } finally { $payloadReader.Dispose() }
            if ((Get-TextHash $payload) -cne $evaluationComponent.dataHash) {
                throw "Packaged Test case component differs from the evaluated source: $($evaluationComponent.schemaName)"
            }
          }
        }
        $packagedTestSchemas = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($metadataEntry in @($zip.Entries | Where-Object { $_.FullName -like 'botcomponents/*/botcomponent.xml' })) {
            $metadataReader = [IO.StreamReader]::new($metadataEntry.Open())
            try { [xml]$metadata = $metadataReader.ReadToEnd() } finally { $metadataReader.Dispose() }
            if ([string]$metadata.botcomponent.componenttype -cne '19') { continue }
            $schema = [string]$metadata.botcomponent.schemaname
            $payloadEntry = $zip.GetEntry("botcomponents/$schema/data")
            if ($null -eq $payloadEntry) { throw "Packaged Test case component has no data: $schema" }
            $payloadReader = [IO.StreamReader]::new($payloadEntry.Open())
            try { $kind = Get-PayloadKind $payloadReader.ReadToEnd() } finally { $payloadReader.Dispose() }
            if ($kind -in @('EvaluationSet','MultiTurnEvaluationCase')) { $null = $packagedTestSchemas.Add($schema) }
        }
        if ($packagedTestSchemas.Count -ne $expectedTestSchemas.Count -or
            @($packagedTestSchemas | Where-Object { -not $expectedTestSchemas.Contains($_) }).Count -gt 0) {
            throw 'The package contains missing or unrelated evaluation Test case components.'
        }
        @{sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash; version=[string]$manifest.Version}
    }
    finally { $zip.Dispose() }
}

function Assert-GateResponse {
    param([hashtable]$Result, [hashtable]$Expected, [hashtable]$Config)
    foreach ($field in 'schemaVersion','solutionUniqueName','evaluationName','correlationId','artifactSha256','sourceFingerprint','flowRunId','evaluationRunId','environmentId','agentId','testSetId','state','expectedTests','totalTests','passedTests','passed','testCasesResults') {
        if (-not $Result.ContainsKey($field)) { throw "Evaluation response is missing $field." }
    }
    foreach ($field in 'solutionUniqueName','evaluationName','correlationId','artifactSha256','sourceFingerprint') {
        if ($Result[$field] -isnot [string] -or $Result[$field] -cne $Expected[$field]) { throw "Evaluation response mismatch: $field" }
    }
    if ($Result.agentId -notin $Expected.agentIds) { throw 'Evaluated agent does not belong to the selected solution.' }
    if ($Result.environmentId -cne $Config.sourceEnvironmentId -or $Result.state -cne 'Completed') { throw 'Evaluation did not complete in the configured source environment.' }
    foreach ($field in 'schemaVersion','expectedTests','totalTests','passedTests') {
        if ($Result[$field] -isnot [int] -and $Result[$field] -isnot [long]) { throw "Expected an integer: $field" }
    }
    if ($Result.schemaVersion -ne 2 -or $Result.expectedTests -lt 1 -or $Result.totalTests -ne $Result.expectedTests -or $Result.passedTests -lt 0 -or $Result.passedTests -gt $Result.totalTests) { throw 'Unexpected evaluation counts or schema version.' }
    if ($Result.passed -isnot [bool]) { throw 'passed must be a JSON boolean, not a string.' }
    foreach ($field in 'evaluationRunId','agentId','testSetId') {
        $id=[guid]::Empty
        if ($Result[$field] -isnot [string] -or -not [guid]::TryParse($Result[$field],[ref]$id) -or $id -eq [guid]::Empty) { throw "Invalid identity: $field" }
    }
    if ([string]::IsNullOrWhiteSpace($Result.flowRunId)) { throw 'Missing flow run identity.' }
    if ($Result.testCasesResults -isnot [array] -or $Result.testCasesResults.Count -ne $Result.expectedTests) { throw 'Incomplete individual results.' }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $passed = 0
    foreach ($case in $Result.testCasesResults) {
        if ($case -isnot [hashtable] -or -not $case.ContainsKey('testCaseId') -or -not $ids.Add([string]$case.testCaseId) -or [string]::IsNullOrWhiteSpace($case.testCaseId)) { throw 'Invalid or duplicate case ID.' }
        if ($case.state -cne 'Completed') { throw 'A test case did not complete.' }
        if ($case.metricsResults -isnot [array] -or $case.metricsResults.Count -eq 0) { throw 'Missing metric coverage.' }
        $casePassed = $true
        foreach ($metric in $case.metricsResults) {
            if ([string]::IsNullOrWhiteSpace($metric.type) -or $metric.result.status -cnotin @('Pass','Fail')) { throw 'Evaluation metric error or unsupported status.' }
            if ($metric.result.status -cne 'Pass') { $casePassed = $false }
        }
        if ($casePassed) { $passed++ }
    }
    if ($Result.passedTests -ne $passed -or $Result.passed -ne ($passed -eq $Result.expectedTests)) { throw 'Summary and individual case results disagree.' }
    if ($passed -ne $Result.expectedTests) { throw "Evaluation gate FAILED: $passed/$($Result.expectedTests) passed; target deployment is blocked." }
}

function Assert-PollUri {
    param([uri]$Uri, [hashtable]$Config)
    $origin = [uri]$Config.bridgeUrl
    if ($Uri.Scheme -ne 'https' -or -not $Uri.IsDefaultPort -or $Uri.UserInfo -or $Uri.Fragment -or
        $Uri.Host -cne $origin.Host -or -not $Uri.AbsolutePath.Contains("/workflows/$($Config.bridgeWorkflowId)/")) {
        throw 'Polling URL is outside the approved bridge. Refusing to send credentials.'
    }
}

function Invoke-EvaluationBridge {
    param([hashtable]$Config, [hashtable]$Request, [int]$TimeoutSeconds = 1500)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $uri = [uri]$Config.bridgeUrl
    $method = 'POST'
    $initialRunId = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        Assert-PollUri $uri $Config
        $remaining = [math]::Max(1, [math]::Min(90, [int]($deadline - [DateTime]::UtcNow).TotalSeconds))
        $arguments = @{
            Method=$method; Uri=$uri; MaximumRedirection=0; TimeoutSec=$remaining
            Headers=@{Authorization="Bearer $(Get-ServiceToken 'https://service.flow.microsoft.com/')"}
            SkipHttpErrorCheck=$true
        }
        if ($method -eq 'POST') {
            $arguments.ContentType = 'application/json'
            $arguments.Body = $Request | ConvertTo-Json -Compress
        }
        try { $response = Invoke-WebRequest @arguments }
        catch { throw 'Evaluation HTTP request failed or timed out. No start retry was attempted; inspect the bridge run before rerunning.' }
        if ($response.StatusCode -eq 202) {
            if ($response.Headers.ContainsKey('Location')) {
                $uri = [uri]::new($uri, [string]$response.Headers.Location[0])
                Assert-PollUri $uri $Config
                if ($uri.AbsolutePath -match '/runs/([^/]+)') {
                    if ($initialRunId -and $initialRunId -cne $Matches[1]) { throw 'Polling changed flow run identity.' }
                    $initialRunId = $Matches[1]
                }
            }
            elseif ($method -eq 'POST') { throw 'Accepted evaluation has no polling Location.' }
            $method = 'GET'
            Start-Sleep -Seconds ([math]::Min(15, [math]::Max(1,[int]($deadline - [DateTime]::UtcNow).TotalSeconds)))
            continue
        }
        if ($method -eq 'GET' -and $response.StatusCode -in @(429,502,503,504)) {
            Start-Sleep -Seconds 15
            continue
        }
        if ($response.StatusCode -ne 200) {
            $errorCode = 'Unspecified'
            try {
                $errorBody = $response.Content | ConvertFrom-Json -AsHashtable
                if ($errorBody.ContainsKey('error') -and $errorBody.error.code -match '^[A-Za-z0-9_.-]+$') {
                    $errorCode = $errorBody.error.code
                }
            }
            catch { Write-Warning 'Bridge returned a non-JSON error response; raw content withheld to protect signed URLs.' }
            throw "Evaluation bridge returned HTTP $($response.StatusCode) ($errorCode); deployment blocked."
        }
        try { $result = $response.Content | ConvertFrom-Json -AsHashtable }
        catch { throw 'Evaluation bridge returned invalid JSON.' }
        if ($initialRunId -and $result.flowRunId -cne $initialRunId) { throw 'Final response belongs to a different flow run.' }
        return $result
    }
    throw 'Evaluation deadline exceeded; target deployment is blocked. The remote flow may still be running.'
}

Export-ModuleMember -Function Get-GateConfig,Assert-SolutionName,Get-TextHash,Get-PayloadKind,Get-ServiceToken,Invoke-DataverseRead,Get-DataverseRows,Get-SourceStamp,Read-SolutionPackage,Assert-GateResponse,Assert-PollUri,Invoke-EvaluationBridge
