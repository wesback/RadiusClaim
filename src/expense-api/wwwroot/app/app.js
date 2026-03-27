const state = {
    expenses: [],
    selectedExpenseId: null,
    selectedExpense: null,
    selectedWorkflow: null,
    historyTimer: null,
    selectedTimer: null
};

const elements = {
    form: document.querySelector("#expense-form"),
    submitButton: document.querySelector("#submit-button"),
    feedback: document.querySelector("#form-feedback"),
    history: document.querySelector("#expense-history"),
    detail: document.querySelector("#expense-detail"),
    workflow: document.querySelector("#workflow-detail"),
    stats: document.querySelector("#stat-grid"),
    connection: document.querySelector("#connection-state"),
    refreshButtons: document.querySelectorAll("[data-refresh]")
};

const currencyFormatter = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
});

const statusToneMap = {
    Submitted: "submitted",
    Approved: "approved",
    Reimbursed: "reimbursed",
    ManualReviewRequested: "manual",
    Rejected: "rejected",
    Pending: "muted",
    Running: "submitted",
    Completed: "approved",
    Unavailable: "error"
};

bind();
boot();

function bind() {
    elements.form?.addEventListener("submit", handleSubmit);
    elements.refreshButtons.forEach((button) => {
        button.addEventListener("click", async () => {
            await refreshExpenses(true);
        });
    });

    document.querySelectorAll("[data-preset]").forEach((button) => {
        button.addEventListener("click", () => applyPreset(button.getAttribute("data-preset")));
    });
}

async function boot() {
    renderStats([]);
    renderHistory([]);
    renderDetail(null);
    renderWorkflow(null, null);
    await refreshExpenses(true);
    startPolling();
}

async function handleSubmit(event) {
    event.preventDefault();
    const submission = getSubmission();
    const validation = validateSubmission(submission);

    if (validation.length > 0) {
        renderFeedback(validation.join(" "), "error");
        return;
    }

    setSubmitting(true);
    renderFeedback("Submitting expense…", "muted");

    try {
        const response = await fetch("/expenses", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(submission)
        });

        if (!response.ok) {
            const problem = await safeProblem(response);
            await hydratePersistedExpense(problem);
            const details = extractProblemDetails(problem);
            throw new Error(details || "The expense could not be submitted.");
        }

        const createdExpense = await response.json();
        renderFeedback(`Expense ${createdExpense.expenseId} is in motion.`, "success");
        elements.form.reset();
        document.querySelector("#currency").value = "USD";
        await refreshExpenses(false, createdExpense.expenseId);
    } catch (error) {
        renderFeedback(error.message || "The expense could not be submitted.", "error");
    } finally {
        setSubmitting(false);
    }
}

function getSubmission() {
    return {
        employeeId: document.querySelector("#employee-id").value.trim(),
        amount: Number.parseFloat(document.querySelector("#amount").value),
        currency: document.querySelector("#currency").value.trim().toUpperCase(),
        description: document.querySelector("#description").value.trim()
    };
}

function validateSubmission(submission) {
    const errors = [];

    if (!submission.employeeId) {
        errors.push("Employee ID is required.");
    }

    if (!Number.isFinite(submission.amount) || submission.amount <= 0) {
        errors.push("Amount must be greater than zero.");
    }

    if (!submission.currency) {
        errors.push("Currency is required.");
    }

    if (!submission.description) {
        errors.push("Description is required.");
    }

    return errors;
}

function applyPreset(type) {
    if (type === "manual") {
        document.querySelector("#employee-id").value = "emp-demo-002";
        document.querySelector("#amount").value = "150.00";
        document.querySelector("#currency").value = "USD";
        document.querySelector("#description").value = "Conference travel";
        renderFeedback("Manual-review preset loaded.", "muted");
        return;
    }

    document.querySelector("#employee-id").value = "emp-demo-001";
    document.querySelector("#amount").value = "50.00";
    document.querySelector("#currency").value = "USD";
    document.querySelector("#description").value = "Office supplies";
    renderFeedback("Auto-approve preset loaded.", "muted");
}

