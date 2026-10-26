# Azure DevOps pipeline setup

Configure Commit Solution, CI Build and evaluation-gated deployment in your
private Azure DevOps project. Install the
[Power Automate bridge solution](../../PowerAutomate/Solution/README.md) in the
source environment before running the deployment pipeline.

## Repository and tools

- Use a private **Azure Repos** repository on `main`. Both producers verify
  repository/project identity and private visibility using `System.AccessToken`.
- Grant the Azure DevOps Build Service read/contribute permissions on that
  private repository. Checkout persists credentials for its scoped Git push.
  A GitHub credential is not supplied by an Azure DevOps job token.
- Use Microsoft-hosted Windows agents with PowerShell 7 and the Power Platform
  Build Tools extension. The version/install helpers use
  `Rnwood.Dataverse.Data.PowerShell` version `1.1.3`.
- Only the main-branch path is supported. Hotfix/other branch
  workflows need their own explicit versioning and repository checks.
- Commits use `ALM Automation <alm-automation@example.invalid>` and a fixed
  message. No requesting user's display name, email or arbitrary message is used.

## Create the pipeline definitions

In Azure DevOps, select **Pipelines > New pipeline > Azure Repos Git**, choose
your private repository, and use **Existing Azure Pipelines YAML file**.
Repeat for each entry below.

| Display name | YAML |
| --- | --- |
| Commit Solution | [PipelineDefinitions/commit-solution-changes.yml](PipelineDefinitions/commit-solution-changes.yml) |
| CI Build | [PipelineDefinitions/ci-build.yml](PipelineDefinitions/ci-build.yml) |
| Deploy Solution with Agent Evaluation | [PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml](PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml) |

Keep **CI Build** as the producer's display name; the deployment pipeline resource
references it. Authorize each definition to use its repository, variable groups,
service connections and environment resources.

All three are manual (`trigger: none`, `pr: none`). Set up separate definitions
while validating the sample, rather than replacing a working release process.

## What each pipeline does

Commit Solution requires only `SolutionName`. It validates the private checkout
first, increments the source version, publishes customizations, exports both
package types, unpacks, tokenizes settings, scans the selected paths and commits
only those paths. Review those source-environment side effects before running.
An unchanged export is reported without an empty commit.

CI Build requires the same `SolutionName`. Its validation job must succeed before
the three artifact jobs run:

- `Solutions`: only the selected managed and unmanaged ZIPs.
- `Settings`: only the selected solution's tokenized JSON.
- `Scripts`: the `.ps1` **and `.psm1`** helper bundle; keep module dependencies.

Deployment selects one CI run and uses its artifacts throughout the release.
Its import template supplies script credentials/configuration through environment
variables and supports managed update/upgrade options. Upgrades can remove omitted
components; select the intended import mode.

## Variable groups

Create and authorize these groups:

| Group | Variables |
| --- | --- |
| `Generic Variables` | Shared nonsecret settings, if any |
| `DEV Environment Variables` | `SPNServiceConnection`, `EnvironmentVariableTokens`, `ConnectionReferenceTokens` |
| `TEST Environment Variables` | `SPNServiceConnection`, `EnvironmentVariableValues`, `ConnectionReferenceTokens` |

Provide valid JSON arrays, including `[]` when there are no mappings. Store real
target values in protected pipeline configuration, never in sample files.

Synthetic shapes (values below are not usable deployment bindings):

```json
{
  "EnvironmentVariableTokens": [
    {"SchemaName": "sample_setting", "StaticToken": "SETTING_TOKEN"}
  ],
  "EnvironmentVariableValues": [
    {"StaticToken": "SETTING_TOKEN", "Value": "configure-privately"}
  ],
  "DEV_ConnectionReferenceTokens": [
    {"ConnectorId": "/providers/Microsoft.PowerApps/apis/example", "StaticToken": "CONNECTION_TOKEN"}
  ],
  "TEST_ConnectionReferenceTokens": [
    {
      "ConnectorId": "/providers/Microsoft.PowerApps/apis/example",
      "StaticToken": "CONNECTION_TOKEN",
      "ConnectionId": "configure-privately"
    }
  ]
}
```

