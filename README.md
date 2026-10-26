# Agent evaluation gates for Power Platform

Run native Copilot Studio evaluations as part of an Azure DevOps release.
A complete pass allows the selected managed solution package into TEST.
Other outcomes retain the evaluation results and skip deployment.

**[Start here](START-HERE.md)** ·
**[Download the unmanaged bridge solution](https://github.com/PetrosFeleskouras/power-platform-agent-evaluation-gate/releases/download/bridge-v1.0.0/AgentEvaluationGateBridge_1_0_0_0_unmanaged.zip)** ·
**[Import and enable the flow](PowerAutomate/Solution/README.md)**

## How it works

```text
Commit Solution -> CI Build -> Evaluation-gated deployment
                                      |
                         Compare CI package with DEV
                                      |
                        Run the packaged evaluation
                              /              \
                         All pass        Other outcome
                            |                  |
                    Import to TEST       Retain results
                            |            Skip deployment
                    Verify components
```

1. **Commit Solution** exports a selected DEV solution into private source control.
2. **CI Build** produces its managed/unmanaged ZIPs, settings and deployment scripts.
3. **Deploy Solution with Agent Evaluation** downloads a selected CI build,
   validates its package against DEV and calls the Power Automate bridge.
4. The bridge runs the native evaluation and returns individual case results.
5. A complete pass authorizes that exact managed ZIP for import into TEST.

Evaluations run against the **live DEV agent**. The pipeline compares covered
agent configuration, skills and test content with the package, then rechecks
source fingerprints and the package hash before import. Keep DEV content stable
during the release.

## What is included

| Component | File or guide |
| --- | --- |
| Commit Solution | [Pipeline YAML](Samples/AzureDevOps/PipelineDefinitions/commit-solution-changes.yml) |
| CI Build | [Pipeline YAML](Samples/AzureDevOps/PipelineDefinitions/ci-build.yml) |
| Evaluation-gated deployment | [Recommended pipeline YAML](Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml) |
| Power Automate bridge | [Unmanaged solution and installation guide](PowerAutomate/Solution/README.md) |
| Pipeline configuration | [Azure DevOps setup](Samples/AzureDevOps/README.md) |
| Gate implementation | [Entry script](AgentEvaluationsProject/Pipeline/Invoke-Gate.ps1) and [helpers](AgentEvaluationsProject/Pipeline/Gate.psm1) |
| Tests and verification scope | [Validation guide](VALIDATION.md) |

These are **Azure DevOps pipelines**, not GitHub Actions workflows. Use a private
Azure Repos repository for operational solution exports and pipeline runs.

## Solution requirements

Each application solution must contain:

- Exactly one Copilot Studio agent.
- Exactly one packaged `EvaluationSet` and its nonempty set of
  `MultiTurnEvaluationCase` components.
- The agent's required skills as explicit solution members.

The active evaluation name must resolve uniquely for that agent. Its returned
test-set ID and exact case-ID set must match the packaged evaluation. Every case
must complete and every reported metric must pass. Missing data, ambiguity,
errors and timeouts prevent import.

The bridge is installed separately in the source environment. The bridge ZIP
does not contain your agents or evaluation datasets.

## Getting started

Follow [Start Here](START-HERE.md) to:

1. Prepare a private Azure Repos repository and DEV/TEST service connections.
2. Import the bridge using **Solutions > Import solution**.
3. Bind its connection reference, configure its three environment variables and
   enable the flow.
4. Configure the pipeline variables and authorize the Azure DevOps resources.
5. Run the three pipelines separately for each solution.

The deployment run requires `SolutionName` and selection of the matching CI
resource version. Service connections and environment settings are configured once.

## Using an existing CI Build

The gate can consume a compatible CI producer without changing its trigger or
build logic. The selected run must publish these **Build Artifacts**:

| Artifact | Required contents |
| --- | --- |
| `Solutions` | `<SolutionName>_managed.zip` |
| `Settings` | `<SolutionName>.json` |
| `Scripts` | Compatible deployment helpers, including their `.psm1` dependencies |

The supplied [CI Build](Samples/AzureDevOps/PipelineDefinitions/ci-build.yml)
publishes this contract for one selected solution. Its helper sources are in
[Scripts](Samples/AzureDevOps/Scripts/).

For existing workshop integrations, the
[workshop-compatible deployment entry point](Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation.yml)
is also available. For a new setup, use the recommended pipeline above with the
included helper bundle and [explicit target bindings](Samples/AzureDevOps/README.md#variable-groups).

## Reviewing results

- `evaluation-gate-result` contains the source snapshot, evaluation results and,
  when applicable, the reason deployment was blocked.
- `evaluation-gated-deployment-result` adds release and post-import verification.
- In `evaluation.json`, inspect metric statuses and grader explanations. Match
  each `testCaseId` with `source.json` to identify its question.
- In Copilot Studio, open the corresponding evaluation run to review the
  responses and detailed assessments.

Keep these artifacts private: evaluation content can include sensitive data.

## Scope and safeguards

The pipeline checks exact agent/evaluation inventories, package identity and
SHA-256, and verifies the imported components. It supports managed update/upgrade
options; review those options because upgrades can remove omitted components.

This sample targets TEST. Agent publishing, channel readiness and PROD promotion
are separate lifecycle steps. Native grading is probabilistic, and fingerprints
are change-detection guards rather than an atomic DEV lock. Combine evaluations
with human review and the release controls appropriate to your application.

## Origin and references

The deployment pattern builds on the Advanced ALM for Power Platform workshop
associated with **Sean Astrakhan** and **Parvez Ghumra**.

**Reuse permissions remain unestablished.** Public availability is not a
repository-wide open-source licence. Read [REUSE.md](REUSE.md) before redistribution
or incorporating the material into another product.

- [About agent evaluation](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-intro)
- [Evaluation connectors](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-automate-tools)
- [Run evaluations and view results](https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-agent-evaluation-results)