async function refreshExpenses(preserveSelection = true, explicitSelection = null) {
    try {
        const response = await fetch("/expenses", { cache: "no-store" });
        if (!response.ok) {
            const problem = await safeProblem(response);
            throw new Error(extractProblemDetails(problem) || "Live expense data is unavailable.");
        }

        const expenses = await response.json();
        state.expenses = [...expenses].sort((left, right) =>
            new Date(right.submittedAtUtc) - new Date(left.submittedAtUtc));

        renderConnectionState(true);
        renderStats(state.expenses);
        renderHistory(state.expenses);

        const nextSelection = explicitSelection
            ?? (preserveSelection ? state.selectedExpenseId : null)
            ?? state.expenses[0]?.expenseId
            ?? null;

        if (nextSelection) {
            await selectExpense(nextSelection);
        } else {
            state.selectedExpenseId = null;
            state.selectedExpense = null;
            state.selectedWorkflow = null;
            renderDetail(null);
            renderWorkflow(null, null);
        }
    } catch (error) {
        renderConnectionState(false, error.message);
        renderHistory(state.expenses);
        if (!state.expenses.length) {
            renderDetail(null);
            renderWorkflow(null, error.message);
        }
    }
}

async function selectExpense(expenseId) {
    state.selectedExpenseId = expenseId;
    renderHistory(state.expenses);

    try {
        const [expenseResponse, workflowResponse] = await Promise.all([
            fetch(`/expenses/${encodeURIComponent(expenseId)}`, { cache: "no-store" }),
            fetch(`/expenses/${encodeURIComponent(expenseId)}/workflow`, { cache: "no-store" })
        ]);

        if (!expenseResponse.ok) {
            const problem = await safeProblem(expenseResponse);
            throw new Error(extractProblemDetails(problem) || "The selected expense is no longer available.");
        }

        state.selectedExpense = await expenseResponse.json();
        state.selectedWorkflow = workflowResponse.ok
            ? await workflowResponse.json()
            : workflowResponse.status === 404
                ? null
                : extractProblemDetails(await safeProblem(workflowResponse));
        renderDetail(state.selectedExpense);
        renderWorkflow(state.selectedExpense, state.selectedWorkflow);
        renderHistory(state.expenses);
    } catch (error) {
        renderDetail(null, error.message);
        renderWorkflow(null, error.message);
    }
}

function renderStats(expenses) {
    const totals = {
        total: expenses.length,
        submitted: expenses.filter((expense) => expense.status === "Submitted").length,
        approved: expenses.filter((expense) => expense.status === "Approved").length,
        manual: expenses.filter((expense) => expense.status === "ManualReviewRequested").length,
        reimbursed: expenses.filter((expense) => expense.status === "Reimbursed").length
    };

    const cards = [
        { label: "Total expenses", value: totals.total },
        { label: "Awaiting workflow", value: totals.submitted },
        { label: "Approved", value: totals.approved },
        { label: "Manual review / reimbursed", value: totals.manual + totals.reimbursed }
    ];

    elements.stats.innerHTML = cards.map((card) => `
        <article class="stat-card">
            <div class="label">${escapeHtml(card.label)}</div>
            <div class="value">${card.value}</div>
        </article>
    `).join("");
}

