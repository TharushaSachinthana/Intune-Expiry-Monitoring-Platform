/**
 * Intune Expiry Monitoring Platform — Dashboard Application
 *
 * Loads monitoring_report.json and renders:
 *  - Overall health status in the header
 *  - Summary count cards (Urgent / Critical / Warning / Healthy)
 *  - Filterable resource cards with days-remaining progress bars
 *  - Detail modal on card click
 *
 * Data flow:
 *   monitoring_report.json (PowerShell export)
 *       ↓
 *   fetch() → parse JSON
 *       ↓
 *   renderSummary() → renderResourceCards()
 *       ↓
 *   Filter buttons → filterCards()
 *       ↓
 *   Card click → openModal()
 */

'use strict';

// ─── CONSTANTS ──────────────────────────────────────────────────────────────
const REPORT_PATH = './data/monitoring_report.json';

const STATE_CONFIG = {
    URGENT:   { cls: 'urgent',   label: 'Urgent',   icon: '🔴' },
    CRITICAL: { cls: 'critical', label: 'Critical',  icon: '🟠' },
    WARNING:  { cls: 'warning',  label: 'Warning',   icon: '🟡' },
    HEALTHY:  { cls: 'healthy',  label: 'Healthy',   icon: '🟢' },
    EXPIRED:  { cls: 'urgent',   label: 'Expired',   icon: '💀' },
    UNKNOWN:  { cls: 'warning',  label: 'Unknown',   icon: '⚪' },
};

const RESOURCE_TYPE_LABELS = {
    APNsCertificate : 'APNs Certificate',
    DEPToken        : 'DEP / ABM Token',
    VPPToken        : 'VPP Token',
    EnrollmentToken : 'Enrollment Token',
};

// ─── STATE ───────────────────────────────────────────────────────────────────
let allResources = [];
let activeFilter = 'all';

// ─── INIT ────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    loadReport();
    setupFilterButtons();
    setupModal();
});

// ─── DATA LOADING ─────────────────────────────────────────────────────────────
async function loadReport() {
    try {
        const res    = await fetch(REPORT_PATH + '?_=' + Date.now());
        if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
        const report = await res.json();

        allResources = report.resources || [];
        renderHeader(report);
        renderSummary(report.summary);
        renderResourceCards(allResources);
        updateLastUpdated(report.generatedAt);
    }
    catch (err) {
        console.error('[Dashboard] Failed to load report:', err);
        showLoadError(err.message);
    }
}

// ─── HEADER ───────────────────────────────────────────────────────────────────
function renderHeader(report) {
    const overallHealth = report.summary?.OverallHealth || 'UNKNOWN';
    const cfg           = STATE_CONFIG[overallHealth] || STATE_CONFIG.UNKNOWN;

    const pill = document.getElementById('overall-status-pill');
    const dot  = document.getElementById('status-dot');
    const text = document.getElementById('overall-status-text');

    if (dot)  { dot.className = `status-dot ${cfg.cls}`; }
    if (text) { text.textContent = `${cfg.icon}  Overall: ${cfg.label}`; }

    // Update hero section background accent color based on overall state
    const hero = document.getElementById('hero-section');
    if (hero && overallHealth !== 'HEALTHY') {
        const colors = { URGENT: '215,58,73', CRITICAL: '227,98,9', WARNING: '240,173,78' };
        const rgb = colors[overallHealth];
        if (rgb) {
            hero.style.borderColor = `rgba(${rgb},0.4)`;
        }
    }
}

// ─── SUMMARY CARDS ───────────────────────────────────────────────────────────
function renderSummary(summary) {
    if (!summary) return;

    const set = (id, val) => {
        const el = document.getElementById(id);
        if (el) el.textContent = val ?? '0';
    };

    set('count-urgent',   summary.UrgentCount);
    set('count-critical', summary.CriticalCount);
    set('count-warning',  summary.WarningCount);
    set('count-healthy',  summary.HealthyCount);

    // Animate counts
    animateCount('count-urgent',   summary.UrgentCount   || 0);
    animateCount('count-critical', summary.CriticalCount || 0);
    animateCount('count-warning',  summary.WarningCount  || 0);
    animateCount('count-healthy',  summary.HealthyCount  || 0);
}