Use `ConnectionReferenceTokens` as the actual variable name in each group;
`DEV_`/`TEST_` above only distinguish the shapes. **Target connections must be
explicitly mapped.** Each token must resolve to exactly one target connection.
Missing or duplicate mappings fail.
The transformation operates on a downloaded settings working copy, not the ZIP.

## Deployment variables

Set these variables on **Deploy Solution with Agent Evaluation**. Store credential
values in Azure DevOps service connections rather than repository files.

| Variable | Value |
| --- | --- |
| `SOURCE_ENVIRONMENT_URL` | DEV Dataverse root HTTPS URL |
| `SOURCE_ENVIRONMENT_ID` | DEV Power Platform environment GUID |
| `SOURCE_TENANT_ID` | DEV tenant GUID |
| `SOURCE_SERVICE_CONNECTION` | Source Power Platform service connection name |
| `TARGET_ENVIRONMENT_URL` | TEST Dataverse root HTTPS URL |
| `TARGET_ENVIRONMENT_ID` | TEST Power Platform environment GUID |
| `TARGET_TENANT_ID` | TEST tenant GUID |
| `TARGET_SERVICE_CONNECTION` | Target Power Platform service connection name |
| `EVALUATION_BRIDGE_URL` | The enabled bridge's authenticated HTTP trigger URL |
| `EVALUATION_BRIDGE_WORKFLOW_ID` | The 32-character workflow ID in the trigger URL |

Use the same target connection for `TARGET_SERVICE_CONNECTION` and the TEST
group's `SPNServiceConnection`. Authorize the `TEST` Azure DevOps environment
and preserve required approvals. Configure the bridge as described in
[unmanaged solution setup](../../PowerAutomate/Solution/README.md).

## Run a release

1. Run Commit Solution with the selected `SolutionName`.
2. After it succeeds, run CI Build for the same solution and its source commit.
3. Run Deploy Solution with Agent Evaluation using that solution name and select
   the corresponding CI Build resource version.
4. Review the evaluation artifacts and TEST outcome.

The application solution must contain one agent, one packaged evaluation set,
its test cases and required skills. Keep the source stable during the release.
For another solution, repeat the sequence with a separate CI run.

## Privacy checks and limits

Before Git staging, the sample rejects configured patterns for email addresses,
private keys, token-like strings, signed URLs, local user paths, actual environment
endpoints and literal secret settings. It also rejects unsupported binary/large
files and reparse points. Only the selected solution directory and settings
file may be staged; a pre-populated index blocks the commit.

Review failures locally. Matched values are not included in scanner errors.
The scanner intentionally has no skip switch. For binary/image/other source
types, implement a reviewed scanner extension before using that content.
This is a conservative sample, not an automatic classification service.

Names and sensitive facts in ordinary text can evade pattern matching. Keep the
runtime repository and all logs/artifacts private and review exported content.
Platform tasks may emit resource names; Azure DevOps masking is not a substitute
for access control. Configuration conversion errors and debugging should be
reviewed only in that private runtime.

## Regression checks

From repository root:

```powershell
pwsh -NoProfile -File .\Samples\AzureDevOps\Tests\Test-Publication.ps1
pwsh -NoProfile -File .\AgentEvaluationsProject\Pipeline\Test-Gate.ps1
```

For a source-only review of newly added sample files, stage those additions and run:

```powershell
pwsh -NoProfile -File .\Samples\AzureDevOps\Tests\Test-PublicationContent.ps1 -BaseRef origin/main
```

That check is intentionally limited to added text files. It rejects modifications
and ZIPs and is not a general release validator. Inspect solution ZIPs with
[Test-SolutionPackage.ps1](../../PowerAutomate/Solution/Test-SolutionPackage.ps1).
Review all proposed changes, commit metadata and release assets before a public push.
