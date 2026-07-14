/* ==========================================================================
   SERENUT OS V2 - ADMIN DASHBOARD MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';

let dashboardCharts = {};

export async function loadDashboard() {
  try {
    const data = await apiFetch('/admin/dashboard');

    // Populate operational stats metrics
    document.getElementById('stat-companies').innerText = data.metrics.activeCompanies || 0;
    document.getElementById('stat-devices').innerText = data.metrics.activePos || 0;
    document.getElementById('stat-licenses').innerText = data.metrics.activeLicenses || 0;
    document.getElementById('stat-expiring').innerText = data.metrics.expiringLicenses || 0;

    // Launch Operations Center metrics
    document.getElementById('ops-new-signups').innerText = '—';
    document.getElementById('ops-active-trials').innerText = data.metrics.trialUsers || 0;
    document.getElementById('ops-expiring-trials').innerText = data.metrics.expiringLicenses || 0;
    document.getElementById('ops-payments-today').innerText = '—';
    document.getElementById('ops-failed-payments').innerText = '—';
    document.getElementById('ops-open-tickets').innerText = '—';
    document.getElementById('ops-latest-ota').innerText = '—';

    // Update telemetry metrics health bars
    updateHealthBar('cpu', data.system.cpuUsage);
    updateHealthBar('ram', data.system.ramUsage);
    updateHealthBar('disk', data.system.diskUsage);

    // Update health status badges
    updateHealthBadge('db-health-badge', `🐘 PostgreSQL: ${data.system.database === 'up' ? 'Aktif' : 'Bağlantı Kesik'}`, data.system.database);
    updateHealthBadge('redis-health-badge', `🔴 Redis Cache: ${data.system.redis === 'up' ? 'Aktif' : 'Bağlantı Kesik'}`, data.system.redis);

    // Initialize/Redraw analytical Chart.js graphs
    await loadDashboardCharts();

  } catch (err) {
    console.error('Failed to load admin dashboard indices:', err);
  }
}

function updateHealthBar(prefix, percentage) {
  const bar = document.getElementById(`${prefix}-bar`);
  const text = document.getElementById(`${prefix}-text`);
  if (!bar || !text) return;

  const value = Math.min(100, Math.max(0, Number(percentage) || 0));
  bar.style.width = `${value}%`;
  text.innerText = `${value}%`;

  // Apply visual colors classes based on usage values
  bar.className = 'health-bar-fill';
  if (value > 85) {
    bar.classList.add('danger');
  } else if (value > 65) {
    bar.classList.add('warning');
  } else {
    bar.classList.add('normal');
  }
}

function updateHealthBadge(elementId, labelText, status) {
  const badge = document.getElementById(elementId);
  if (!badge) return;

  badge.innerText = labelText;
  badge.className = `badge ${status === 'up' ? 'badge-active' : 'badge-danger'}`;
}

async function loadDashboardCharts() {
  try {
    const data = await apiFetch('/admin/analytics');

    // Destroy existing charts to prevent rendering overlapping bugs
    if (dashboardCharts.sales) dashboardCharts.sales.destroy();
    if (dashboardCharts.licenses) dashboardCharts.licenses.destroy();

    // Chart.js requires global CDN inclusion in html shell
    if (typeof Chart === 'undefined') {
      console.warn('Chart.js library is not available globally.');
      return;
    }

    // 1. Sales Trend Graph
    const salesCtx = document.getElementById('salesChart')?.getContext('2d');
    if (salesCtx) {
      dashboardCharts.sales = new Chart(salesCtx, {
        type: 'line',
        data: {
          labels: data.salesTrend.map(d => d.date),
          datasets: [{
            label: 'Günlük Ciro (TRY)',
            data: data.salesTrend.map(d => d.amount),
            borderColor: '#00f0ff',
            backgroundColor: 'rgba(0, 240, 255, 0.08)',
            fill: true,
            tension: 0.3,
            borderWidth: 2
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: {
            x: { grid: { color: 'rgba(255, 255, 255, 0.03)' }, ticks: { color: '#94a3b8' } },
            y: { grid: { color: 'rgba(255, 255, 255, 0.03)' }, ticks: { color: '#94a3b8' } }
          }
        }
      });
    }

    // 2. License Distribution Graph
    const licCtx = document.getElementById('licenseDistChart')?.getContext('2d');
    if (licCtx) {
      const distData = data.licenseDistribution || [];
      dashboardCharts.licenses = new Chart(licCtx, {
        type: 'doughnut',
        data: {
          labels: distData.map(d => String(d.tier).toUpperCase()),
          datasets: [{
            data: distData.map(d => parseInt(d.count, 10)),
            backgroundColor: ['#00f0ff', '#bd00ff', '#10b981', '#f59e0b'],
            borderWidth: 0
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: 'bottom',
              labels: { color: '#cbd5e1', font: { size: 10 } }
            }
          }
        }
      });
    }

  } catch (err) {
    console.error('Failed to render dashboard Chart.js data:', err);
  }
}
