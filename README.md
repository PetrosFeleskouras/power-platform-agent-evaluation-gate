# Deploy Solution with Agent Evaluation

An **Azure DevOps YAML pipeline** that runs a packaged Copilot Studio evaluation
against the source agent and promotes the selected managed solution artifact to
TEST only after a complete pass.

This repository hosts the deployment pipeline and its gate helpers. It is not a
GitHub Actions workflow and does not create Power Platform environments, a
Power Automate bridge, service connections or a CI producer automatically.

```text
Existing Commit Solution -> Existing CI Build
                                  |
                     Select a managed CI artifact
                                  |
                  Validate package against live DEV
                                  |
                  Run native Copilot Studio evaluation
                     /                         \
                 Pass                     Other outcome
                  |                            |
         Verify package hash            Retain results
                  |                     TEST is skipped
         Existing import template
                  |
         Verify components in TEST
```

## Included files

- [Deployment pipeline](Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation.yml)
- [Gate entry script](AgentEvaluationsProject/Pipeline/Invoke-Gate.ps1):
  `Snapshot`, `Evaluate`, `BeforeImport`, `VerifyImport`
- [Gate helpers](AgentEvaluationsProject/Pipeline/Gate.psm1):
  solution discovery, package inspection, authenticated polling and result checks
- [Local regression checks](AgentEvaluationsProject/Pipeline/Test-Gate.ps1)
- [Existing workshop deployment template](Samples/AzureDevOps/Templates/deploy-solution-template.yml),
  retained as a required dependency of the new pipeline

The original paths are preserved so YAML template references and script paths
resolve without rewriting the verified implementation. This extraction adds
`pr: none` alongside `trigger: none` to keep the GitHub-hosted deployment
definition manual, including for pull requests.

## Prerequisites

### 1. A compatible CI Build in Azure DevOps

The pipeline resource is named `CI-Build` and refers to a producer named
`CI Build` in the same Azure DevOps project. Change the resource's `source` if
your producer has a different display name.

The producer can remain in another repository, including Azure Repos. Its
selected successful run must publish these **Build Artifacts**, using the
existing `PublishBuildArtifacts@1` convention:

| Artifact | Required contents |
| --- | --- |
| `Solutions` | `<SolutionName>_managed.zip` |
| `Settings` | `<SolutionName>.json`, prepared for the existing deployment template |
| `Scripts` | The existing workshop deployment script bundle, including `IsSolutionInstalled.ps1` and `TransformDeploymentSettingsFile.ps1` and their dependencies |

These scripts and the solution packages come from the selected CI run; they are
not copied into this repository. The original workshop producer's script bundle
is the verified dependency. A different producer must supply compatible scripts
with the same parameters and deployment-variable behavior.

**CI does not have to be redesigned for the evaluation gate.** Its trigger can
be automatic or manual, and its artifacts may contain additional solutions. It
must produce the managed package and settings for the solution selected at
deployment time. A producer hardcoded to an unrelated solution will not supply
the required package.

### 2. Solution and evaluation in the source environment

The source solution must contain:

- Exactly one Copilot Studio agent.
- Exactly one `EvaluationSet` Test case component.
- Its nonempty set of `MultiTurnEvaluationCase` child components.
- Explicit membership for the agent's skills.

The named active evaluation must resolve uniquely for that agent in the bridge.
The case count is discovered rather than hardcoded. The release rule requires
every case to complete and every reported metric to pass.

The evaluation runs on **live DEV content**, not inside a ZIP. Covered agent
configuration, skills and evaluation payloads are compared with the downloaded
package. Keep source content stable during export, evaluation and deployment.

### 3. Power Platform authentication and evaluation bridge

Install the Microsoft Power Platform Build Tools extension in Azure DevOps.
Create source and target Power Platform service connections with the Dataverse
permissions needed for discovery/exported-component reads and managed import.
The hosted jobs use `windows-latest` and PowerShell 7.

Configure an authenticated Power Automate HTTP bridge in DEV, using the native
Microsoft Copilot Studio evaluation connector. An already configured bridge from
the original deployment can be reused with its owner's authorization.

**The bridge flow is an external dependency and is not exported here.** Its
connection and caller allowlist are environment-specific. Configure the trigger
for the intended source automation identity; do not use anonymous access.
Use asynchronous HTTP responses for long-running evaluations. The caller handles
`202`/`Location` polling and expects a final HTTP `200` JSON result.

The bridge contract used by the included scripts:

- Request fields: `solutionUniqueName`, `evaluationName`,
  `sourceEnvironmentId`, `agentIds`, `correlationId`, `artifactSha256`,
  `sourceFingerprint`.
- The bridge finds exactly one active evaluation with the requested name across
  the supplied agent IDs, starts that evaluation, polls to completion, and
  returns the run identity and individual metric results.
- Response fields: `schemaVersion` (integer `2`), the echoed
  `solutionUniqueName`, `evaluationName`, `correlationId`, `artifactSha256`,
  `sourceFingerprint`, plus `flowRunId`, `evaluationRunId`, `environmentId`,
  `agentId`, `testSetId`, `state`, `expectedTests`, `totalTests`, `passedTests`,
  `passed` (JSON boolean), and `testCasesResults`.
