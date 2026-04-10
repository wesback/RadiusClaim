# Camila History

## Core Context

- User: Wesley Backelant
- Project: RadiusClaim — Dapr + Radius reference sample
- Stack: .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure-backed platform story, planned web UI
- Mission: design and build a beautiful, modern frontend experience for the RadiusClaim application without weakening the portability story

## Learnings

- Added to the squad on 2026-03-24 as the dedicated frontend/UI specialist.
- Initial remit is to design a modern web interface for the expense submission and workflow visibility experience.
- Chose a hosted frontend inside `src/expense-api/wwwroot/app/` so the sample gains a polished UI without introducing a separate Node toolchain, CORS setup, or an extra deployment surface.
- Added a workflow-telemetry proxy at `GET /expenses/{id}/workflow` in `src/expense-api/Program.cs`; it derives the workflow instance from `ExpenseRecord.CorrelationId` and keeps the browser on the same origin.
- Key UI entry points now live at `src/expense-api/wwwroot/app/index.html`, `src/expense-api/wwwroot/app/styles.css`, and `src/expense-api/wwwroot/app/app.js`.
- Conducted framework landscape research (March 2026) evaluating React + Vite + TypeScript, Next.js, Vue, SvelteKit, and Blazor (WASM/Server) against RadiusClaim's constraints: same-origin hosting, Kubernetes-first portability, demo clarity, and long-term maintainability.
- **Decision**: Recommend React + Vite + TypeScript as primary choice, Vue + Vite as runner-up. Vanilla approach was the right demo-first decision but reaches its limits at scale (no type safety, monolithic state, no component reusability).
- Rationale for React: industry-standard job market (70%+ market share), mature ecosystem, excellent TypeScript support, Vite's fast HMR, ability to keep the app in `wwwroot/` without separate Node deployment, and component-based architecture makes the UI teachable.
- Migration path is non-breaking: create `src/expense-api/client/` as separate Vite project, build to `wwwroot/app/dist/`, no API changes, no deployment changes — still one .NET binary.

## Team Input (2026-03-24)

- **Daisy (Lead)** provided framework-fit analysis: Keep vanilla UI unless conditions change (UI becomes product, multiple routes needed, separate SPA deployment desired, or team composition shifts)
- Rationale: UI is demo surface, not product; framework adds pedagogical friction without advancing Dapr + Radius narrative
- **Implication for React recommendation:** Document React path for future reference; maintain vanilla JS as the appropriate choice for Phase 7
- **Status:** React recommendation is documented and ready for team; vanilla is the current path forward

## Learnings (Issue #15 — Monitoring Dashboard, 2026-03-27)

- Issue #15 asked for a workflow monitoring dashboard; the existing `wwwroot/app/` UI already covered items 1–3 (expense list with status, timeline/history, auto-refresh).
- The missing piece was approve/reject buttons for `ManualReviewRequested` expenses. Added `handleApproval()` in `app.js` that POSTs to `/expenses/{id}/approve` or `/expenses/{id}/reject`.
- Buttons appear inline in the workflow card only when `expense.status === "ManualReviewRequested"`, keeping the UI minimal and context-specific.
- Adjusted history polling from 10 s to 5 s to match the issue requirement.
- Used `--approve` / `--reject` CSS modifier classes styled with the existing `--success` / `--danger` CSS variables; no new design system tokens needed.
- Chose not to introduce a new `src/dashboard/` Next.js app — the existing vanilla UI in `wwwroot/app/` already satisfies all requirements with zero toolchain overhead.

## Learnings (Daisy's Architectural Review — Design & A11y Polish, 2026-03-28)

### Implemented MUST-FIX Items

1. **Design Tokens Documentation** (`styles.css`)
   - Added comprehensive comment block at the top of `styles.css` explaining:
     - Color palette with semantic meanings (primary, success, warning, danger, muted, border, etc.)
     - Surface layers and their opacity values for glassmorphism effect
     - Spacing/radius scale (xl, lg, md, sm) for consistent button and card styling
     - Typography font stack (system-first for performance)
   - All CSS variables now self-document their purpose and use case
   - Enables future designers to understand token intent without reverse-engineering hex values

2. **Form Validation Accessibility** (`index.html`)
   - Added `aria-describedby` to all four form inputs (employee-id, amount, currency, description)
   - Created corresponding error message containers (id="error-{fieldname}") beneath each field
   - Applied `.feedback` class to error divs with `data-tone="error"` for semantic styling
   - Error divs positioned directly under inputs so screen readers announce both the label (implicitly via <label>) and the error message
   - Structure follows WCAG 2.1 best practice: input + aria-describedby linking to adjacent error text

3. **Module Documentation & JSDoc** (`app.js`)
   - Added 40-line header comment explaining:
     - Module purpose: Expense submission, live polling, workflow telemetry
     - Data flow: Form → validation → POST → polling → render pipeline
     - State shape: describes expenses, selectedExpenseId, selectedExpense, selectedWorkflow, timers
     - Initialization: boot() → bind() → refreshExpenses() → startPolling()
     - Accessibility features: aria-live regions, aria-describedby, skip-link
   - Added JSDoc comments to 10 public functions:
     - `handleSubmit(event)`: Form POST with error handling
     - `validateSubmission(submission)`: Returns array of validation errors
     - `refreshExpenses(preserveSelection, explicitSelection)`: Fetches /expenses, updates state
     - `selectExpense(expenseId)`: Fetches detail + workflow telemetry
     - `renderStats(expenses)`: Renders summary card grid
     - `renderHistory(expenses)`: Renders expense list with selection state
     - `renderDetail(expense, errorMessage)`: Renders detail + timeline
     - `renderWorkflow(expense, workflowOrError)`: Renders workflow metrics + approval UI
     - `handleApproval(expenseId, action)`: POSTs approval decision
     - `startPolling()` / `stopPolling()`: Timer management for 5s refresh loop
   - Comments describe parameters, return types, and side effects for IDE autocompletion and future maintainers

### Design & A11y Rationale

- **Tokens as a single source of truth**: Keeping all design semantics documented in one place (top of CSS) makes it impossible for colors to drift and ensures any future theme change only touches one file
- **Error messages for screen readers**: Linking input fields to error messages via aria-describedby means assistive tech users get the same atomic feedback as sighted users—the message appears instantly when validation fails, no separate announcement needed
- **Vanilla JS, documented**: Without a framework, the module's intent must be crystal clear in comments. JSDoc on exported functions gives future readers and IDE tools the same scaffolding that TypeScript or React would provide
- **Minimal, non-intrusive changes**: No changes to the demo's visual aesthetic or interaction model; all improvements are foundational and invisible to the user experience

### Files Modified

- `src/expense-api/wwwroot/app/styles.css` — Added design tokens documentation block
- `src/expense-api/wwwroot/app/index.html` — Added aria-describedby to form fields + error containers
- `src/expense-api/wwwroot/app/app.js` — Added 40-line header comment + JSDoc on 10 functions

### Next Steps (Optional Nice-to-Haves)

- Group CSS rules by component (hero, panel, form, badge, timeline) for easier scanning
- Audit color contrast with Lighthouse/DevTools to ensure WCAG AA minimum
- Extract state mutations into named functions (e.g., `updateSelectedExpense()`, `clearSelection()`) to prep for testability
