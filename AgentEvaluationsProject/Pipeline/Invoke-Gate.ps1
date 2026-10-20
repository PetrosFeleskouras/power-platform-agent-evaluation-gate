[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Snapshot','Evaluate','BeforeImport','VerifyImport')][string]$Action,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$PackagePath,
    [string]$CorrelationId,
    [string]$SolutionUniqueName = $env:SOLUTION_UNIQUE_NAME
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Gate.psm1') -Force
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$snapshotPath = Join-Path $OutputDirectory 'source.json'
$manifestPath = Join-Path $OutputDirectory 'release.json'

try {
    $config = Get-GateConfig
    Assert-SolutionName $SolutionUniqueName
    $isSource = $Action -in @('Snapshot','Evaluate')
    $expectedUrl = if ($isSource) { $config.sourceUrl } else { $config.targetUrl }
    if ([string]::IsNullOrWhiteSpace($env:GATE_ENVIRONMENT_URL) -or $env:GATE_ENVIRONMENT_URL.TrimEnd('/') -ine $expectedUrl) {
        throw 'Service connection URL does not match the configured environment.'
    }
    switch ($Action) {
        'Snapshot' {
            $stamp = Get-SourceStamp $config $SolutionUniqueName
            $stamp | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $snapshotPath -Encoding utf8
            Write-Host "Source solution resolved with one agent and evaluation '$($stamp.agents[0].evaluation.name)'."
        }
        'Evaluate' {
            if ([string]::IsNullOrWhiteSpace($CorrelationId)) { throw 'A build-specific correlation ID is required.' }
            $stamp = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable
            if ($stamp.solutionName -cne $SolutionUniqueName) { throw 'Snapshot belongs to another solution.' }
            $evaluationName = [string]$stamp.agents[0].evaluation.name
            $package = Read-SolutionPackage $PackagePath $stamp
            if ([version]$package.version -ne [version]$stamp.solutionVersion) { throw 'Export version differs from source snapshot.' }
            $before = Get-SourceStamp $config $SolutionUniqueName
            if ($before.fingerprint -cne $stamp.fingerprint) { throw 'Source changed during export; start a fresh run.' }
            $request = @{
                solutionUniqueName=$SolutionUniqueName; evaluationName=$evaluationName
                sourceEnvironmentId=$config.sourceEnvironmentId; agentIds=@($stamp.agents.agentId)
                correlationId=$CorrelationId; artifactSha256=$package.sha256; sourceFingerprint=$stamp.fingerprint
            }
            $result = Invoke-EvaluationBridge $config $request
            $result | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'evaluation.json') -Encoding utf8
            Assert-GateResponse $result $request $config
            $after = Get-SourceStamp $config $SolutionUniqueName
            if ($after.fingerprint -cne $stamp.fingerprint) { throw 'Source changed during evaluation; result cannot authorize this package.' }
            @{
                solutionName=$SolutionUniqueName; solutionVersion=$package.version; evaluationName=$evaluationName
                agents=$stamp.agents; evaluatedAgentId=$result.agentId; testSetId=$result.testSetId
                sourceEnvironmentId=$config.sourceEnvironmentId; targetEnvironmentId=$config.targetEnvironmentId
                sourceUrl=$config.sourceUrl; targetUrl=$config.targetUrl
                artifactSha256=$package.sha256; sourceFingerprint=$stamp.fingerprint
                evaluationRunId=$result.evaluationRunId; flowRunId=$result.flowRunId
                correlationId=$CorrelationId; passed=$true
            } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
            Write-Host "Evaluation gate PASSED: $($result.passedTests)/$($result.totalTests)."
            Write-Host '##vso[task.setvariable variable=gatePassed;isOutput=true]true'
        }
        'BeforeImport' {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
            if ($manifest.passed -isnot [bool] -or -not $manifest.passed -or
                $manifest.solutionName -cne $SolutionUniqueName -or
                $manifest.sourceEnvironmentId -cne $config.sourceEnvironmentId -or
                $manifest.targetEnvironmentId -cne $config.targetEnvironmentId -or
                $manifest.sourceUrl -cne $config.sourceUrl -or $manifest.targetUrl -cne $config.targetUrl) {
                throw 'Release manifest does not authorize the configured solution and target.'
            }
            $package = Read-SolutionPackage $PackagePath $manifest
            if ($package.sha256 -cne $manifest.artifactSha256 -or $package.version -cne $manifest.solutionVersion) { throw 'Artifact changed after evaluation.' }
            $result = Get-Content -LiteralPath (Join-Path $OutputDirectory 'evaluation.json') -Raw | ConvertFrom-Json -AsHashtable
            $expected = @{
                solutionUniqueName=$SolutionUniqueName; evaluationName=$manifest.evaluationName
                correlationId=$manifest.correlationId; artifactSha256=$manifest.artifactSha256
                sourceFingerprint=$manifest.sourceFingerprint; agentIds=@($manifest.agents.agentId)
            }
            Assert-GateResponse $result $expected $config
            if ($result.evaluationRunId -cne $manifest.evaluationRunId -or $result.agentId -cne $manifest.evaluatedAgentId -or
                $result.testSetId -cne $manifest.testSetId -or $result.flowRunId -cne $manifest.flowRunId) {
                throw 'Release and evaluation identities differ.'
            }
            $existing = @(Get-DataverseRows $config.targetUrl "solutions?`$select=solutionid,version,ismanaged&`$filter=uniquename eq '$SolutionUniqueName'")
            if ($existing.Count -gt 1) { throw 'Ambiguous target solution.' }
            if ($existing.Count -eq 1) {
                if (-not $existing[0].ismanaged) { throw 'Target has an unmanaged solution with this name; no overwrite or uninstall will be attempted.' }
                if ([version]$existing[0].version -gt [version]$manifest.solutionVersion) { throw 'Refusing a solution downgrade.' }
            }
            Write-Host 'Target, artifact and passing evaluation evidence verified.'
        }
        'VerifyImport' {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
            $solutions = @(Get-DataverseRows $config.targetUrl "solutions?`$select=solutionid,version,ismanaged&`$filter=uniquename eq '$SolutionUniqueName'")
            if ($solutions.Count -ne 1 -or -not $solutions[0].ismanaged -or [version]$solutions[0].version -ne [version]$manifest.solutionVersion) {
                throw 'Managed solution/version not verified in target.'
            }
            $imported = @()
            foreach ($agent in $manifest.agents) {
                $schemaLiteral = $agent.schemaName.Replace("'","''")
                $bots = @(Get-DataverseRows $config.targetUrl "bots?`$select=botid,schemaname&`$filter=schemaname eq '$schemaLiteral'")
                if ($bots.Count -ne 1) { throw "Imported agent not found uniquely: $($agent.schemaName)" }
                $skills = @(Get-DataverseRows $config.targetUrl "botcomponents?`$select=schemaname&`$filter=_parentbotid_value eq $($bots[0].botid) and componenttype eq 9")
                foreach ($skill in $agent.skills) {
                    if (@($skills | Where-Object { $_.schemaname -ceq $skill.schemaName }).Count -ne 1) {
                        throw "Imported skill missing or ambiguous: $($skill.schemaName)"
                    }
                }
                $testComponents = @(Get-DataverseRows $config.targetUrl "botcomponents?`$select=botcomponentid,schemaname,name,componenttype,_parentbotcomponentid_value&`$filter=_parentbotid_value eq $($bots[0].botid) and componenttype eq 19")
                $testSet = @($testComponents | Where-Object { $_.schemaname -ceq $agent.evaluation.schemaName })
                if ($testSet.Count -ne 1) { throw "Imported evaluation set missing or ambiguous: $($agent.evaluation.schemaName)" }
                foreach ($testCase in $agent.evaluation.cases) {
                    if (@($testComponents | Where-Object {
                        $_.schemaname -ceq $testCase.schemaName -and
                        $_._parentbotcomponentid_value -eq $testSet[0].botcomponentid
                    }).Count -ne 1) {
                        throw "Imported evaluation case missing or ambiguous: $($testCase.schemaName)"
                    }
                }
                $imported += @{
                    agentId=$bots[0].botid
                    schemaName=$agent.schemaName
                    evaluationName=$agent.evaluation.name
                    verifiedTestCases=$agent.evaluation.cases.Count
                    verifiedSkills=@($agent.skills | ForEach-Object { $_.schemaName })
                }
            }
            @{
                state='Imported'; environmentId=$config.targetEnvironmentId; solutionName=$SolutionUniqueName
                solutionVersion=$solutions[0].version; agents=$imported; artifactSha256=$manifest.artifactSha256
                publishedByPipeline=$false
            } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'deployment.json') -Encoding utf8
            Write-Host 'Managed solution, agent, skills and packaged evaluation verified in target. No explicit agent publish was performed.'
        }
    }
}
catch {
    $message = $_.Exception.Message
    Write-Error $message -ErrorAction Continue
    @{action=$Action; solutionUniqueName=$SolutionUniqueName; error=$message} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $OutputDirectory 'failure.json') -Encoding utf8
    exit 1
}
