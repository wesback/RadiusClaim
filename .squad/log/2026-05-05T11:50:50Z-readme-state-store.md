# Session Log: README State Store Documentation

**Timestamp:** 2026-05-05T11:50:50Z  
**Work Item:** Eddie — Update README Application Flow with state store backing  
**Status:** Approved & Merged

## What Happened

Eddie (Docs/Story Agent) updated README.md to explicitly surface Dapr state store backing in the Application Flow section.

## Changes

1. **Opening paragraph (line 26):** Added "All state is persisted through a **Dapr state store** (PostgreSQL on Azure, Redis locally)."
2. **Flow diagram (lines 33, 38):** Changed `[State]` → `[State Store]` labels; added durable checkpoint reference
3. **Service Boundaries table (lines 55-56):** Updated expense-api and workflow-engine to include "State Store" in their Dapr bindings

## Rationale

- Transparency: Readers now see that data persists beyond in-memory
- Clarity: Concrete backing (PostgreSQL/Azure, Redis/local) explicitly named
- Narrative flow: Aligns persistence story with portability narrative

## Impact

- Documentation accuracy improved
- No code changes or breaking changes
- Readers can trace data lineage: app → expense-api → state-store → PostgreSQL/Redis

## Decision Reference

Decision: `eddie-readme-state-store.md`  
Date: 2026-05-05  
Status: Approved  
Merged: .squad/decisions.md
