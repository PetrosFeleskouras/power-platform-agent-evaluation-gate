# Complete pipeline and bridge samples

These are **new publication copies** of the producer pipelines and evaluation
bridge. The previously published deployment pipeline, template, helpers and root
README are preserved unchanged as the original snapshot. This guide describes
the additional, privacy-oriented setup.

## What is included

| Component | Entry point |
| --- | --- |
| Commit Solution copy | [commit-solution-changes.yml](Samples/AzureDevOps/PipelineDefinitions/commit-solution-changes.yml) |
| CI Build copy | [ci-build.yml](Samples/AzureDevOps/PipelineDefinitions/ci-build.yml) |
| Evaluation-gated deployment copy with private credential passing | [deploy-solution-with-agent-evaluation-private.yml](Samples/AzureDevOps/PipelineDefinitions/deploy-solution-with-agent-evaluation-private.yml) |
| Producer configuration and script dependencies | [Azure DevOps setup](Samples/AzureDevOps/README.md) |
| Sanitized Power Automate bridge source and create-only installer | [Bridge setup](PowerAutomate/Bridge/README.md) |
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
3. Use the [bridge installer](PowerAutomate/Bridge/README.md) to create a **new,
   stopped** flow bound to your environment, Copilot Studio connection and allowed
   automation identity. Review its configuration, then enable your new instance.
4. Configure the deployment pipeline's existing source/target and bridge variables.
5. Create new Azure DevOps definitions for the three YAML entry points above.
   Name the CI producer **CI Build**, matching the deployment pipeline resource.
6. Run Commit Solution for one reviewed source solution. This increments its
   version, publishes source customizations and exports it to private Git.
7. Run CI Build for the same `SolutionName` and the new source commit.
8. Run the new deployment copy with that `SolutionName` and select its CI build.
   Only a complete passing evaluation authorizes the exact managed CI package.

A cloud flow JSON definition is **not** a Power Automate portal import ZIP. This
release provides inspectable source and a tested create-only installer instead
of an unverified archive. Setup values and generated callback URLs stay local.

## Privacy and provenance

New sample files contain synthetic bindings only. The repository's already
published account identity, Git attribution and workshop credits remain intact;
this is not an anonymous repository. No source tenant bindings, real evaluation
transcripts, flow run links or operational export packages are added here.

The producer/import pattern originates from the Advanced ALM for Power Platform
workshop credited in the [original README](README.md#origin-and-references).
The scripts/templates here are separate adaptations for private-runtime use.
No new license is assigned to inherited material.

Automated privacy checks catch specified patterns and reject unsupported binary
source; they cannot certify arbitrary natural-language content as PII-free.
Review your solution content and keep runtime repositories, logs and artifacts
private, even when a scan passes.
