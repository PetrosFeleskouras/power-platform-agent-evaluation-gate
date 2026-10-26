# Validation of the new publication copies

Validation date: 26 October 2026 (UTC).

## Preservation boundary

- Only new files are added to this GitHub repository.
- The previously published deployment pipeline, template, gate module, entry
  script, regression tests, README and gitignore are unchanged.
- No existing Azure DevOps pipeline definition was edited or run.
- No existing Power Platform agent, solution, evaluation set or connection was
  edited, and the original live bridge definition/last-modified value was preserved.
- Cloud checks used newly created validation flows. The final configured bridge
  copy is stopped. Temporary intermediate validation flows were removed.

## Executed checks

| Check | Result |
| --- | --- |
| Existing gate regression suite | 41 checks passed |
| New publication/privacy/bridge suite | 40 checks passed |
| YAML lint | All five new pipeline/template YAML files passed |
| Create-only bridge installation | Final sanitized source created a new stopped flow through the installer |
| Final bridge readback | Caller restriction, source-environment guard, stopped state and explicit polling-limit failure verified |
| Anonymous HTTP caller | HTTP 401 |
| Authenticated caller outside allowlist | HTTP 403 |
| Synthetic cloud contract: complete pass | HTTP 200, `passed: true` |
| Synthetic cloud contract: failed metric | HTTP 200, `passed: false` |
| Synthetic cloud contract: incomplete results | HTTP 200, `passed: false` |
| Synthetic cloud contract: exhausted polling | HTTP 500, `passed: false` |
| Synthetic cloud contract: timeout | HTTP 500, `passed: false` |
| Synthetic cloud contract: ambiguous match | HTTP 500, `passed: false` |
| Synthetic cloud contract: wrong environment | HTTP 500, `passed: false` |

The cloud contract fixture replaced the three connector actions with synthetic
responses, supplied synthetic identities/questions and shortened polling limits.
The discovery, counting, pass policy, environment guard and response expressions
were retained. It did **not** invoke native agent evaluations or import a
solution. This tests cloud expression/control-flow behavior, not connector data
quality or a complete new tenant deployment.

The actual connector-backed copy was installed/read back and used only for
authentication checks. It reuses a connected connector binding without editing
that connection. Installation into a tenant with different licensing, DLP,
permissions or solution-wrapping behavior must be checked separately.

## Privacy testing

Synthetic tests exercised:

- Private repository identity/visibility checks and rejection of GitHub runtime.
- Solution-name validation and narrowly scoped staging.
- Rejection of an email, token-like data, secret settings, user paths and signed
  URLs without printing matched values.
- Rejection of unsupported binary source and pre-existing staged work.
- Settings tokenization and explicit target bindings without value logging.
- Generic parser errors that withhold supplied configuration.
- Source-version calculations and explicit increment selection.
- Required caller/connection/environment configuration before flow creation.
- Preserved asynchronous responses, exact-match discovery and polling limits.

Before public push, scan the exact staged additions with
[Test-PublicationContent.ps1](Samples/AzureDevOps/Tests/Test-PublicationContent.ps1),
inspect the new commit metadata and confirm the diff is additive. Source
identifiers, credentials, local configuration, raw API outputs and validation run
history remain outside the published repository.

## Limits of the verification

- Native evaluation scores and managed import in the original demo were verified
  previously. Those existing assets were intentionally not exercised again.
- The new producer YAML was statically validated and its privacy/version/settings
  logic tested locally. A full new Azure DevOps export/build/import run is not
  claimed; users must validate it in their private runtime project.
- Pattern scans do not identify all personal names or sensitive natural-language
  facts. Manual review and private-runtime access controls remain required.
- Power Automate variable/control actions have limited secure-history support.
  Treat all flow run history and pipeline evidence as private.
- The public repository retains its existing ownership/attribution; it is not
  anonymous. The new operational examples use synthetic values.
