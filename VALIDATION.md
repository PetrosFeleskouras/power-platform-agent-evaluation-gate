# Tests and validation

Validation recorded on 26 October 2026. These results describe the tested sample;
verify permissions, policies, licensing and behavior in your own environment.

## Run the checks

From the repository root, using PowerShell 7:

```powershell
pwsh -NoProfile -File .\AgentEvaluationsProject\Pipeline\Test-Gate.ps1
pwsh -NoProfile -File .\Samples\AzureDevOps\Tests\Test-Publication.ps1
pwsh -NoProfile -File .\PowerAutomate\Solution\Test-SolutionPackage.ps1
```

These commands use local fixtures and package inspection. They do not start
native evaluations, import solutions or change cloud resources.

## Local checks

| Area | Result and coverage |
| --- | --- |
| Gate regression tests | **68 passed**: exact test-set/case IDs, complete metrics, package identity, agent inventory, duplicate ZIP entries and polling URL restrictions |
| Pipeline/privacy regression tests | **40 passed**: private repository checks, scoped staging, tokenization, explicit connection mappings, configuration guards and privacy-safe error handling |
| YAML lint | All seven pipeline/template files passed |
| Documentation navigation | Local file links checked |
| Unmanaged solution inspection | Off flow, unbound connection reference, safe variable defaults, empty publisher contact fields and expected package contents verified |
| Source rebuild | Unpacked solution source packed successfully and passed the package checks |

Read-only checks against recorded demo artifacts also confirmed that the complete
passing result and its CI package are accepted, while the 8/10 result is rejected.
Those private artifacts are not distributed here.

## Unmanaged solution

The [released ZIP](PowerAutomate/Solution/README.md) is version `1.0.0.0` with SHA-256:

```text
5744FD2E8E80849BC28CD87E6140921EA3F93868AF8F9D7BD455924C2CD81114
```

The exact ZIP was imported into a second environment and verified to contain:

- An unmanaged solution and an Off bridge flow.
- One unbound Copilot Studio connection reference.
- Three required environment-variable definitions and no current values.

Enablement was tested in the source validation environment after configuring its
connection and current values. An anonymous caller received HTTP 401; a configured
caller using the wrong source environment received a blocking response.

The second environment had no Copilot Studio connection, so enablement there was
not tested. Validation settings were removed before the final export. The public
download was verified against the tested ZIP's hash.

## Bridge behavior

The bridge's response logic was exercised using a separate cloud fixture:

| Scenario | HTTP result | `passed` |
| --- | --- | --- |
| Complete pass | 200 | `true` |
| Failed metric | 200 | `false` |
| Incomplete case results | 200 | `false` |
| Polling limit reached | 500 | `false` |
| Timeout | 500 | `false` |
| Ambiguous evaluation match | 500 | `false` |
| Wrong source environment | 500 | `false` |

That fixture substituted synthetic responses for connector calls and shortened
polling limits. It tested cloud expressions and control flow, not native agent
quality or a complete tenant deployment.

## Scope and limitations

- The producer YAML was statically checked, and its version/settings/privacy
  logic was tested locally. A full run of the adapted producer pipelines in a
  new tenant is not claimed.
- Source fingerprints detect changes; they do not lock DEV against editing.
- Pattern checks cannot detect every personal name or sensitive fact in text.
  Review solution content and keep operational repositories and artifacts private.
- Variable/control-flow history may expose intermediate data to authorized flow
  owners. Apply appropriate access and retention controls.
- The repository retains ownership metadata and workshop attribution. It is not
  anonymous; [reuse permissions](REUSE.md) remain unestablished.