function renderHistory(expenses) {
    if (!expenses.length) {
        elements.history.innerHTML = emptyState(
            "No expenses yet",
            "Submit a claim to turn this board into a live walkthrough.",
            true);
        return;
    }

    elements.history.innerHTML = expenses.map((expense) => {
        const isSelected = expense.expenseId === state.selectedExpenseId;
        return `
            <button class="history-item ${isSelected ? "is-selected" : ""}" type="button" data-expense-id="${escapeHtml(expense.expenseId)}">
                <div class="history-item__top">
                    <div>
                        <h3>${escapeHtml(expense.description)}</h3>
                        <p>${escapeHtml(expense.employeeId)} · ${formatCurrency(expense.amount, expense.currency)}</p>
                    </div>
                    ${renderBadge(expense.status)}
                </div>
                <div class="trace-grid">
                    <div class="trace-item">
                        <strong>Expense ID</strong>
                        <span>${escapeHtml(expense.expenseId)}</span>
                    </div>
                    <div class="trace-item">
                        <strong>Submitted</strong>
                        <span>${formatDate(expense.submittedAtUtc)}</span>
                    </div>
                </div>
            </button>
        `;
    }).join("");

    elements.history.querySelectorAll("[data-expense-id]").forEach((button) => {
        button.addEventListener("click", () => selectExpense(button.getAttribute("data-expense-id")));
    });
}

function renderDetail(expense, errorMessage = "") {
    if (!expense) {
        elements.detail.innerHTML = emptyState(
            "Choose an expense",
            errorMessage || "The right-hand side comes alive once a record exists.",
            false);
        return;
    }

    const summary = describeExpense(expense);
    const steps = buildTimeline(expense, state.selectedWorkflow);

    elements.detail.innerHTML = `
        <div class="detail-card">
            <div>
                <h3>${escapeHtml(expense.description)}</h3>
                <p class="meta-note">${escapeHtml(summary)}</p>
            </div>
            <div class="detail-grid">
                <div class="detail-row">
                    <strong>Amount</strong>
                    <span>${formatCurrency(expense.amount, expense.currency)}</span>
                </div>
                <div class="detail-row">
                    <strong>Status</strong>
                    <span>${renderBadge(expense.status)}</span>
                </div>
                <div class="detail-row">
                    <strong>Employee</strong>
                    <span>${escapeHtml(expense.employeeId)}</span>
                </div>
                <div class="detail-row">
                    <strong>Last updated</strong>
                    <span>${formatDate(expense.lastUpdatedAtUtc)}</span>
                </div>
            </div>
            <div class="trace-grid">
                <div class="trace-item">
                    <strong>Expense ID</strong>
                    <span>${escapeHtml(expense.expenseId)}</span>
                </div>
                <div class="trace-item">
                    <strong>Correlation ID</strong>
                    <span>${escapeHtml(expense.correlationId)}</span>
                </div>
            </div>
            <div>
                <strong class="muted">Journey</strong>
                <div class="timeline">
                    ${steps.map((step) => `
                        <div class="timeline-step" data-state="${escapeHtml(step.state)}">
                            <h4>${escapeHtml(step.title)}</h4>
                            <p>${escapeHtml(step.body)}</p>
                        </div>
                    `).join("")}
                </div>
            </div>
        </div>
    `;
}

