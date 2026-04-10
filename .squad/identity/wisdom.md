---
last_updated: 2026-03-23T12:42:14.492Z
---

# Team Wisdom

Reusable patterns and heuristics learned through work. NOT transcripts — each entry is a distilled, actionable insight.

## Patterns

<!-- Append entries below. Format: **Pattern:** description. **Context:** when it applies. -->

**Parameter Documentation Hygiene:** Deprecated CLI flags in documentation can persist unnoticed until they trigger warnings or cause workflow failures. Regular audits of Azure CLI and Dapr commands against official documentation prevent accumulation of outdated parameters. Short flags (e.g., `dapr init -k`) are often the documented standard; long forms with extra modifiers (e.g., `--kubernetes --wait`) may be relics. **Context:** Applicable when reviewing and maintaining step-by-step setup guides and CI/CD workflows that depend on external CLIs.

**Variable Aliasing Simplification:** Pure one-to-one variable aliases (e.g., `AKS_RESOURCE_GROUP="$AZURE_RESOURCE_GROUP"`) add cognitive load without providing value. If the alias is never expanded or decorated, remove it and use the source variable directly. This reduces context switching for users reading the guide. **Context:** Applicable when simplifying runbooks, deployment guides, and step-by-step walkthroughs that must be easy to follow.
