# New producer and private-runtime deployment copies

These files are additions. They do not change existing cloud pipeline definitions
or the original deployment YAML/template already in the repository.

## Repository and tools

- Use a private **Azure Repos** repository on `main`. Both producers verify
  repository/project identity and private visibility using `System.AccessToken`.
- Grant the Azure DevOps Build Service read/contribute permissions on that
  private repository. Checkout persists credentials for its scoped Git push.
  A GitHub credential is not supplied by an Azure DevOps job token.
- Use Microsoft-hosted Windows agents with PowerShell 7 and the Power Platform
  Build Tools extension. The version/install helpers use
  `Rnwood.Dataverse.Data.PowerShell` version `1.1.3`.
- Only the main-branch path is supported by these copies. Hotfix/other branch
  workflows need their own explicit versioning and repository checks.
- Commits use `ALM Automation <alm-automation@example.invalid>` and a fixed
  message. No requesting user's display name, email or arbitrary message is used.

## New pipeline definitions

| Display name | YAML |
| --- | --- |
| Commit Solution | [PipelineDefinitions/commit-solution-changes.yml](PipelineDefinitions/commit-solution-changes.yml) |
| CI Build | [PipelineDefinitions/ci-build.yml](PipelineDefinitions/ci-build.yml) |
| Deploy Solution with Agent Evaluation - Private Copy | [PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml](PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml) |

All are manual (`trigger: none`, `pr: none`). Configure new definitions rather
than repointing an existing verified pipeline during evaluation of these samples.

Commit Solution requires only `SolutionName`. It validates the private checkout
first, increments the source version, publishes customizations, exports both
package types, unpacks, tokenizes settings, scans the selected paths and commits
only those paths. Review those source-environment side effects before running.
An unchanged export is reported without an empty commit.

CI Build requires the same `SolutionName`. Its validation job must succeed before
the three artifact jobs run:

- `Solutions`: only the selected managed and unmanaged ZIPs.
- `Settings`: only the selected solution's tokenized JSON.
- `Scripts`: the new `.ps1` **and `.psm1`** helper bundle; keep module dependencies.

Deployment uses the same artifact names/resource selection as the original gate.
Its new import-template copy supplies script credentials/configuration through
environment variables. It still supports the original managed update/upgrade
options. Upgrades can remove omitted components; select the intended import mode.

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
explicitly mapped.** Unlike the original helper, this copy does not choose the
first connection returned by a connector query. Missing/duplicate mappings fail.
The transformation operates on a downloaded settings working copy, not the ZIP.

Configure the existing deployment variables as described in the
[original gate README](../../README.md#4-one-time-pipeline-configuration):
`SOURCE_ENVIRONMENT_URL`, `SOURCE_ENVIRONMENT_ID`, `SOURCE_TENANT_ID`,
`SOURCE_SERVICE_CONNECTION`, `TARGET_ENVIRONMENT_URL`, `TARGET_ENVIRONMENT_ID`,
`TARGET_TENANT_ID`, `TARGET_SERVICE_CONNECTION`, `EVALUATION_BRIDGE_URL` and
`EVALUATION_BRIDGE_WORKFLOW_ID`.

Use the same target connection for `TARGET_SERVICE_CONNECTION` and the TEST
group's `SPNServiceConnection`. Authorize the `TEST` Azure DevOps environment
and preserve required approvals. Configure the bridge as described in
[Bridge setup](../../PowerAutomate/Bridge/README.md).

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

Before publishing new sample content, stage only reviewed additions and run:

```powershell
pwsh -NoProfile -File .\Samples\AzureDevOps\Tests\Test-PublicationContent.ps1 -BaseRef origin/main
```

That final command checks the proposed added files, not private operational
exports. Review every new commit and release asset before a public push.
