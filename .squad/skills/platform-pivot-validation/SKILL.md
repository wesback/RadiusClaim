---
name: "platform-pivot-validation"
description: "Validate a deployment-story pivot by checking workflow syntax, live-safe structural evidence, and doc-to-workflow consistency"
domain: "testing"
confidence: "high"
source: "earned"
tools:
  - name: "rg"
    description: "Find stale flags, legacy platform commands, and naming residue across docs and workflows"
    when: "A repo changes its primary deployment/runtime story and drift is likely"
  - name: "bash"
    description: "Run safe structural checks like YAML parse, build/test, script syntax, and Bicep parse"
    when: "You need fresh evidence instead of trusting prior summaries"
  - name: "view"
    description: "Capture exact file/line evidence for the review report"
    when: "You need to cite specific mismatches without hand-waving"
---

## Context

Use this when a repository changes its primary deployment narrative (for example, ACA-first to Kubernetes-first, or single-cloud to recipe-driven portability). These updates often look coherent at a headline level while leaving stale workflow inputs, legacy troubleshooting commands, or secret-contract mismatches behind.

## Patterns

### Re-run structural proof first

- Parse the workflow as YAML before arguing about the story.
- Run the existing build/test commands and any script syntax checks already implied by the repo.
- Rebuild the relevant Radius/Bicep files so the platform model has fresh evidence.

### Compare docs against the executable path

- Match workflow-dispatch inputs in docs to the actual workflow input names.
- Match job names in docs/checklists to the actual workflow jobs.
- Match secret/variable descriptions to what the workflow really expects.
- Sweep for retired platform tooling (`az containerapp`, old namespaces, old product names) after a Kubernetes-first pivot.

### Treat secret-shape ambiguity as a real blocker

- If docs say a secret is base64-encoded but the workflow consumes it as raw text, do not guess.
- Call out the mismatch explicitly and require one contract.

### Clean up validation side effects

- `dotnet build/test` may dirty `bin/` and `obj/`.
- `az bicep build` may update checked-in generated `.json` outputs.
- If those changes are only validation exhaust, revert them before finishing and say so plainly.

## Examples

- `.github/workflows/deploy-azure.yml`
- `README.md`
- `docs/radius-validation-checklist.md`
- `docs/phase-7-demo-walkthrough.md`
- `docs/ADR-0001-azure-cli-fallback.md`

## Anti-Patterns

- Declaring a platform-story update “done” because the main README paragraph was rewritten.
- Trusting old phase-checklist wording after workflow/job names changed.
- Treating generated artifact churn as intentional source changes.
- Pretending live validation happened when only structural checks were possible.