function animateCount(elementId, targetValue) {
    const el = document.getElementById(elementId);
    if (!el) return;

    const duration = 600;
    const start    = performance.now();
    const startVal = 0;

    function update(now) {
        const elapsed  = now - start;
        const progress = Math.min(elapsed / duration, 1);
        const eased    = 1 - Math.pow(1 - progress, 3); // ease-out cubic
        el.textContent = Math.round(startVal + (targetValue - startVal) * eased);
        if (progress < 1) requestAnimationFrame(update);
    }

    requestAnimationFrame(update);
}

// ─── RESOURCE CARDS ───────────────────────────────────────────────────────────
function renderResourceCards(resources) {
    const grid    = document.getElementById('resource-grid');
    const spinner = document.getElementById('loading-spinner');

    if (spinner) spinner.remove();
    if (!grid) return;

    // Clear existing cards
    grid.querySelectorAll('.resource-card').forEach(c => c.remove());

    if (!resources || resources.length === 0) {
        grid.innerHTML = '<div class="loading-spinner"><span>No resources found in monitoring report.</span></div>';
        return;
    }

    resources.forEach((resource, index) => {
        const card = buildResourceCard(resource, index);
        grid.appendChild(card);
    });
}

function buildResourceCard(resource, index) {
    const state  = resource.HealthState || 'UNKNOWN';
    const cfg    = STATE_CONFIG[state] || STATE_CONFIG.UNKNOWN;
    const days   = resource.DaysRemaining;
    const pct    = resource.ExpirationPercent ?? 50;
    const expiry = resource.ExpirationDate ? formatDate(resource.ExpirationDate) : 'Unknown';
    const typeLabel = RESOURCE_TYPE_LABELS[resource.ResourceType] || resource.ResourceType;

    const card = document.createElement('div');
    card.className   = 'resource-card';
    card.dataset.state  = state;
    card.dataset.index  = index;
    card.style.animationDelay = `${index * 60}ms`;
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.setAttribute('aria-label', `${resource.DisplayName}: ${cfg.label}`);

    // Days display
    const daysDisplay = resource.IsExpired
        ? `<span class="days-number" style="color:var(--expired)">EXP</span>`
        : `<span class="days-number">${days}</span><span class="days-unit">days remaining</span>`;

    // Progress bar (percentage of lifetime remaining, capped 0-100)
    const progressWidth = Math.max(0, Math.min(100, pct));

    card.innerHTML = `
        <div class="card-header">
            <div>
                <div class="card-type">${escapeHtml(typeLabel)}</div>
                <div class="card-name">${escapeHtml(resource.DisplayName)}</div>
            </div>
            <div class="card-badge ${cfg.cls}">${cfg.icon} ${cfg.label}</div>
        </div>

        <div class="card-days">
            ${daysDisplay}
        </div>

        <div class="card-progress">
            <div class="progress-label">
                <span>Lifetime remaining</span>
                <span>${Math.round(progressWidth)}%</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: 0%" data-target="${progressWidth}"></div>
            </div>
        </div>

        <div class="card-footer">
            <div class="card-expiry">
                <span class="card-expiry-label">Expires</span>
                <span class="card-expiry-date">${expiry}</span>
            </div>
            <div class="card-action-icon">→</div>
        </div>
    `;

    // Click handler
    card.addEventListener('click',   () => openModal(resource));
    card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') openModal(resource); });

    // Animate progress bar after paint
    requestAnimationFrame(() => {
        setTimeout(() => {
            const fill = card.querySelector('.progress-fill');
            if (fill) fill.style.width = fill.dataset.target + '%';
        }, 100 + index * 40);
    });

    return card;
}

// ─── FILTER BUTTONS ───────────────────────────────────────────────────────────
function setupFilterButtons() {
    const buttons = document.querySelectorAll('.filter-btn');
    buttons.forEach(btn => {
        btn.addEventListener('click', () => {
            buttons.forEach(b => { b.classList.remove('active'); b.setAttribute('aria-pressed', 'false'); });
            btn.classList.add('active');
            btn.setAttribute('aria-pressed', 'true');
            activeFilter = btn.dataset.filter;
            filterCards(activeFilter);
        });
    });
}

