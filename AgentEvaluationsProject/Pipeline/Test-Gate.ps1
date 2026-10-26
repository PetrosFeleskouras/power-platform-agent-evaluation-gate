$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Gate.psm1') -Force
$config = @{
    sourceEnvironmentId='22222222-2222-2222-2222-222222222222'
    bridgeUrl='https://example.invalid/workflows/33333333333333333333333333333333/triggers/manual'
    bridgeWorkflowId='33333333333333333333333333333333'
}
$agentId='44444444-4444-4444-4444-444444444444'
$testSetId='55555555-5555-5555-5555-555555555555'
$expected = @{
    solutionUniqueName='ExampleSolution'; evaluationName='Example evaluation'; correlationId='test-build-1'; artifactSha256=('A' * 64)
    sourceFingerprint=('B' * 64); agentIds=@($agentId)
}
$valid = $expected.Clone()
$valid.schemaVersion = 2
$valid.agentId=$agentId
$valid.testSetId=$testSetId
$valid.flowRunId = 'test-flow-run'
$valid.evaluationRunId = '11111111-1111-1111-1111-111111111111'
$valid.environmentId = $config.sourceEnvironmentId
$valid.state = 'Completed'
$valid.expectedTests = 10
$valid.totalTests = 10
$valid.passedTests = 10
$valid.passed = $true
$valid.testCasesResults = @(1..10 | ForEach-Object {
    @{testCaseId="case-$_"; state='Completed'; metricsResults=@(@{type='GeneralQuality'; result=@{status='Pass'}})}
})
$expected.testSetId = $testSetId
$expected.testCaseIds = @($valid.testCasesResults.testCaseId)
$script:count = 0
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    & $Body
    $script:count++
    Write-Host "PASS: $Name"
}
function Expect-Rejection {
    param([scriptblock]$Body)
    $rejected = $false
    try { & $Body } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid evidence was accepted.' }
}
function Copy-Result {
    $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
}
Test-Case 'Exact ten-of-ten result is accepted' { Assert-GateResponse (Copy-Result) $expected $config }
Test-Case 'Eight-of-ten is rejected, not a success-shaped fallback' {
    $r=Copy-Result; $r.testCasesResults[4].metricsResults[0].result.status='Fail'
    $r.testCasesResults[7].metricsResults[0].result.status='Fail'; $r.passedTests=8; $r.passed=$false
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'Nine-of-ten is rejected at the exact threshold' {
    $r=Copy-Result; $r.testCasesResults[0].metricsResults[0].result.status='Fail'; $r.passedTests=9; $r.passed=$false
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
foreach ($field in 'solutionUniqueName','evaluationName','correlationId','artifactSha256','sourceFingerprint','agentId','testSetId','environmentId') {
    Test-Case "Mismatched $field is rejected" {
        $r=Copy-Result; $r[$field]='wrong'
        Expect-Rejection { Assert-GateResponse $r $expected $config }
    }
}
Test-Case 'String true is rejected' { $r=Copy-Result; $r.passed='true'; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Missing passed is rejected' { $r=Copy-Result; $r.Remove('passed'); Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'String count is rejected' { $r=Copy-Result; $r.passedTests='10'; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Summary cannot hide a failed case' {
    $r=Copy-Result; $r.testCasesResults[0].metricsResults[0].result.status='Fail'
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'Missing case is rejected' { $r=Copy-Result; $r.testCasesResults=$r.testCasesResults[0..8]; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Duplicate case is rejected' { $r=Copy-Result; $r.testCasesResults[9].testCaseId='case-1'; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Empty metric is rejected' { $r=Copy-Result; $r.testCasesResults[0].metricsResults=@(); Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Metric error is rejected' { $r=Copy-Result; $r.testCasesResults[0].metricsResults[0].result.status='Error'; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Incomplete case is rejected' { $r=Copy-Result; $r.testCasesResults[0].state='Running'; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Incomplete run is rejected' { $r=Copy-Result; $r.state='InProgress'; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Zero cases cannot pass' { $r=Copy-Result; $r.testCasesResults=@(); $r.totalTests=0; Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Allowlisted bridge URL is accepted' { Assert-PollUri ([uri]$config.bridgeUrl) $config }
Test-Case 'Untrusted Location host is rejected' { Expect-Rejection { Assert-PollUri ([uri]'https://example.com/workflows/33333333333333333333333333333333/runs/123') $config } }
Test-Case 'Different workflow URL is rejected' {
    Expect-Rejection { Assert-PollUri ([uri]$config.bridgeUrl.Replace($config.bridgeWorkflowId,'unrelated')) $config }
}
Test-Case 'HTTP Location is rejected' { Expect-Rejection { Assert-PollUri ([uri]$config.bridgeUrl.Replace('https:','http:')) $config } }
Test-Case 'Invalid solution name is rejected before querying or exporting' { Expect-Rejection { Assert-SolutionName "demo'; drop" } }
Test-Case 'Arbitrary case count is supported, not fixed at ten' {
    $r=Copy-Result; $r.testCasesResults=$r.testCasesResults[0..2]
    $r.expectedTests=3; $r.totalTests=3; $r.passedTests=3
    $threeCaseExpectation=$expected.Clone()
    $threeCaseExpectation.testCaseIds=@($r.testCasesResults.testCaseId)
    Assert-GateResponse $r $threeCaseExpectation $config
}
Test-Case 'Non-GeneralQuality metric and multiple metrics can pass' {
    $r=Copy-Result; $r.testCasesResults[0].metricsResults=@(
        @{type='ExactMatch';result=@{status='Pass'}},
        @{type='CompareMeaning';result=@{status='Pass'}}
    )
    Assert-GateResponse $r $expected $config
}
Test-Case 'Every metric must pass' {
    $r=Copy-Result; $r.testCasesResults[0].metricsResults+=@{type='ExactMatch';result=@{status='Fail'}}
    $r.passedTests=9; $r.passed=$false
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'Missing expected count is rejected' { $r=Copy-Result; $r.Remove('expectedTests'); Expect-Rejection { Assert-GateResponse $r $expected $config } }
Test-Case 'Different well-formed test set cannot authorize the package' {
    $r=Copy-Result; $r.testSetId='66666666-6666-6666-6666-666666666666'
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'An unrelated case cannot replace a packaged case' {
    $r=Copy-Result; $r.testCasesResults[0].testCaseId='unrelated-case'
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'A self-consistent smaller evaluation cannot authorize a larger packaged set' {
    $r=Copy-Result; $r.testCasesResults=@($r.testCasesResults[0..2])
    $r.expectedTests=3; $r.totalTests=3; $r.passedTests=3
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'A self-consistent larger evaluation cannot add a case to the package' {
    $r=Copy-Result
    $r.testCasesResults+=@{testCaseId='additional-case';state='Completed';metricsResults=@(@{type='GeneralQuality';result=@{status='Pass'}})}
    $r.expectedTests=11; $r.totalTests=11; $r.passedTests=11
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
Test-Case 'Case order does not affect exact inventory matching' {
    $r=Copy-Result; [array]::Reverse($r.testCasesResults)
    Assert-GateResponse $r $expected $config
}
Test-Case 'Case ID casing is normalized for inventory matching' {
    $r=Copy-Result; $r.testCasesResults[0].testCaseId='CASE-1'
    Assert-GateResponse $r $expected $config
}
Test-Case 'Non-string result case ID is rejected' {
    $r=Copy-Result; $r.testCasesResults[0].testCaseId=1
    Expect-Rejection { Assert-GateResponse $r $expected $config }
}
foreach($scenario in 'MissingSet','InvalidSet','MissingCases','EmptyCases','DuplicateCases','InvalidCaseType') {
    Test-Case "Invalid packaged expectations: $scenario" {
        $e=$expected | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        switch($scenario) {
            'MissingSet' {$null=$e.Remove('testSetId')}
            'InvalidSet' {$e.testSetId='not-a-guid'}
            'MissingCases' {$null=$e.Remove('testCaseIds')}
            'EmptyCases' {$e.testCaseIds=@()}
            'DuplicateCases' {$e.testCaseIds[1]=$e.testCaseIds[0]}
            'InvalidCaseType' {$e.testCaseIds[0]=1}
        }
        Expect-Rejection { Assert-GateResponse (Copy-Result) $e $config }
    }
}
$wireRequest=$expected.Clone()
$null=$wireRequest.Remove('testSetId')
$null=$wireRequest.Remove('testCaseIds')
$expectationSource=@{
    solutionName=$expected.solutionUniqueName
    agents=@(@{
        agentId=$agentId
        evaluation=@{name=$expected.evaluationName;testSetId=$testSetId;cases=@($expected.testCaseIds | ForEach-Object { @{testCaseId=$_} })}
    })
}
Test-Case 'Snapshot expectations do not change the bridge request contract' {
    $jsonBefore=$wireRequest|ConvertTo-Json -Depth 10 -Compress
    $bound=New-GateExpectation $wireRequest $expectationSource
    if (($wireRequest|ConvertTo-Json -Depth 10 -Compress) -cne $jsonBefore) { throw 'Request was mutated.' }
    if ($wireRequest.ContainsKey('testSetId') -or $wireRequest.ContainsKey('testCaseIds')) { throw 'Private expectations leaked into the wire request.' }
    Assert-GateResponse (Copy-Result) $bound $config
    $r=Copy-Result; $r.testSetId='66666666-6666-6666-6666-666666666666'
    Expect-Rejection { Assert-GateResponse $r $bound $config }
}
Test-Case 'Release expectations survive JSON serialization and reject unrelated cases' {
    $release=$expectationSource|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
    $bound=New-GateExpectation $wireRequest $release
    Assert-GateResponse (Copy-Result) $bound $config
    $r=Copy-Result; $r.testCasesResults[0].testCaseId='unrelated-case'
    Expect-Rejection { Assert-GateResponse $r $bound $config }
}
Test-Case 'Request cannot bind expectations from another solution or agent' {
    $request=$wireRequest.Clone();$request.solutionUniqueName='AnotherSolution'
    Expect-Rejection { New-GateExpectation $request $expectationSource }
    $request=$wireRequest.Clone();$request.agentIds=@('66666666-6666-6666-6666-666666666666')
    Expect-Rejection { New-GateExpectation $request $expectationSource }
}
function New-PackageFixture {
    param([string]$Path, [hashtable]$Entries)
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($name).Open())
            try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}
$agentConfiguration = '{"instructions":"Use onboarding-plan"}'
$payload = "kind: InlineAgentSkill`ncontent: |-`n  Follow the onboarding procedure."
$evaluationPayload = "kind: EvaluationSet`ngraders:`n  - kind: GeneralQualityGrader"
$casePayload = "kind: MultiTurnEvaluationCase`nsource: Imported`nactivities: []"
$fixtureCandidate = @{
    solutionName='demo'
    agents=@(@{
        agentId=$agentId
        schemaName='demo_agent'
        configurationHash=Get-TextHash $agentConfiguration
        skills=@(@{
            name='onboarding-plan'
            schemaName='demo_agent.skill.onboarding-plan_abc'
            dataHash=Get-TextHash $payload
        })
        evaluation=@{
            testSetId=$testSetId
            name='Demo evaluation'
            schemaName='demo_agent.evaluation'
            dataHash=Get-TextHash $evaluationPayload
            cases=@(@{
                testCaseId='99999999-9999-9999-9999-999999999999'
                name='Demo case'
                schemaName='demo_agent.evaluation.case'
                dataHash=Get-TextHash $casePayload
            })
        }
    })
}
$manifest = '<ImportExportXml><SolutionManifest><UniqueName>demo</UniqueName><Version>1.0.0.0</Version><Managed>1</Managed></SolutionManifest></ImportExportXml>'
$metadata = '<botcomponent schemaname="demo_agent.skill.onboarding-plan_abc"><componenttype>9</componenttype><name>onboarding-plan</name><parentbotid><schemaname>demo_agent</schemaname></parentbotid></botcomponent>'
$metadataPath = 'botcomponents/demo_agent.skill.onboarding-plan_abc/botcomponent.xml'
$payloadPath = 'botcomponents/demo_agent.skill.onboarding-plan_abc/data'
$evaluationMetadata = '<botcomponent schemaname="demo_agent.evaluation"><componenttype>19</componenttype><name>Demo evaluation</name><parentbotid><schemaname>demo_agent</schemaname></parentbotid></botcomponent>'
$caseMetadata = '<botcomponent schemaname="demo_agent.evaluation.case"><componenttype>19</componenttype><name>Demo case</name><parentbotcomponentid><schemaname>demo_agent.evaluation</schemaname></parentbotcomponentid><parentbotid><schemaname>demo_agent</schemaname></parentbotid></botcomponent>'
foreach ($scenario in 'MentionOnly','Complete','WrongParent','MissingPayload','WrongType',
    'ExtraAgent','ExtraAgentMetadataOnly','ExtraAgentConfigurationOnly','MissingAgentMetadata',
    'WrongAgentMetadata','DuplicateAgentMetadata','DuplicateCaseVariant','BackslashAgentPath',
    'WrongAgentDirectoryCase','EmptyAgentExpectation','MultipleAgentExpectations') {
    Test-Case "Package structure: $scenario" {
        $path = Join-Path ([IO.Path]::GetTempPath()) "hr-gate-test-$([guid]::NewGuid()).zip"
        try {
            $entries = @{
                'solution.xml'=$manifest
                'bots/demo_agent/bot.xml'='<bot schemaname="demo_agent"/>'
                'bots/demo_agent/configuration.json'=$agentConfiguration
                'botcomponents/demo_agent.evaluation/botcomponent.xml'=$evaluationMetadata
                'botcomponents/demo_agent.evaluation/data'=$evaluationPayload
                'botcomponents/demo_agent.evaluation.case/botcomponent.xml'=$caseMetadata
                'botcomponents/demo_agent.evaluation.case/data'=$casePayload
            }
            if ($scenario -ne 'MentionOnly') {
                $entries[$metadataPath] = $metadata
                if ($scenario -ne 'MissingPayload') { $entries[$payloadPath] = $payload }
            }
            if ($scenario -eq 'WrongParent') { $entries[$metadataPath] = $metadata.Replace('<schemaname>demo_agent</schemaname>','<schemaname>another_agent</schemaname>') }
            if ($scenario -eq 'WrongType') { $entries[$metadataPath] = $metadata.Replace('<componenttype>9</componenttype>','<componenttype>19</componenttype>') }
            if ($scenario -in @('ExtraAgent','ExtraAgentMetadataOnly')) {
                $entries['bots/additional_agent/bot.xml']='<bot schemaname="additional_agent"/>'
            }
            if ($scenario -in @('ExtraAgent','ExtraAgentConfigurationOnly')) {
                $entries['bots/additional_agent/configuration.json']='{"instructions":"Synthetic additional agent"}'
            }
            if ($scenario -eq 'MissingAgentMetadata') { $null=$entries.Remove('bots/demo_agent/bot.xml') }
            if ($scenario -eq 'WrongAgentMetadata') { $entries['bots/demo_agent/bot.xml']='<bot schemaname="another_agent"/>' }
            if ($scenario -eq 'BackslashAgentPath') { $entries['bots\additional_agent\bot.xml']='<bot schemaname="additional_agent"/>' }
            if ($scenario -eq 'WrongAgentDirectoryCase') { $entries['Bots/additional_agent/bot.xml']='<bot schemaname="additional_agent"/>' }
            New-PackageFixture $path $entries
            if ($scenario -in @('DuplicateAgentMetadata','DuplicateCaseVariant')) {
                $duplicatePath=if($scenario -eq 'DuplicateAgentMetadata'){'bots/demo_agent/bot.xml'}else{'bots/demo_agent/BOT.XML'}
                $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Update)
                try {
                    $writer=[IO.StreamWriter]::new($zip.CreateEntry($duplicatePath).Open())
                    try {$writer.Write('<bot schemaname="demo_agent"/>')}finally{$writer.Dispose()}
                } finally {$zip.Dispose()}
            }
            $candidate=$fixtureCandidate|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
            if($scenario -eq 'EmptyAgentExpectation'){$candidate.agents=@()}
            if($scenario -eq 'MultipleAgentExpectations'){$candidate.agents+=@{schemaName='additional_agent'}}
            if ($scenario -eq 'Complete') {
                $package = Read-SolutionPackage $path $candidate
                if ($package.version -cne '1.0.0.0' -or $package.sha256.Length -ne 64) { throw 'Invalid package identity.' }
            }
            else { Expect-Rejection { Read-SolutionPackage $path $candidate } }
        }
        finally { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop } }
    }
}
$environment = @{
    SOURCE_ENVIRONMENT_URL='https://source.example.invalid'
    SOURCE_ENVIRONMENT_ID='22222222-2222-2222-2222-222222222222'
    SOURCE_TENANT_ID='66666666-6666-6666-6666-666666666666'
    TARGET_ENVIRONMENT_URL='https://target.example.invalid'
    TARGET_ENVIRONMENT_ID='77777777-7777-7777-7777-777777777777'
    TARGET_TENANT_ID='88888888-8888-8888-8888-888888888888'
    EVALUATION_BRIDGE_URL=$config.bridgeUrl
    EVALUATION_BRIDGE_WORKFLOW_ID=$config.bridgeWorkflowId
}
$previous = @{}
try {
    foreach ($key in $environment.Keys) {
        $previous[$key]=[Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key,$environment[$key])
    }
    Test-Case 'Environment configuration comes from variables' {
        $c=Get-GateConfig
        if ($c.sourceUrl -cne 'https://source.example.invalid' -or $c.targetEnvironmentId -cne $environment.TARGET_ENVIRONMENT_ID) { throw 'Incorrect environment resolution.' }
    }
    Test-Case 'Missing environment configuration fails closed' {
        [Environment]::SetEnvironmentVariable('SOURCE_ENVIRONMENT_ID',$null)
        try { Expect-Rejection { Get-GateConfig } }
        finally { [Environment]::SetEnvironmentVariable('SOURCE_ENVIRONMENT_ID',$environment.SOURCE_ENVIRONMENT_ID) }
    }
    Test-Case 'Same source and target URL is rejected' {
        [Environment]::SetEnvironmentVariable('TARGET_ENVIRONMENT_URL',$environment.SOURCE_ENVIRONMENT_URL)
        try { Expect-Rejection { Get-GateConfig } }
        finally { [Environment]::SetEnvironmentVariable('TARGET_ENVIRONMENT_URL',$environment.TARGET_ENVIRONMENT_URL) }
    }
    Test-Case 'Same source and target ID is rejected' {
        [Environment]::SetEnvironmentVariable('TARGET_ENVIRONMENT_ID',$environment.SOURCE_ENVIRONMENT_ID)
        try { Expect-Rejection { Get-GateConfig } }
        finally { [Environment]::SetEnvironmentVariable('TARGET_ENVIRONMENT_ID',$environment.TARGET_ENVIRONMENT_ID) }
    }
    Test-Case 'Environment URL cannot contain credentials or query data' {
        [Environment]::SetEnvironmentVariable('TARGET_ENVIRONMENT_URL','https://user@target.example.invalid/?token=example')
        try { Expect-Rejection { Get-GateConfig } }
        finally { [Environment]::SetEnvironmentVariable('TARGET_ENVIRONMENT_URL',$environment.TARGET_ENVIRONMENT_URL) }
    }
}
finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key]) }
}
Write-Host "$script:count gate unit checks passed."
