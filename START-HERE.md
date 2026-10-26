# Start here

Set up a release path that evaluates an agent in DEV before importing its managed
solution into TEST.

## Before you begin

You need:

- A private Azure DevOps project and Azure Repos repository.
- DEV and TEST Dataverse environments with suitable Power Platform permissions.
- Power Platform Build Tools installed in Azure DevOps.
- Power Automate Premium entitlement for the bridge's HTTP trigger.
- A Copilot Studio agent solution containing an evaluation set and its test cases.
- Permission to configure service connections, variable groups and the TEST
  Azure DevOps environment.

Review the [reuse terms](REUSE.md) before adapting or redistributing the sample.

## 1. Prepare your runtime repository

Place the sample code in a **private Azure Repos repository** on `main`, preserving
the directory structure. Commit Solution and CI Build check repository visibility
before exporting or building.

Keep agent exports, generated settings, connection values and evaluation evidence
in private infrastructure. The public repository is a source distribution, not
the destination for operational exports.

## 2. Import and enable the bridge

Follow the [solution installation guide](PowerAutomate/Solution/README.md):

1. Download the unmanaged solution ZIP.
2. Import it into the source environment through **Solutions > Import solution**.
3. Bind the Copilot Studio connection reference.
4. Set the current values for allowed caller, source environment and evaluation
   connection name.
5. Review the caller restriction, then turn on the flow.

The flow is delivered Off with unconfigured defaults. Save its trigger URL and
the workflow ID from that URL for the deployment pipeline.

## 3. Configure Azure DevOps

Use the [pipeline setup guide](Samples/AzureDevOps/README.md) to configure:

- DEV and TEST service connections.
- `Generic Variables`, `DEV Environment Variables` and `TEST Environment Variables`.
- The deployment pipeline's source, target and bridge variables.
- Repository permissions, resource authorization and any TEST approval checks.

Create these pipeline definitions:

| Name | YAML |
| --- | --- |
| Commit Solution | [commit-solution-changes.yml](Samples/AzureDevOps/PipelineDefinitions/commit-solution-changes.yml) |
| CI Build | [ci-build.yml](Samples/AzureDevOps/PipelineDefinitions/ci-build.yml) |
| Deploy Solution with Agent Evaluation | [deploy-solution-with-agent-evaluation-private.yml](Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml) |

Use **CI Build** as the producer's name because the deployment resource references
it. All three pipelines are manually queued.

## 4. Run one release

1. Run **Commit Solution** with your `SolutionName`. It increments the version,
   publishes source customizations and exports the solution into private Git.
2. Wait for success, then run **CI Build** for that solution and its resulting
   source commit.
3. Run **Deploy Solution with Agent Evaluation** with the same solution name.
   Select the successful CI resource version from step 2.
4. Review the evaluation result and deployment outcome.

For a second solution, repeat the complete sequence with a separate CI build.
Keep the source agent and evaluation stable throughout each release.

## 5. Inspect the evidence

Download `evaluation-gate-result` from the deployment run Summary. A successful
import also publishes `evaluation-gated-deployment-result`.

The gate requires all cases and metrics to pass, the returned evaluation
identities to match the packaged tests, and the package hash to remain unchanged.
Other outcomes skip TEST and retain diagnostic evidence.

## Maintenance

Update [Gate.psm1](AgentEvaluationsProject/Pipeline/Gate.psm1) and
[Invoke-Gate.ps1](AgentEvaluationsProject/Pipeline/Invoke-Gate.ps1) together.
Use current pipeline source from `main`; a bridge release's automatic source-code
archive may predate later pipeline fixes. The bridge HTTP contract is version 2.

Run the [regression checks](VALIDATION.md#run-the-checks) before adopting code
changes, then validate in your private environment.
