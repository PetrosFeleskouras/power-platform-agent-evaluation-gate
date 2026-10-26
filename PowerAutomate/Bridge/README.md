# Evaluation bridge: sanitized source and create-only installer

> **Recommended:** use the [unmanaged solution and portal installation guide](../Solution/README.md).
> This earlier source-based installer remains available as an advanced option;
> it is not required when importing the solution.

This is a new copy of the existing evaluation bridge. The public definition
contains placeholders rather than connection instances, caller identities or
environment IDs. Installing it **creates a new flow** and never updates an
existing one.

## Contents

- [definition.template.json](definition.template.json): inspectable Logic Apps
  definition, preserving native test discovery, polling and gate response v2.
- [BridgeTools.psm1](BridgeTools.psm1): constructs the configured creation request
  in memory and rejects missing/invalid configuration.
- [Install-Bridge.ps1](Install-Bridge.ps1): create-only installation with stopped
  state, duplicate-name guard and configuration readback.
- [.gitignore](.gitignore): local configuration stays in `.local/` or
  `*.local.json` files and is excluded from Git.

The JSON in this directory is not a portal-import ZIP. This advanced option uses
the Power Automate management API. The separately published
[unmanaged solution ZIP](../Solution/README.md) uses the normal Solutions import
experience and includes environment-variable definitions and a connection reference.

## Prerequisites

- Azure CLI signed in to the intended tenant with permission to create flows.
- PowerShell 7 and the ability to obtain an access token for the Flow API.
- A Premium-capable Power Automate environment: the authenticated HTTP Request
  trigger requires Premium.
- An existing **Connected** Microsoft Copilot Studio connection in that
  environment, accessible to the signed-in creator.
- The Entra **object ID** of the caller allowed to invoke the bridge. For the
  pipeline, use the source automation service principal's object ID, not its
  application/client ID.
- An agent evaluation capability and test sets available to that connection.

The template uses `Embedded` connector references. The existing connection is
bound to the new flow; it is not edited or recreated.

## Create a new instance

1. Sign in with `az login --tenant <your-tenant-id>`. Check `az account show`
   privately to confirm the intended tenant.
2. Obtain your environment ID, connected Copilot Studio connection name and
   allowed caller object ID from your own admin/configuration tools.
3. Store those values in an ignored `.local/` directory if you use a config file.
   Do not commit a rendered creation request or callback URL.
4. In PowerShell, set the variables privately and run:

```powershell
# Set these from your private configuration, not public source.
$environmentId = $env:BRIDGE_ENVIRONMENT_ID
$callerObjectId = $env:BRIDGE_CALLER_OBJECT_ID
$connectionName = $env:BRIDGE_CONNECTION_NAME

.\PowerAutomate\Bridge\Install-Bridge.ps1 `
    -EnvironmentId $environmentId `
    -CallerObjectId $callerObjectId `
    -ConnectionName $connectionName `
    -Name 'Agent Evaluation Bridge'
```

`-WhatIf` validates configuration without creating a flow. An existing display
name is rejected; choose a new name rather than using this as an update command.
If a network timeout occurs, inspect your private flow list before retrying.

The installer prints the new flow ID and leaves it **Stopped**. Keep that output
private. Review the new instance in Power Automate before enabling it:

- HTTP trigger authentication is restricted to the configured caller.
- The Copilot Studio connection and `mcsConnectionId` profile binding agree.
- The source environment guard contains the intended environment ID.
- Both HTTP response paths are asynchronous.
- Secure inputs/outputs are set where supported.

Enable only your newly created instance. Copy its HTTP trigger URL into the
deployment pipeline's `EVALUATION_BRIDGE_URL`, and the workflow ID from that URL
into `EVALUATION_BRIDGE_WORKFLOW_ID`. That URL workflow ID may differ from the
flow ID displayed in the portal. Keep the configured caller allowlist restricted.

## Execution contract

The existing deployment caller supplies the solution name, evaluation name,
source environment ID, agent IDs, correlation ID, artifact hash and source
fingerprint. The bridge validates its configured source environment before
discovery and then:

1. Lists active test sets for the supplied agent IDs.
2. Requires exactly one exact evaluation-name match.
3. Starts the native evaluation once (no automatic start retry).
4. Polls at 15-second intervals with a 20-minute/80-iteration limit.
5. Validates result identities, counts, unique case IDs and metric outcomes.
6. Returns response contract version 2 with individual case/metric results.

The pipeline retains the result and independently applies its release checks.
Incomplete/ambiguous discovery, invalid output or timeout returns an error and
cannot authorize import. The gate helper's own deadline and artifact checks remain
unchanged.

## Runtime privacy

Connector actions use secure inputs and outputs; the trigger and data/response
actions use the supported secure-history settings. **Variable and control-flow
actions do not support all secure-data options.** Their intermediate data can
still be visible to authorized flow owners in run history. Restrict flow owner
access, use private pipeline artifacts, and do not publish run histories.

This sample's code contains no operational evaluation data. Your runtime results
may include questions, responses or grader explanations containing private data.
Use synthetic cases for public demonstrations and apply your retention policy.

## Validation and support boundary

The installer was exercised against Power Automate using a newly created stopped
flow. The new copy was briefly enabled to confirm anonymous access returned HTTP
401 and an authenticated non-allowlisted identity returned HTTP 403; it was then
returned to Stopped. The original bridge was not edited.

The offline tests cover configuration guards and preserve the existing gate
validation tests. Native passing/failing evaluation and target import must be
verified in your own private setup before production use. This publication task
does not claim a new end-to-end deployment in every tenant.

See [validation details](../../VALIDATION.md) and the
[official connector guidance](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-automate-tools).