function renderWorkflow(expense, workflowOrError) {
    if (!expense) {
        elements.workflow.innerHTML = emptyState(
            "Workflow telemetry waits here",
            typeof workflowOrError === "string"
                ? workflowOrError
                : "Submit or select an expense to inspect the orchestrator. Live telemetry appears after expense state and workflow-engine are both reachable through Dapr.",
            false);
        return;
    }

    if (typeof workflowOrError === "string") {
        elements.workflow.innerHTML = emptyState("Workflow unavailable", workflowOrError, false);
        return;
    }

    const workflow = workflowOrError;
    const tone = statusToneMap[workflow?.state] || "muted";

    elements.workflow.innerHTML = `
        <div class="workflow-card">
            <div>
                <h3>${workflow ? escapeHtml(workflow.summary) : "Workflow details are still warming up."}</h3>
                <p class="meta-note">${workflow?.currentStep
                    ? `Current step: ${escapeHtml(workflow.currentStep)}.`
                    : "As soon as the workflow reports progress, this card will explain the step."}</p>
            </div>
            <div class="workflow-metrics">
                <div class="workflow-metric">
                    <strong>Workflow state</strong>
                    <span>${workflow ? renderBadge(workflow.state, tone) : renderBadge("Pending", "muted")}</span>
                </div>
                <div class="workflow-metric">
                    <strong>Decision source</strong>
                    <span>${escapeHtml(workflow?.decisionSource || "Waiting on runtime signal")}</span>
                </div>
                <div class="workflow-metric">
                    <strong>Runtime status</strong>
                    <span>${escapeHtml(workflow?.runtimeStatus || "Pending")}</span>
                </div>
                <div class="workflow-metric">
                    <strong>Notification event</strong>
                    <span>${escapeHtml(workflow?.notificationEventType || "Not emitted yet")}</span>
                </div>
                <div class="workflow-metric">
                    <strong>Workflow instance</strong>
                    <span>${escapeHtml(workflow?.instanceId || expense.correlationId)}</span>
                </div>
                <div class="workflow-metric">
                    <strong>Last runtime update</strong>
                    <span>${workflow?.lastUpdatedAtUtc ? formatDate(workflow.lastUpdatedAtUtc) : "Not available yet"}</span>
                </div>
            </div>
            ${workflow?.failureDetails
                ? `<div class="trace-item"><strong>Failure details</strong><span>${escapeHtml(workflow.failureDetails)}</span></div>`
                : ""}
            ${expense.status === "ManualReviewRequested"
                ? `<div class="approval-actions">
                    <p class="approval-label">This expense is held for manual review. Approve or reject to signal the workflow.</p>
                    <div class="approval-buttons">
                        <button class="button button--approve" type="button" data-action="approve" data-expense-id="${escapeHtml(expense.expenseId)}">Approve</button>
                        <button class="button button--reject" type="button" data-action="reject" data-expense-id="${escapeHtml(expense.expenseId)}">Reject</button>
                    </div>
                    <div id="approval-feedback" class="feedback" role="status" aria-live="polite"></div>
                   </div>`
                : ""}
        </div>
    `;

    elements.workflow.querySelectorAll("[data-action]").forEach((btn) => {
        btn.addEventListener("click", () =>
            handleApproval(btn.getAttribute("data-expense-id"), btn.getAttribute("data-action")));
    });
}

