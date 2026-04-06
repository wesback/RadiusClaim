# Skill: Debugging .NET Package Version Constraint Failures

**Category:** Dependency Management & Troubleshooting  
**Difficulty:** Intermediate  
**Owned by:** Daisy (Lead)

---

## When to Use

When a `dotnet restore` or `dotnet build` fails with:
- `error NU1102: Unable to find package X with version (>= Y.Z.A)`
- `error NU1104: Version constraint cannot be satisfied`
- Build succeeds locally but fails in Docker/CI, or vice versa

## Root Cause Patterns

### Pattern 1: Ecosystem Fragmentation

**Symptoms:**
- Primary package has version 1.11.0
- Exporter/plugin for same package maxes out at 1.5.1
- Other packages in same family all reached 1.11.0

**Example:** OpenTelemetry (1.11.0) vs. OpenTelemetry.Exporter.Jaeger (1.6.0-rc.1 max)

**Why it happens:**
- Different maintainers control different packages
- Release cadences diverge (core stable, plugins/exporters slower)
- Pre-release versions exist alongside stable gaps

**Fix approach:**
1. Research NuGet history for the problematic package
2. Identify the actual latest stable version (not aspirational)
3. Downgrade dependents to match, OR
4. Use pre-release explicitly (with risk acceptance)
5. Document the constraint in team wiki for future reference

---

### Pattern 2: Transitive Dependency Mismatch

**Symptoms:**
- Direct dependency is correct
- Build fails on a transitive dependency you didn't directly reference
- Error is from an indirect package (e.g., OpenTelemetry.Api pulled in by instrumentation package)

**Fix approach:**
1. Use `dotnet package search` or NuGet web UI to trace the dependency tree
2. Identify which direct dependency is pulling in the problematic transitive
3. Check if the direct dependency has a newer version with updated transitive deps
4. If not, explicitly pin the problematic transitive package to a compatible version

---

### Pattern 3: Local vs. Docker Mismatch

**Symptoms:**
- `dotnet restore` works on local machine
- Fails in Docker build (error: package not found)
- Timing suggests Docker has fresher package index

**Causes:**
- Local machine has cached package (from before it was delisted)
- Docker always hits fresh NuGet index
- NuGet cache may be stale or differ between environments

**Fix approach:**
1. Force clean restore on local: `dotnet nuget locals all --clear && dotnet restore`
2. Verify against NuGet.org web UI directly (don't trust local cache)
3. If package is truly unavailable, use a different version

---

## Debugging Workflow

### Step 1: Verify the Package Exists

```bash
# Check NuGet.org directly (not local cache)
dotnet nuget search OpenTelemetry.Exporter.Jaeger --exact-match

# OR visit: https://www.nuget.org/packages/OpenTelemetry.Exporter.Jaeger/
```

**Look for:**
- What versions actually exist?
- Which is marked as "latest stable"?
- Are all others marked pre-release?

### Step 2: Check Your Constraint

```bash
# In the .csproj or .sln, examine the version specification
cat ExpenseApi.csproj | grep -A 2 "OpenTelemetry"

# Look for:
# <PackageReference Include="OpenTelemetry.Exporter.Jaeger" Version="1.11.0" />
# OR
# <PackageReference Include="OpenTelemetry.Exporter.Jaeger" Version="1.11.*" />
```

**Constraint types:**
- `Version="1.11.0"` — exact match (fails if not found)
- `Version="[1.11.0]"` — exact match (same)
- `Version="1.11.*"` — range (1.11.0–1.11.999, but fails if none exist)
- `Version="1.5.1"` — exact (works if that version exists)

### Step 3: Trace Transitive Dependencies

```bash
# List all direct and transitive dependencies
dotnet list package --include-transitive

# Find what's pulling in problematic packages
dotnet list package --include-transitive | grep -i "opentelemetry"
```

### Step 4: Test Fix Locally

```bash
# Update the constraint in .csproj
# Then validate locally (before Docker):
dotnet clean
dotnet nuget locals all --clear
dotnet restore

# If successful, test build:
dotnet build
```

### Step 5: Validate in Docker

```bash
# Build the image (this uses fresh NuGet index)
docker build -t service:test .

# Check logs for any download errors or warnings
```

---

## Decision Tree

```
Does error mention NuGet (NU1102, NU1104, NU1902)?
└─ YES → Continue
   ├─ Is this a direct or transitive dependency?
   │  ├─ Direct → Go to "Handle Direct Dependency"
   │  └─ Transitive → Go to "Handle Transitive Dependency"
   └─ Is the package actually on NuGet.org?
      ├─ NO → Package was delisted; find replacement
      └─ YES → Constraint doesn't match; continue below

Is the constraint reasonable (1.5.1) or aspirational (1.11.0)?
└─ Aspirational?
   ├─ Check NuGet.org: Latest version is lower?
   │  ├─ YES → Downgrade constraint to match reality
   │  └─ NO → Pin to pre-release (acceptance needed)
   └─ Reasonable?
      └─ Check local cache: dotnet nuget locals all --clear

Has local cache been cleared?
└─ NO → Clear it, retry
└─ YES → Problem is real; downgrade or switch to alternative

Is there a pre-release version (1.6.0-rc.1)?
└─ YES → Consider using it with risk acceptance
└─ NO → Find alternative package or downgrade

Alternative packages available?
└─ YES → Document migration, update code if needed
└─ NO → Accept constraint, document for future (Phase N)
```

---

## Real-World Example: OpenTelemetry Jaeger

**Scenario:** Team set `OpenTelemetry.Exporter.Jaeger` to 1.11.0, matching other packages. Docker build failed.

**Solution applied:**
1. Verified NuGet.org: max stable version is 1.5.1
2. Identified 1.6.0-rc.1 is pre-release (higher but risky)
3. Decided to downgrade all three services to 1.5.1
4. No code changes needed (API compatible)
5. Documented constraint in team history for future phases

**Lesson:** Version parity across an ecosystem is not guaranteed. Exporters/plugins often lag behind core.

---

## Preventive Measures

1. **Before committing version pins:**
   - Check NuGet.org (not just local documentation)
   - Verify ALL related packages at target version
   - Test docker build locally before merging

2. **In team wiki:**
   - Document which packages have version ceilings
   - Note when ceilings were last verified
   - Flag packages with fragmented releases

3. **In CI/CD:**
   - Include `dotnet nuget locals all --clear` in Docker builds
   - Fail on NuGet warnings (not just errors)
   - Log exact versions resolved (for debugging diffs)

4. **In code review:**
   - Ask: "Is this version available on NuGet.org?"
   - Ask: "Are all packages in this family at this version?"
   - Request evidence (screenshot of NuGet.org or `dotnet package search` output)

---

## See Also

- **Related Skills:** None yet (first in sequence)
- **Decision Documents:**
  - `.squad/decisions/inbox/daisy-otel-jaeger-fix-plan.md` (example application of this skill)
- **Team Decisions:**
  - Check `.squad/decisions.md` for any "package ecosystem" directives