- Each case has `testCaseId`, `state` and nonempty `metricsResults`. Each metric
  has `type` and `result.status` (`Pass` or `Fail`). Successful release evidence
  requires `Completed` run/case states and counts consistent with every case.
- `expectedTests` comes from the evaluation start response. Return the completed
  individual results even when some cases fail: the caller retains that evidence
  and blocks import. Discovery errors, incomplete results and timeouts also block.

See [Assert-GateResponse](AgentEvaluationsProject/Pipeline/Gate.psm1) and
[the regression fixtures](AgentEvaluationsProject/Pipeline/Test-Gate.ps1)
for the exact consumer-side validation. No live bridge URL, tenant ID, connection
binding, solution export or run evidence is included in this repository.

### 4. One-time pipeline configuration

Create these nonsecret pipeline variables; keep credential values in Azure
DevOps service connections:

| Variable | Purpose |
| --- | --- |
| `SOURCE_ENVIRONMENT_URL` | DEV Dataverse root HTTPS URL |
| `SOURCE_ENVIRONMENT_ID` | DEV Power Platform environment GUID |
| `SOURCE_TENANT_ID` | DEV tenant GUID |
| `SOURCE_SERVICE_CONNECTION` | Source Power Platform service connection name |
| `TARGET_ENVIRONMENT_URL` | TEST Dataverse root HTTPS URL |
| `TARGET_ENVIRONMENT_ID` | TEST Power Platform environment GUID |
| `TARGET_TENANT_ID` | TEST tenant GUID |
| `TARGET_SERVICE_CONNECTION` | Target Power Platform service connection name |
| `EVALUATION_BRIDGE_URL` | Authenticated HTTP trigger URL |
| `EVALUATION_BRIDGE_WORKFLOW_ID` | Workflow ID in that URL (32 hexadecimal characters) |

Create/authorize the variable groups `Generic Variables` and
`TEST Environment Variables`. The latter supplies `SPNServiceConnection`,
`EnvironmentVariableValues` and `ConnectionReferenceTokens` for the unchanged
import template. Use the same target service connection for
`SPNServiceConnection` and `TARGET_SERVICE_CONNECTION`, so the pre-import check
and actual import address the same environment. Populate deployment-setting
values according to your existing workshop setup.

Create/authorize the Azure DevOps environment named `TEST`. Retain any required
environment approval checks. Authorize the pipeline to use its variable groups,
service connections and CI artifact resource.

## Connect this GitHub repository to Azure DevOps

1. In Azure DevOps, choose **Pipelines > New pipeline > GitHub**.
2. Authorize access to this repository, including access if it is private.
3. Select **Existing Azure Pipelines YAML file** and choose:
   `Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation.yml`.
4. Save the pipeline as **Deploy Solution with Agent Evaluation**.
5. Configure the prerequisites and variables above before running.
6. Run your existing Commit Solution and CI Build for the desired solution.
7. Manually run this deployment pipeline. Enter `SolutionName`, select the
   matching successful CI resource version and review the import-option defaults.
8. Review the evaluation evidence and TEST deployment outcome.

Hosting the YAML on GitHub does not move or replace existing Azure DevOps
pipelines. Connect it as a new definition or deliberately repoint an existing
definition after validation. The repository upload itself queues no deployment.

## Results and controls

- `evaluation-gate-result` is published for evaluation success or failure.
- On a complete pass, the pipeline verifies the exact package hash and invokes
  the existing deployment template using target settings.
- The template supports managed update/upgrade options. Review those options
  before running; upgrades can remove components omitted from a newer solution.
- `evaluation-gated-deployment-result` retains the post-import verification.
- Import verification covers the solution, agent, skills, evaluation and cases.
  Explicit agent publishing and channel readiness are separate lifecycle steps.
- This implementation targets TEST only.

Native grading is probabilistic. Source fingerprints are change-detection
guards, not atomic DEV locks. Package/content checks and a passing evaluation
are useful release evidence, not comprehensive certification of every scenario.
Use task-appropriate graders, human review and wider ALM controls.

## Validate locally

From the repository root, using PowerShell 7:

```powershell
pwsh -NoProfile -File .\AgentEvaluationsProject\Pipeline\Test-Gate.ps1
```

These checks exercise response validation and package fixtures without starting
native evaluations or importing a solution. Azure DevOps compilation, service
connection authorization, the external bridge and a representative CI artifact
must also be verified in each destination setup.

## Origin and references

The evaluation pipeline/helpers were developed for a Power Platform ALM demo.
The included deployment template is reused from the Advanced ALM for Power
Platform workshop associated with Sean Astrakhan and Parvez Ghumra; it is a
dependency, not newly authored gate logic. This extraction does not assign a new
license to inherited workshop material. Confirm redistribution permissions before
making a public release.

- [Microsoft Learn: agent evaluation](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-intro)
- [Microsoft Learn: evaluation connectors](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-automate-tools)
- [Microsoft Learn: run evaluations and view results](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-results)