async function handleApproval(expenseId, action) {
    const feedbackEl = document.querySelector("#approval-feedback");
    const buttons = elements.workflow.querySelectorAll("[data-action]");

    buttons.forEach((b) => { b.disabled = true; });
    if (feedbackEl) feedbackEl.textContent = `Sending ${action} signal\u2026`;

    try {
        const response = await fetch(`/expenses/${encodeURIComponent(expenseId)}/${action}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({})
        });

        if (response.ok) {
            if (feedbackEl) feedbackEl.textContent = `${action === "approve" ? "Approved" : "Rejected"} \u2014 refreshing\u2026`;
            await refreshExpenses(false, expenseId);
        } else {
            const problem = await safeProblem(response);
            if (feedbackEl) feedbackEl.textContent = `Failed: ${extractProblemDetails(problem) || response.statusText}`;
            buttons.forEach((b) => { b.disabled = false; });
        }
    } catch (err) {
        if (feedbackEl) feedbackEl.textContent = `Network error: ${err.message}`;
        buttons.forEach((b) => { b.disabled = false; });
    }
}

function buildTimeline(expense, workflow) {
    const steps = [
        {
            title: "Expense captured",
            body: `Submitted by ${expense.employeeId} for ${formatCurrency(expense.amount, expense.currency)}.`,
            state: "complete"
        },
        {
            title: "Workflow review",
            body: workflow?.summary || "The workflow will decide whether the expense auto-approves or waits for manual review.",
            state: expense.status === "Submitted" ? "current" : "complete"
        }
    ];

    if (expense.status === "ManualReviewRequested") {
        steps.push({
            title: "Manual review surfaced",
            body: "This amount crossed the threshold, so the workflow holds instead of pretending it failed.",
            state: "blocked"
        });
    } else if (expense.status === "Reimbursed") {
        steps.push({
            title: "Reimbursement finished",
            body: "The happy path completed end-to-end, including the reimbursement step.",
            state: "complete"
        });
    } else if (expense.status === "Approved") {
        steps.push({
            title: "Approval confirmed",
            body: "The workflow approved the expense and is advancing toward reimbursement.",
            state: "current"
        });
    } else {
        steps.push({
            title: "Outcome pending",
            body: "Keep polling the record to watch the workflow outcome settle in.",
            state: "current"
        });
    }

    return steps;
}

function describeExpense(expense) {
    switch (expense.status) {
        case "ManualReviewRequested":
            return "This one is intentionally held for human review, which keeps the demo honest.";
        case "Reimbursed":
            return "This claim completed the full workflow, all the way through reimbursement.";
        case "Approved":
            return "The claim is approved and moving down the happy path.";
        case "Rejected":
            return "The workflow finished with a rejection.";
        default:
            return "The claim is still moving through the asynchronous workflow.";
    }
}

function renderConnectionState(isHealthy, message = "") {
    elements.connection.dataset.state = isHealthy ? "ok" : "error";
    elements.connection.textContent = isHealthy
        ? "Expense API and Dapr state are reachable. Live polling is active."
        : message || "The expense API is unavailable right now.";
}

function renderFeedback(message, tone) {
    elements.feedback.textContent = message;
    elements.feedback.dataset.tone = tone;
}

function renderBadge(label, explicitTone = "") {
    const tone = explicitTone || statusToneMap[label] || "muted";
    return `<span class="badge" data-tone="${escapeHtml(tone)}">${escapeHtml(label)}</span>`;
}

function formatCurrency(amount, currency = "USD") {
    if (currency === "USD") {
        return currencyFormatter.format(amount);
    }

    return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency
    }).format(amount);
}

function formatDate(value) {
    if (!value) {
        return "—";
    }

    return new Intl.DateTimeFormat("en-US", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "UTC"
    }).format(new Date(value)) + " UTC";
}

function emptyState(title, description, includeShortcut) {
    return `
        <div class="empty-state">
            <h3>${escapeHtml(title)}</h3>
            <p>${escapeHtml(description)}</p>
            ${includeShortcut ? '<a class="button button--ghost" href="#submit-expense">Start with the submit form</a>' : ""}
        </div>
    `;
}

function setSubmitting(isSubmitting) {
    elements.submitButton.disabled = isSubmitting;
    elements.submitButton.textContent = isSubmitting ? "Submitting…" : "Submit expense";
}

function startPolling() {
    stopPolling();

    state.historyTimer = window.setInterval(() => {
        refreshExpenses(true);
    }, 5000);

    state.selectedTimer = window.setInterval(() => {
        if (state.selectedExpenseId) {
            selectExpense(state.selectedExpenseId);
        }
    }, 4000);
}

function stopPolling() {
    if (state.historyTimer) {
        window.clearInterval(state.historyTimer);
    }

    if (state.selectedTimer) {
        window.clearInterval(state.selectedTimer);
    }
}

function extractProblemDetails(problem) {
    if (!problem) {
        return "";
    }

    if (problem.errors) {
        return Object.values(problem.errors).flat().join(" ");
    }

    const detail = typeof problem === "string"
        ? problem
        : problem.detail || problem.title || problem.message || "";

    if (detail.includes("Dapr.DaprException") || detail.includes("Connection refused")) {
        return "Loading and submitting expenses requires the expense-api Dapr sidecar plus the configured statestore. Workflow telemetry also needs workflow-engine to be reachable through Dapr.";
    }

    return detail;
}

async function safeProblem(response) {
    try {
        const text = await response.text();
        if (!text) {
            return null;
        }

        try {
            return JSON.parse(text);
        } catch {
            return { detail: text.trim().split(/\r?\n/, 1)[0] || "" };
        }
    } catch {
        return null;
    }
}

async function hydratePersistedExpense(problem) {
    const expenseId = problem?.expenseId || problem?.expense?.expenseId;
    if (!expenseId) {
        return;
    }

    await selectExpense(expenseId);
}

function escapeHtml(value) {
    return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
}
