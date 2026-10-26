# Complete pipeline and bridge samples

These are **separate publication copies** of the producer pipelines and evaluation
bridge. Existing deployed Power Platform and Azure DevOps assets remain intact.
The recommended bridge installation is now a standard **unmanaged solution import**.

**[Download and install the unmanaged bridge solution](PowerAutomate/Solution/README.md).**

## What is included

| Component | Entry point |
| --- | --- |
| Commit Solution copy | [commit-solution-changes.yml](Samples/AzureDevOps/PipelineDefinitions/commit-solution-changes.yml) |
| CI Build copy | [ci-build.yml](Samples/AzureDevOps/PipelineDefinitions/ci-build.yml) |
| Evaluation-gated deployment copy with private credential passing | [deploy-solution-with-agent-evaluation-private.yml](Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml) |
| Producer configuration and script dependencies | [Azure DevOps setup](Samples/AzureDevOps/README.md) |
| Unmanaged Power Automate bridge solution and portal setup | [Solution setup](PowerAutomate/Solution/README.md) |
| Earlier advanced source-based bridge option | [Source installer](PowerAutomate/Bridge/README.md) |
| Verification scope and privacy limitations | [Validation record](VALIDATION.md) |

```text
Public GitHub sample
       | copy code into your private Azure Repos project
       v
Commit Solution -> CI Build -> Evaluation-gated deployment
                                      |
                            Your own bridge instance
                                      |
                            Native evaluation in DEV
                                      |
                         Complete pass -> import to TEST
```

**Use private infrastructure for operational data.** Do not run Commit Solution
against this public repository. Exported agents, knowledge, test cases, generated
settings and evaluation results can contain private information.

The two new producer definitions require private Azure Repos on `main` before
export/build. The new deployment copy passes credential values through environment
variables instead of embedding them in script command text. It retains the
original gate and import policy. Use the new copy with the new helper bundle;
the existing deployed pipelines and their scripts are not changed by this repo.

## Quick start

1. Copy the sample repository into a **private Azure Repos repository**.
2. Install Power Platform Build Tools and configure DEV/TEST service connections
   and variable groups using the [producer guide](Samples/AzureDevOps/README.md).
3. Import the [unmanaged bridge solution](PowerAutomate/Solution/README.md) into
   your source environment through **Solutions > Import solution**. Bind the
   connection reference, configure its three current environment-variable values,
   then enable the new flow after reviewing caller restrictions.
4. Configure the deployment pipeline's existing source/target and bridge variables.
5. Create new Azure DevOps definitions for the three YAML entry points above.
   Name the CI producer **CI Build**, matching the deployment pipeline resource.
6. Run Commit Solution for one reviewed source solution. This increments its
   version, publishes source customizations and exports it to private Git.
7. Run CI Build for the same `SolutionName` and the new source commit.
8. Run the new deployment copy with that `SolutionName` and select its CI build.
   Only a complete passing evaluation authorizes the exact managed CI package.

Use the unmanaged ZIP in **Solutions > Import solution**, not the legacy
**My flows > Import package** page. The package has been imported and verified in
a second environment. The earlier source installer remains an optional advanced
alternative; it is not needed for the recommended solution installation.
Setup values and generated callback URLs stay in private runtime configuration.

## Privacy and provenance

New sample files contain synthetic bindings only. The repository's already
published account identity, Git attribution and workshop credits remain intact;
this is not an anonymous repository. No source tenant bindings, real evaluation
transcripts, flow run links or operational export packages are added here.

The producer/import pattern originates from the Advanced ALM for Power Platform
workshop credited in the [original README](README.md#origin-and-references).
The scripts/templates here are separate adaptations for private-runtime use.
No new license is assigned to inherited material.
See [REUSE.md](REUSE.md) for the current permissions status and provenance checks.

Automated privacy checks catch specified patterns and reject unsupported binary
source; they cannot certify arbitrary natural-language content as PII-free.
Review your solution content and keep runtime repositories, logs and artifacts
private, even when a scan passes.

## Updating the gate after the repository review

Update [Gate.psm1](AgentEvaluationsProject/Pipeline/Gate.psm1) and
[Invoke-Gate.ps1](AgentEvaluationsProject/Pipeline/Invoke-Gate.ps1) together in
your private runtime repository. Both evaluation-time and pre-import validation
now require the packaged test-set identity, exact case-ID set and exact agent
inventory. The bridge HTTP request/response contract remains version 2.

The unmanaged bridge ZIP is unchanged; these corrections are pipeline-side.
Use the current pipeline source from `main` rather than assuming a historical
bridge release's automatic source-code archive includes later gate fixes.
Run the [gate regression checks](AgentEvaluationsProject/Pipeline/Test-Gate.ps1)
before selecting the updated commit in Azure DevOps.
