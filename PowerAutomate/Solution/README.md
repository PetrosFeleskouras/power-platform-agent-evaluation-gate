# Install the unmanaged Agent Evaluation Gate Bridge solution

**Recommended installation:** import this solution through Power Apps or
Power Automate. Azure CLI and the earlier PowerShell flow installer are not
required for normal installation.

## Download

- [Download the unmanaged solution ZIP](https://github.com/PetrosFeleskouras/power-platform-agent-evaluation-gate/releases/download/bridge-v1.0.0/AgentEvaluationGateBridge_1_0_0_0_unmanaged.zip)
- [Repository copy](AgentEvaluationGateBridge_1_0_0_0_unmanaged.zip)
- [Inspectable unpacked source](src/)

| Property | Value |
| --- | --- |
| Solution display name | Agent Evaluation Gate Bridge |
| Unique name | `AgentEvaluationGateBridge` |
| Version | `1.0.0.0` |
| Type | **Unmanaged** |
| Publisher | Agent Evaluation Gate Samples (`aeg`) |
| SHA-256 | `5744FD2E8E80849BC28CD87E6140921EA3F93868AF8F9D7BD455924C2CD81114` |

This ZIP contains one new flow, one connection reference and three environment
variable definitions. It contains no agents or evaluation datasets. The flow is
exported **Off** with safe, unconfigured defaults and no current variable values.

## 1. Choose the source environment

Import the bridge into the **DEV/source environment containing the agents to
evaluate**, not automatically into the pipeline's TEST destination.

Before importing:

- Confirm you can import unmanaged solutions and create/configure cloud flows.
- Have suitable Power Automate Premium entitlement for the HTTP Request trigger.
- Have permission to create/use a Microsoft Copilot Studio connection that can
  access the source agents and their evaluations.
- Obtain the **Entra object ID** of the service principal used by the pipeline's
  source Power Platform service connection. This is not the application/client ID.
- Confirm your DLP policies allow the HTTP trigger and Copilot Studio connector.

Use an environment where this sample solution does not already exist for the
first installation. Reimporting this unmanaged solution updates its components,
so review any changes you have made to a previous installation.

## 2. Import using the Solutions interface

1. Open [Power Apps](https://make.powerapps.com) or
   [Power Automate](https://make.powerautomate.com).
2. Select the intended source environment in the environment picker.
3. Open **Solutions > Import solution** and select the downloaded ZIP.
   Use the **Solutions** import experience, not **My flows > Import package**.
4. Review the solution name and unmanaged type.
5. When prompted, bind **Agent Evaluation Gate - Copilot Studio** to your own
   Microsoft Copilot Studio connection. Create/sign in to a connection if needed.
6. Set the environment-variable values if the wizard offers them. If it uses
   defaults or does not prompt, complete the next section after import.
7. Complete the import and open **Agent Evaluation Gate Bridge**.

The downloaded package has no connection instance embedded. If a headless or
deferred import leaves the reference unbound, open **Connection references** in
the solution and bind `aeg_CopilotStudio` before enabling the flow.

## 3. Configure all three current values

Open the solution's **Environment variables**, edit each definition, and set its
**Current value** for this environment:

| Display name / schema name | Current value to provide |
| --- | --- |
| Bridge Allowed Caller Object ID / `aeg_AllowedCallerObjectId` | The source pipeline service principal's **object ID** from Microsoft Entra **Enterprise applications** |
| Bridge Source Environment ID / `aeg_SourceEnvironmentId` | The Power Platform environment GUID containing the agent and this bridge |
| Bridge Evaluation Connection Name / `aeg_EvaluationConnectionName` | The connection instance name bound to `aeg_CopilotStudio`, beginning `shared-microsoftcopi-...` |

For the connection name, open the connection reference to identify the selected
connection, then inspect that connection's details/URL in the environment's
**Connections** page. Use its full instance name, not the connector display name
or logical reference name `aeg_CopilotStudio`.

Keep the evaluation connection name and connection reference bound to the same
connection. This value is passed as the native evaluation's `mcsConnectionId`.

The shipped defaults deliberately do not identify a caller, source environment
or usable connection:

- Caller and environment defaults: `00000000-0000-0000-0000-000000000000`.
- Connection-name default: `CONFIGURE_CONNECTION_NAME`.

Replace all three before enabling. The flow validates configuration and checks
that the request's source environment matches its configured environment before
invoking an evaluation. Keep actual values in your environment, not GitHub.

## 4. Review and enable the flow

1. Open **Cloud flows > Agent Evaluation Gate - Solution Bridge** in the imported
   solution.
2. Confirm its Copilot Studio connector actions use the bound connection.
3. Inspect **When an HTTP request is received**. Authentication must remain
   restricted to the configured caller. The allowed caller is supplied through
   the environment-variable parameter. Do not select **Anyone** or replace it
   with tenant-wide access.
4. Save if the designer requests connection confirmation, then select **Turn on**.
5. Verify the flow shows **On** and copy its HTTP POST URL from the trigger.
6. If you change environment-variable values later, save/refresh the flow and
   turn it off/on as appropriate so the runtime uses the new configuration.

The new solution flow was successfully enabled with configured environment
variables during validation and then returned to Off. An anonymous call returned
HTTP 401, and a request from the configured caller with a mismatched source
environment returned a blocking response before native evaluation.

Do not weaken trigger authentication to work around an enablement/authentication
error. Verify the connection, variable values, caller object ID, tenant and license.

## 5. Configure the Azure DevOps deployment pipeline

In your **private runtime Azure DevOps project**, set:

| Variable | Value |
| --- | --- |
| `EVALUATION_BRIDGE_URL` | The new flow's HTTP POST URL |
| `EVALUATION_BRIDGE_WORKFLOW_ID` | The 32-character workflow ID in that URL's `/workflows/<id>/` segment |

The workflow ID in the trigger URL can differ from the solution component ID or
portal flow ID. Use the URL's ID for polling validation.

Also configure the existing `SOURCE_*` and `TARGET_*` variables and service
connections from the [pipeline setup guide](../../Samples/AzureDevOps/README.md).
The source service principal must be the caller allowed by the bridge.

Keep callback URLs and connection/service-principal values in protected runtime
configuration. Do not add live bindings or test results to this public repository.

## 6. Install and run the three pipeline definitions

See [the complete start guide](../../START-HERE.md) and
[Azure DevOps setup](../../Samples/AzureDevOps/README.md) for the full variable list
and synthetic configuration shapes.

1. Copy the sample code into a **private Azure Repos repository** on `main`.
2. Install the Microsoft Power Platform Build Tools Azure DevOps extension.
3. Create DEV and TEST Power Platform service connections and grant their
   application users the appropriate Dataverse permissions.
4. Create/authorize `Generic Variables`, `DEV Environment Variables` and
   `TEST Environment Variables`, and the Azure DevOps environment named `TEST`.
5. Create new Azure DevOps YAML pipeline definitions:
   - **Commit Solution**:
     `Samples/AzureDevOps/PipelineDefinitions/commit-solution-changes.yml`
   - **CI Build**:
     `Samples/AzureDevOps/PipelineDefinitions/ci-build.yml`
   - **Deploy Solution with Agent Evaluation - Private Copy**:
     `Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml`
6. Authorize their repository, variable-group, service-connection, environment and
   pipeline-resource access. Enable the definitions for manual queuing; these
   samples intentionally use `trigger: none` and `pr: none`.
7. For each source solution, run **Commit Solution**, wait for success, then run
   **CI Build** for the same `SolutionName` and resulting source commit.
8. Manually run the new deployment definition with that `SolutionName` and
   select the corresponding successful **CI Build** resource version.
9. Review `evaluation-gate-result`. A complete pass allows the exact managed ZIP
   into TEST; other outcomes retain evidence and skip the import.

The agent solution must contain one agent, one packaged evaluation set, its
cases and required skills. Those application components are supplied by the user;
this bridge solution is installed separately from the application being gated.

## Privacy and validation

Every ZIP entry was inspected before publication. Publisher contact fields are
empty; there are no source-environment IDs, real caller IDs, connection instances,
current variable values, credentials or evaluation transcripts.

The package includes a stable **flow component GUID** so Dataverse can identify
the component across imports. That technical component identity is intentional;
it is not a person, credential or environment binding.

The exact published ZIP was imported into a second environment and verified to
contain an unmanaged solution, an Off flow, an unbound connection reference,
three definitions and no current values. Enablement was validated on the
separate source copy with private configuration. The second environment had no
Copilot Studio connection, so enablement there was not claimed.

No existing demo agents, solutions, pipelines, flows or connections were edited.
No native agent evaluation or TEST application deployment was started for this
packaging task.

## Verify or rebuild

PowerShell 7 package inspection:

```powershell
.\PowerAutomate\Solution\Test-SolutionPackage.ps1
```

Optional PAC CLI source rebuild:

```powershell
pac solution pack --folder .\PowerAutomate\Solution\src `
  --zipfile .\AgentEvaluationGateBridge_rebuilt.zip --packagetype Unmanaged
```

A rebuild may have a different ZIP hash because of packaging metadata; compare
the extracted entries and run the package test before using it. Importing through
the portal requires neither these commands nor the earlier custom flow installer.

Official guidance:

- [Import a solution containing cloud flows](https://learn.microsoft.com/en-us/power-automate/import-flow-solution)
- [Environment variables in flows](https://learn.microsoft.com/en-us/power-automate/environment-variables)
- [Connection references](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference)