function filterCards(filter) {
    const cards = document.querySelectorAll('.resource-card');
    cards.forEach(card => {
        const show = filter === 'all' || card.dataset.state === filter;
        card.style.display = show ? '' : 'none';
    });
}

// ─── MODAL ────────────────────────────────────────────────────────────────────
function setupModal() {
    const overlay = document.getElementById('modal-overlay');
    const closeBtn = document.getElementById('modal-close');

    if (closeBtn) closeBtn.addEventListener('click', closeModal);
    if (overlay)  overlay.addEventListener('click', (e) => {
        if (e.target === overlay) closeModal();
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeModal();
    });
}

function openModal(resource) {
    const state   = resource.HealthState || 'UNKNOWN';
    const cfg     = STATE_CONFIG[state] || STATE_CONFIG.UNKNOWN;
    const expiry  = resource.ExpirationDate ? formatDate(resource.ExpirationDate) : 'Unknown';
    const typeLabel = RESOURCE_TYPE_LABELS[resource.ResourceType] || resource.ResourceType;

    document.getElementById('modal-icon').textContent  = cfg.icon;
    document.getElementById('modal-state').textContent = typeLabel;
    document.getElementById('modal-title').textContent = resource.DisplayName;

    const rows = [
        ['Health State',       `<span style="color:${resource.HealthStateColor}">${cfg.label}</span>`],
        ['Days Remaining',     resource.IsExpired ? '<span style="color:var(--urgent)">Expired</span>' : `${resource.DaysRemaining} days`],
        ['Expiration Date',    expiry],
        ['Renewal Window',     resource.RenewalWindowDays ? `${resource.RenewalWindowDays} days` : '—'],
        ['In Renewal Window',  resource.IsInRenewalWindow ? '⚡ Yes' : 'No'],
        ['Action Required',    resource.ActionRequired     ? '⚡ Yes' : 'No'],
        ['Trend',              resource.TrendDirection || '—'],
        ['Alert Channels',     (resource.AlertChannels || []).join(', ') || 'None'],
    ];

    const rowsHtml = rows.map(([label, value]) => `
        <div class="modal-row">
            <span class="modal-row-label">${escapeHtml(label)}</span>
            <span class="modal-row-value">${value}</span>
        </div>
    `).join('');

    document.getElementById('modal-body').innerHTML = `
        ${rowsHtml}
        <div class="modal-action-box ${cfg.cls}">
            ${escapeHtml(resource.Description || '')}
        </div>
        <a href="https://intune.microsoft.com" class="modal-cta" target="_blank" rel="noopener">
            Open Intune Admin Center →
        </a>
    `;

    document.getElementById('modal-overlay').classList.add('open');
    document.getElementById('modal-close').focus();
}

function closeModal() {
    document.getElementById('modal-overlay').classList.remove('open');
}

// ─── LAST UPDATED ─────────────────────────────────────────────────────────────
function updateLastUpdated(iso) {
    const el = document.getElementById('last-updated');
    if (!el || !iso) return;
    try {
        const d = new Date(iso);
        el.textContent = `Last updated: ${d.toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' })} UTC`;
    }
    catch (_) {
        el.textContent = `Last updated: ${iso}`;
    }
}

// ─── ERROR STATE ──────────────────────────────────────────────────────────────
function showLoadError(message) {
    const grid = document.getElementById('resource-grid');
    const spinner = document.getElementById('loading-spinner');
    if (spinner) spinner.remove();
    if (grid) {
        grid.innerHTML = `
            <div class="loading-spinner">
                <div style="font-size:32px">⚠️</div>
                <span>Failed to load monitoring report</span>
                <span style="font-size:12px; color:var(--text-muted)">${escapeHtml(message)}</span>
                <span style="font-size:11px; color:var(--text-muted)">Run Invoke-MonitoringRun.ps1 to generate report data.</span>
            </div>
        `;
    }

    const dot  = document.getElementById('status-dot');
    const text = document.getElementById('overall-status-text');
    if (dot)  dot.className = 'status-dot warning';
    if (text) text.textContent = 'Unable to load report';
}

// ─── UTILITIES ────────────────────────────────────────────────────────────────
function formatDate(iso) {
    try {
        const d = new Date(iso);
        return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    }
    catch (_) { return iso; }
}

function escapeHtml(str) {
    if (typeof str !== 'string') return String(str ?? '');
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
