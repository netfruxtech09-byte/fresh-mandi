const API_BASE = '/api/v1/admin';
const CATALOG_BASE = '/api/v1/catalog';

const views = [
  'dashboardView',
  'ordersView',
  'productsView',
  'procurementView',
  'inventoryView',
  'packingView',
  'processingView',
  'deliveryView',
  'accountingView',
  'customersView',
  'routesView',
  'reportsView',
  'notificationsView',
  'settingsView',
  'productFormView',
];

const viewTitles = {
  dashboardView: 'Dashboard',
  ordersView: 'Orders',
  productsView: 'Products',
  procurementView: 'Purchase Planning',
  inventoryView: 'Inventory',
  packingView: 'Packing',
  processingView: 'Processing Staff',
  deliveryView: 'Delivery',
  accountingView: 'Payments & Accounting',
  customersView: 'Customers',
  routesView: 'Routes',
  reportsView: 'Reports',
  notificationsView: 'Notifications',
  settingsView: 'Settings',
  productFormView: 'Product Form',
};

const statusMap = {
  PENDING_PAYMENT: 'PLACED',
  CONFIRMED: 'PRINTED',
  PLACED: 'PLACED',
  PRINTED: 'PRINTED',
  PACKED: 'PACKED',
  OUT_FOR_DELIVERY: 'OUT_FOR_DELIVERY',
  DELIVERED: 'DELIVERED',
  CANCELLED: 'CANCELLED',
};

const loginView = document.getElementById('loginView');
const appView = document.getElementById('appView');
const loginForm = document.getElementById('loginForm');
const loginError = document.getElementById('loginError');
const adminMeta = document.getElementById('adminMeta');
const viewTitle = document.getElementById('viewTitle');
const todayLabel = document.getElementById('todayLabel');

const navButtons = [...document.querySelectorAll('.nav-btn')];
const kpis = document.getElementById('kpis');
const productsBody = document.getElementById('productsBody');
const ordersBody = document.getElementById('ordersBody');
const sectorTabs = document.getElementById('sectorTabs');
const buildingTabs = document.getElementById('buildingTabs');
const routeTabs = document.getElementById('routeTabs');

const sectorGraph = document.getElementById('sectorGraph');
const hourlyGraph = document.getElementById('hourlyGraph');
const topItemsGraph = document.getElementById('topItemsGraph');
const wastageGraph = document.getElementById('wastageGraph');
const revenueGraph = document.getElementById('revenueGraph');

const procurementSummary = document.getElementById('procurementSummary');
const inventorySummary = document.getElementById('inventorySummary');
const packingSummary = document.getElementById('packingSummary');
const processingStaffForm = document.getElementById('processingStaffForm');
const processingStaffName = document.getElementById('processingStaffName');
const processingStaffPhone = document.getElementById('processingStaffPhone');
const processingStaffCode = document.getElementById('processingStaffCode');
const processingStaffMsg = document.getElementById('processingStaffMsg');
const processingStaffTable = document.getElementById('processingStaffTable');
const deliverySummary = document.getElementById('deliverySummary');
const deliveryExecutiveForm = document.getElementById('deliveryExecutiveForm');
const deliveryAssignmentForm = document.getElementById('deliveryAssignmentForm');
const deliveryExecName = document.getElementById('deliveryExecName');
const deliveryExecPhone = document.getElementById('deliveryExecPhone');
const deliveryExecCode = document.getElementById('deliveryExecCode');
const deliveryBusinessDate = document.getElementById('deliveryBusinessDate');
const deliveryRouteId = document.getElementById('deliveryRouteId');
const deliveryExecutiveId = document.getElementById('deliveryExecutiveId');
const deliveryModuleMsg = document.getElementById('deliveryModuleMsg');
const deliveryExecutivesTable = document.getElementById('deliveryExecutivesTable');
const deliveryAssignmentsTable = document.getElementById('deliveryAssignmentsTable');
const deliveryMonitorSector = document.getElementById('deliveryMonitorSector');
const deliveryMonitorRoute = document.getElementById('deliveryMonitorRoute');
const refreshDeliveryMonitor = document.getElementById('refreshDeliveryMonitor');
const deliveryRouteMonitorTable = document.getElementById('deliveryRouteMonitorTable');
const accountingSummary = document.getElementById('accountingSummary');
const customersSummary = document.getElementById('customersSummary');
const routesSummary = document.getElementById('routesSummary');
const reportsSummary = document.getElementById('reportsSummary');
const notificationsSummary = document.getElementById('notificationsSummary');
const routeForm = document.getElementById('routeForm');
const routeSectorId = document.getElementById('routeSectorId');

const productForm = document.getElementById('productForm');
const productFormMsg = document.getElementById('productFormMsg');
const productFormTitle = document.getElementById('productFormTitle');
const saveProductBtn = document.getElementById('saveProductBtn');
const settingsForm = document.getElementById('settingsForm');
const settingsMsg = document.getElementById('settingsMsg');
const globalLoader = document.getElementById('globalLoader');
const toast = document.getElementById('toast');

const productSearch = document.getElementById('productSearch');
const orderStatusFilter = document.getElementById('orderStatusFilter');
const filterDate = document.getElementById('filterDate');
const filterSector = document.getElementById('filterSector');
const filterRoute = document.getElementById('filterRoute');
const categoryId = document.getElementById('categoryId');
const productImageFile = document.getElementById('productImageFile');
const productImageInput = document.getElementById('productImage');
const productImagePreview = document.getElementById('productImagePreview');
const productImageMeta = document.getElementById('productImageMeta');

let token = localStorage.getItem('admin_token') || '';
let meState = null;
let categories = [];
let productsState = [];
let ordersState = [];
let routesState = [];
let deliveryMonitorRowsState = [];
let deliveryMonitorLastKey = '';
let toastTimer;
let pendingRequests = 0;

const orderTreeSelection = {
  sector: 'ALL',
  building: 'ALL',
  route: 'ALL',
};

function localDateString(d = new Date()) {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function normalizeBusinessDate(value) {
  if (!value) return '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '';
  return parsed.toISOString().slice(0, 10);
}

async function req(path, options = {}) {
  pendingRequests += 1;
  globalLoader?.classList.remove('hidden');
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (token) headers.Authorization = `Bearer ${token}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 20000);

  try {
    const res = await fetch(path, {
      ...options,
      headers,
      cache: 'no-store',
      signal: options.signal || controller.signal,
    });

    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body?.message || `Request failed (${res.status})`);
    return body?.data;
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw new Error('Server is taking too long to respond. Please retry.');
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
    pendingRequests = Math.max(0, pendingRequests - 1);
    if (pendingRequests === 0) {
      globalLoader?.classList.add('hidden');
    }
  }
}

function showToast(message, type = 'success') {
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.remove('hidden', 'success', 'error');
  toast.classList.add(type);
  toastTimer = setTimeout(() => toast.classList.add('hidden'), 2500);
}

function can(permissionCode) {
  const perms = meState?.permissions || [];
  return perms.includes('*') || perms.includes(permissionCode);
}

function applyRoleVisibility() {
  navButtons.forEach((btn) => {
    const required = btn.dataset.perm;
    btn.classList.toggle('hidden', required && !can(required));
  });

  document.getElementById('openCreateProduct').classList.toggle('hidden', !can('products:write'));
  document.getElementById('nightReminderBtn').classList.toggle('hidden', !can('orders:freeze'));
  if (routeForm) routeForm.classList.toggle('hidden', !can('routes:write'));
  if (processingStaffForm) processingStaffForm.classList.toggle('hidden', !can('delivery:write'));
  if (deliveryExecutiveForm) deliveryExecutiveForm.classList.toggle('hidden', !can('delivery:write'));
  if (deliveryAssignmentForm) deliveryAssignmentForm.classList.toggle('hidden', !can('delivery:write'));
  const settingsSubmit = settingsForm?.querySelector('button[type="submit"]');
  if (settingsSubmit) settingsSubmit.classList.toggle('hidden', !can('settings:write'));
}

function toAbsoluteAsset(url) {
  if (!url) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('/')) return `${window.location.origin}${url}`;
  return url;
}

function updateImagePreview(url) {
  const finalUrl = toAbsoluteAsset(url);
  if (!finalUrl) {
    productImagePreview.classList.add('hidden');
    productImagePreview.src = '';
    productImageMeta.textContent = 'No image uploaded yet.';
    return;
  }
  productImagePreview.src = finalUrl;
  productImagePreview.classList.remove('hidden');
  productImageMeta.textContent = url;
}

function showLogin() {
  loginView.classList.remove('hidden');
  appView.classList.add('hidden');
}

function showApp() {
  loginView.classList.add('hidden');
  appView.classList.remove('hidden');
}

function activateNavButton(targetView) {
  navButtons.forEach((b) => b.classList.toggle('active', b.dataset.view === targetView));
}

function showView(targetView) {
  views.forEach((id) => {
    document.getElementById(id).classList.toggle('hidden', id !== targetView);
  });
  viewTitle.textContent = viewTitles[targetView] || 'Admin';
  if (targetView !== 'productFormView') activateNavButton(targetView);
}

function productRouteQuery() {
  const q = productSearch.value.trim();
  return q ? `?q=${encodeURIComponent(q)}` : '';
}

function normalizeStatus(s) {
  return statusMap[s] || 'PLACED';
}

function statusPill(status) {
  const label = normalizeStatus(status).replaceAll('_', ' ');
  const code = normalizeStatus(status);
  return `<span class="status-pill status-${code}">${label}</span>`;
}

function itemSummary(o) {
  if (typeof o.item_count === 'number' && o.item_count > 0) {
    return `${o.item_count} items`;
  }
  if (o.items_summary) return o.items_summary;
  return '-';
}

function renderSimpleList(target, rows, fallbackText) {
  if (!rows.length) {
    target.innerHTML = `<div class="mini-row"><span>${fallbackText}</span><strong>-</strong></div>`;
    return;
  }
  target.innerHTML = rows
    .map((r) => `<div class="mini-row"><span>${r.label}</span><strong>${r.value}</strong></div>`)
    .join('');
}

function fmtNum(value, decimals = 0) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n.toFixed(decimals) : '0';
}

function renderSummaryCards(items) {
  return `
    <div class="summary-grid">
      ${items
        .map(
          (it) => `
            <div class="summary-item">
              <div class="k">${it.k}</div>
              <div class="v">${it.v}</div>
            </div>`,
        )
        .join('')}
    </div>
  `;
}

function renderInlineTable(headers, rows) {
  if (!rows.length) return '<div class="muted" style="margin-top:8px;">No records yet.</div>';
  return `
    <table class="inline-table">
      <thead><tr>${headers.map((h) => `<th>${h}</th>`).join('')}</tr></thead>
      <tbody>
        ${rows.map((r) => `<tr>${r.map((c) => `<td>${c ?? '-'}</td>`).join('')}</tr>`).join('')}
      </tbody>
    </table>
  `;
}

function buildOrderTree(rows) {
  const tree = {};
  rows.forEach((o) => {
    const sector = o.sector_name || o.sector_code || (o.sector_id ? `Sector ${o.sector_id}` : 'Unassigned Sector');
    const building = o.building_name || o.building_code || (o.building_id ? `Building ${o.building_id}` : 'Unassigned Building');
    const route = o.route_code || (o.route_id ? `Route ${o.route_id}` : 'Unassigned Route');

    if (!tree[sector]) tree[sector] = {};
    if (!tree[sector][building]) tree[sector][building] = {};
    if (!tree[sector][building][route]) tree[sector][building][route] = [];

    tree[sector][building][route].push(o);
  });

  return tree;
}

function renderTabRow(target, values, activeValue, onPick) {
  target.innerHTML = values
    .map((value) => `<button class="chip ${value === activeValue ? 'active' : ''}" data-chip="${encodeURIComponent(value)}">${value}</button>`)
    .join('');

  target.querySelectorAll('[data-chip]').forEach((btn) => {
    btn.addEventListener('click', () => onPick(decodeURIComponent(btn.dataset.chip)));
  });
}

function applyOrderFilters(rows) {
  const dateVal = filterDate.value;
  const selectedStatus = orderStatusFilter.value;
  const selectedSector = filterSector.value;
  const selectedRoute = filterRoute.value;

  return rows.filter((o) => {
    if (selectedStatus && normalizeStatus(o.status) !== selectedStatus) return false;

    const sectorName = o.sector_name || o.sector_code || (o.sector_id ? `Sector ${o.sector_id}` : 'Unassigned Sector');
    const routeName = o.route_code || (o.route_id ? `Route ${o.route_id}` : 'Unassigned Route');

    if (selectedSector && sectorName !== selectedSector) return false;
    if (selectedRoute && routeName !== selectedRoute) return false;

    if (dateVal) {
      const dt = new Date(o.created_at || 0);
      if (!Number.isNaN(dt.getTime())) {
        const day = dt.toISOString().slice(0, 10);
        if (day !== dateVal) return false;
      }
    }

    return true;
  });
}

function renderOrders() {
  const filtered = applyOrderFilters(ordersState);
  const tree = buildOrderTree(filtered);
  const sectors = ['ALL', ...Object.keys(tree)];

  if (!sectors.includes(orderTreeSelection.sector)) orderTreeSelection.sector = 'ALL';
  renderTabRow(sectorTabs, sectors, orderTreeSelection.sector, (sector) => {
    orderTreeSelection.sector = sector;
    orderTreeSelection.building = 'ALL';
    orderTreeSelection.route = 'ALL';
    renderOrders();
  });

  const sectorObj = orderTreeSelection.sector === 'ALL' ? tree : { [orderTreeSelection.sector]: tree[orderTreeSelection.sector] || {} };
  const buildingSet = new Set(['ALL']);
  Object.values(sectorObj).forEach((bObj) => Object.keys(bObj || {}).forEach((b) => buildingSet.add(b)));
  const buildings = [...buildingSet];
  if (!buildings.includes(orderTreeSelection.building)) orderTreeSelection.building = 'ALL';

  renderTabRow(buildingTabs, buildings, orderTreeSelection.building, (building) => {
    orderTreeSelection.building = building;
    orderTreeSelection.route = 'ALL';
    renderOrders();
  });

  const routeSet = new Set(['ALL']);
  Object.values(sectorObj).forEach((bObj) => {
    Object.entries(bObj || {}).forEach(([building, routes]) => {
      if (orderTreeSelection.building === 'ALL' || building === orderTreeSelection.building) {
        Object.keys(routes || {}).forEach((r) => routeSet.add(r));
      }
    });
  });
  const routes = [...routeSet];
  if (!routes.includes(orderTreeSelection.route)) orderTreeSelection.route = 'ALL';

  renderTabRow(routeTabs, routes, orderTreeSelection.route, (route) => {
    orderTreeSelection.route = route;
    renderOrders();
  });

  if (!filtered.length) {
    sectorTabs.innerHTML = '<span class="muted">No sector data for selected filters.</span>';
    buildingTabs.innerHTML = '<span class="muted">No building data for selected filters.</span>';
    routeTabs.innerHTML = '<span class="muted">No route data for selected filters.</span>';
  }

  const displayRows = filtered.filter((o) => {
    const sector = o.sector_name || o.sector_code || (o.sector_id ? `Sector ${o.sector_id}` : 'Unassigned Sector');
    const building = o.building_name || o.building_code || (o.building_id ? `Building ${o.building_id}` : 'Unassigned Building');
    const route = o.route_code || (o.route_id ? `Route ${o.route_id}` : 'Unassigned Route');

    if (orderTreeSelection.sector !== 'ALL' && sector !== orderTreeSelection.sector) return false;
    if (orderTreeSelection.building !== 'ALL' && building !== orderTreeSelection.building) return false;
    if (orderTreeSelection.route !== 'ALL' && route !== orderTreeSelection.route) return false;
    return true;
  });

  ordersBody.innerHTML = displayRows
    .sort((a, b) => Number(a.route_sequence || a.id) - Number(b.route_sequence || b.id))
    .map((o, idx) => {
      const printStatus = o.print_status || normalizeStatus(o.status);
      const packStatus = o.packing_status || normalizeStatus(o.status);
      const delStatus = o.delivery_status || normalizeStatus(o.status);
      const payStatus = o.payment_status || 'PENDING';
      const flat = [o.building_name || o.building_code || '-', o.flat_number || o.line1 || '-'].join(' / ');

      return `
      <tr>
        <td>${o.route_sequence || idx + 1}</td>
        <td>#${o.id}</td>
        <td>${o.user_name || '-'}</td>
        <td>${flat}</td>
        <td>${itemSummary(o)}</td>
        <td>₹${Number(o.total || 0).toFixed(2)}</td>
        <td>${statusPill(printStatus)}</td>
        <td>${statusPill(packStatus)}</td>
        <td>${statusPill(delStatus)}</td>
        <td>${payStatus}</td>
      </tr>`;
    })
    .join('');

  if (!displayRows.length) {
    const selectedDate = filterDate.value || 'today';
    ordersBody.innerHTML = `<tr><td colspan="10">No orders found for ${selectedDate}. Try changing date/status filters or refresh.</td></tr>`;
  }
}

function renderDashboard() {
  const today = localDateString();
  const todayOrders = ordersState.filter((o) => (o.created_at || '').slice(0, 10) === today);

  const totals = {
    totalOrdersToday: todayOrders.length,
    totalRevenue: todayOrders.reduce((acc, o) => acc + Number(o.total || 0), 0),
    ordersPrinted: todayOrders.filter((o) => normalizeStatus(o.print_status || o.status) === 'PRINTED').length,
    ordersPacked: todayOrders.filter((o) => normalizeStatus(o.packing_status || o.status) === 'PACKED').length,
    outForDelivery: todayOrders.filter((o) => normalizeStatus(o.delivery_status || o.status) === 'OUT_FOR_DELIVERY').length,
    delivered: todayOrders.filter((o) => normalizeStatus(o.delivery_status || o.status) === 'DELIVERED').length,
    pendingPayments: todayOrders.filter((o) => (o.payment_status || 'PENDING') === 'PENDING').length,
    purchaseItems: new Set(todayOrders.flatMap((o) => (o.items || []).map((i) => i.product_id))).size,
    stockRemaining: '-',
  };

  const kpiRows = [
    ['Total Orders Today', totals.totalOrdersToday],
    ['Total Revenue', `₹${totals.totalRevenue.toFixed(2)}`],
    ['Orders Printed', totals.ordersPrinted],
    ['Orders Packed', totals.ordersPacked],
    ['Out for Delivery', totals.outForDelivery],
    ['Delivered', totals.delivered],
    ['Pending Payments', totals.pendingPayments],
    ['Total Items to Purchase', totals.purchaseItems],
    ['Stock Remaining', totals.stockRemaining],
  ];

  kpis.innerHTML = kpiRows
    .map(([label, value]) => `<div class="kpi"><div class="label">${label}</div><div class="value">${value}</div></div>`)
    .join('');

  const sectorCount = {};
  const hourly = {};
  const topItems = {};
  const revenueByDay = {};

  ordersState.forEach((o) => {
    const sector = o.sector_name || o.sector_code || (o.sector_id ? `Sector ${o.sector_id}` : 'Unassigned');
    sectorCount[sector] = (sectorCount[sector] || 0) + 1;

    const dt = new Date(o.created_at || 0);
    if (!Number.isNaN(dt.getTime())) {
      const hh = `${String(dt.getHours()).padStart(2, '0')}:00`;
      hourly[hh] = (hourly[hh] || 0) + 1;
      const day = dt.toISOString().slice(0, 10);
      revenueByDay[day] = (revenueByDay[day] || 0) + Number(o.total || 0);
    }

    if (Array.isArray(o.items)) {
      o.items.forEach((it) => {
        const key = it.name || `Item ${it.product_id || ''}`;
        topItems[key] = (topItems[key] || 0) + Number(it.quantity || 0);
      });
    }
  });

  renderSimpleList(
    sectorGraph,
    Object.entries(sectorCount)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6)
      .map(([label, value]) => ({ label, value })),
    'No sector data',
  );

  renderSimpleList(
    hourlyGraph,
    Object.entries(hourly)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([label, value]) => ({ label, value })),
    'No hourly trend',
  );

  renderSimpleList(
    topItemsGraph,
    Object.entries(topItems)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6)
      .map(([label, value]) => ({ label, value })),
    'No item data',
  );

  renderSimpleList(
    wastageGraph,
    [
      { label: 'Configured Wastage (default)', value: '5%' },
      { label: 'Damaged Tracking', value: 'Inventory Module' },
      { label: 'Low Stock Alerts', value: 'Enabled' },
    ],
    'No wastage data',
  );

  renderSimpleList(
    revenueGraph,
    Object.entries(revenueByDay)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .slice(-7)
      .map(([label, value]) => ({ label, value: `₹${value.toFixed(0)}` })),
    'No revenue trend',
  );
}

async function loadProcurementSummary() {
  if (!can('purchase:read')) return;
  const data = await req(`${API_BASE}/modules/procurement/summary`);
  const o = data?.overview || {};
  procurementSummary.innerHTML =
    renderSummaryCards([
      { k: 'Rows (Today)', v: fmtNum(o.rows) },
      { k: 'Total Final Qty', v: fmtNum(o.total_qty, 3) },
      { k: 'Purchased', v: fmtNum(o.purchased_rows) },
    ]) +
    renderInlineTable(
      ['Product', 'Required', 'Wastage %', 'Final Qty', 'Supplier', 'Purchased'],
      (data?.items || []).map((it) => [
        it.name,
        fmtNum(it.required_qty, 3),
        fmtNum(it.wastage_pct, 2),
        fmtNum(it.final_purchase_qty, 3),
        it.supplier_name || '-',
        it.purchased ? 'Yes' : 'No',
      ]),
    );
}

async function loadInventorySummary() {
  if (!can('inventory:read')) return;
  const data = await req(`${API_BASE}/modules/inventory/summary`);
  const o = data?.overview || {};
  inventorySummary.innerHTML =
    renderSummaryCards([
      { k: 'Stock Rows (Today)', v: fmtNum(o.rows) },
      { k: 'Total Remaining', v: fmtNum(o.total_remaining, 3) },
      { k: 'Low Stock Items', v: fmtNum(o.low_stock_items) },
      { k: 'Wastage Qty', v: fmtNum(o.total_wastage, 3) },
    ]) +
    renderInlineTable(
      ['Product', 'Remaining', 'Threshold', 'Warehouse'],
      (data?.low_stock || []).map((it) => [
        it.name,
        fmtNum(it.remaining_qty, 3),
        fmtNum(it.low_stock_threshold, 3),
        it.warehouse_code,
      ]),
    );
}

async function loadPackingSummary() {
  if (!can('packing:read')) return;
  const data = await req(`${API_BASE}/modules/packing/summary`);
  const o = data?.overview || {};
  packingSummary.innerHTML =
    renderSummaryCards([
      { k: 'Packed Logs Today', v: fmtNum(o.packed_logs_today) },
      { k: 'Active Routes', v: fmtNum(o.active_routes) },
      { k: 'Crates Used', v: fmtNum(o.crates_used) },
    ]) +
    renderInlineTable(
      ['Route', 'Packed Orders', 'Crates'],
      (data?.routes || []).map((it) => [it.route_code || '-', fmtNum(it.packed_orders), fmtNum(it.crate_count)]),
    );
}

async function loadProcessingStaff() {
  if (!can('delivery:read')) return;
  const staff = await req(`${API_BASE}/processing/staff`);
  processingStaffTable.innerHTML = renderInlineTable(
    ['Name', 'Phone', 'Code', 'Status', 'Last Login'],
    (staff || []).map((s) => [
      s.name || '-',
      s.phone || '-',
      s.employee_code || '-',
      s.active ? 'Active' : 'Inactive',
      s.last_login_at ? new Date(s.last_login_at).toLocaleString('en-IN') : '-',
    ]),
  );
  processingStaffMsg.textContent = `Loaded ${fmtNum((staff || []).length)} processing staff records.`;
}

async function loadDeliverySummary() {
  if (!can('delivery:read')) return;
  const data = await req(`${API_BASE}/modules/delivery/summary`);
  const o = data?.overview || {};
  deliverySummary.innerHTML =
    renderSummaryCards([
      { k: 'Logs Today', v: fmtNum(o.logs_today) },
      { k: 'Delivered', v: fmtNum(o.delivered) },
      { k: 'Not Available', v: fmtNum(o.not_available) },
      { k: 'Rescheduled', v: fmtNum(o.rescheduled) },
      { k: 'Cancelled', v: fmtNum(o.cancelled) },
    ]) +
    renderInlineTable(
      ['Route', 'Total', 'Delivered'],
      (data?.routes || []).map((it) => [it.route_code || '-', fmtNum(it.total), fmtNum(it.delivered)]),
    );

  const targetDate = deliveryBusinessDate?.value || localDateString();
  const [executives, assignments, routesData] = await Promise.all([
    req(`${API_BASE}/delivery/executives`),
    req(`${API_BASE}/delivery/assignments?business_date=${encodeURIComponent(targetDate)}`),
    can('routes:read') ? req(`${API_BASE}/modules/routes`) : Promise.resolve(null),
  ]);

  const routeRows = routesData?.routes || routesState || [];
  routesState = routeRows;

  const sectorMap = new Map();
  routeRows.forEach((r) => {
    if (!r?.sector_code && !r?.sector_name) return;
    const key = String(r.sector_id ?? `${r.sector_code}-${r.sector_name}`);
    if (!sectorMap.has(key)) {
      sectorMap.set(key, {
        sector_id: r.sector_id,
        sector_code: r.sector_code,
        sector_name: r.sector_name,
      });
    }
  });

  if (deliveryMonitorSector) {
    const selectedSector = deliveryMonitorSector.value;
    deliveryMonitorSector.innerHTML =
      '<option value="">All Sectors</option>' +
      [...sectorMap.values()]
        .map((s) => `<option value="${s.sector_id || ''}">${s.sector_name || s.sector_code || '-'}</option>`)
        .join('');
    if ([...deliveryMonitorSector.options].some((o) => o.value === selectedSector)) {
      deliveryMonitorSector.value = selectedSector;
    }
  }

  const monitorSectorId = Number(deliveryMonitorSector?.value || 0);
  const filteredRoutesForMonitor =
    Number.isFinite(monitorSectorId) && monitorSectorId > 0
      ? routeRows.filter((r) => Number(r.sector_id) === monitorSectorId)
      : routeRows;
  if (deliveryMonitorRoute) {
    const selectedRoute = deliveryMonitorRoute.value;
    deliveryMonitorRoute.innerHTML =
      '<option value="">All Routes</option>' +
      filteredRoutesForMonitor
        .map((r) => `<option value="${r.id}">${r.route_code} (${r.sector_name || r.sector_code || '-'})</option>`)
        .join('');
    if ([...deliveryMonitorRoute.options].some((o) => o.value === selectedRoute)) {
      deliveryMonitorRoute.value = selectedRoute;
    }
  }

  deliveryExecutiveId.innerHTML = (executives || []).length
    ? (executives || [])
      .filter((e) => e.active)
      .map((e) => `<option value="${e.id}">${e.name} (${e.phone})</option>`)
      .join('')
    : '<option value="">No active executive</option>';

  deliveryRouteId.innerHTML = routeRows.length
    ? routeRows.map((r) => `<option value="${r.id}">${r.route_code} (${r.sector_name || r.sector_code})</option>`).join('')
    : '<option value="">No routes</option>';

  deliveryExecutivesTable.innerHTML = renderInlineTable(
    ['Name', 'Phone', 'Code', 'Status', 'Last Login'],
    (executives || []).map((e) => [
      e.name || '-',
      e.phone || '-',
      e.employee_code || '-',
      e.active ? 'Active' : 'Inactive',
      e.last_login_at ? new Date(e.last_login_at).toLocaleString('en-IN') : '-',
    ]),
  );

  deliveryAssignmentsTable.innerHTML = renderInlineTable(
    ['Date', 'Route', 'Sector', 'Executive', 'Status'],
    (assignments || []).map((a) => [
      (a.business_date || '').slice(0, 10),
      a.route_code || '-',
      a.sector_name || a.sector_code || '-',
      `${a.delivery_executive_name || '-'} (${a.delivery_executive_phone || '-'})`,
      (a.status || '-').replaceAll('_', ' '),
    ]),
  );

  try {
    await loadDeliveryRouteMonitor();
  } catch (err) {
    if (deliveryRouteMonitorTable) {
      deliveryRouteMonitorTable.innerHTML = `<div class="muted">Failed to load route monitor: ${err.message || 'Unknown error'}</div>`;
    }
  }
  deliveryModuleMsg.textContent = `Loaded ${fmtNum((executives || []).length)} executives and ${fmtNum((assignments || []).length)} assignments for ${targetDate}.`;
}

async function loadDeliveryRouteMonitor() {
  if (!can('delivery:read')) return;
  if (!deliveryRouteMonitorTable) return;
  const targetDate = deliveryBusinessDate?.value || localDateString();
  const sectorId = Number(deliveryMonitorSector?.value || 0);
  const routeId = Number(deliveryMonitorRoute?.value || 0);

  const qs = new URLSearchParams({ business_date: targetDate });
  if (Number.isFinite(sectorId) && sectorId > 0) qs.set('sector_id', String(sectorId));
  if (Number.isFinite(routeId) && routeId > 0) qs.set('route_id', String(routeId));
  const fetchKey = qs.toString();
  if (deliveryMonitorLastKey === fetchKey && Array.isArray(deliveryMonitorRowsState) && deliveryMonitorRowsState.length) {
    renderDeliveryRouteMonitorTable();
    return;
  }

  deliveryMonitorRowsState = await req(
    `${API_BASE}/delivery/route-monitor?${qs.toString()}`,
  );
  deliveryMonitorLastKey = fetchKey;
  renderDeliveryRouteMonitorTable();
}

function renderDeliveryRouteMonitorTable() {
  if (!deliveryRouteMonitorTable) return;

  deliveryRouteMonitorTable.innerHTML = renderInlineTable(
    [
      'Sector',
      'Route',
      'Executive',
      'Assignment',
      'Total',
      'Pending',
      'Packed',
      'Out for Delivery',
      'Delivered',
      'Action',
    ],
    (deliveryMonitorRowsState || []).map((r) => [
      r.sector_name || r.sector_code || '-',
      r.route_code || '-',
      r.delivery_executive_name
        ? `${r.delivery_executive_name} (${r.delivery_executive_phone || '-'})`
        : '-',
      (r.assignment_status || 'UNASSIGNED').replaceAll('_', ' '),
      fmtNum(r.total_orders),
      fmtNum(r.pending_orders),
      fmtNum(r.packed_orders),
      fmtNum(r.out_for_delivery),
      fmtNum(r.delivered_orders),
      (r.assignment_status || '').toUpperCase() === 'COMPLETED' && r.assignment_id
        ? `<button class="small-btn" data-reopen-assignment="${r.assignment_id}">Reopen Route</button>`
        : '-',
    ]),
  );

  deliveryRouteMonitorTable
    .querySelectorAll('[data-reopen-assignment]')
    .forEach((btn) => {
      btn.addEventListener('click', async () => {
        const assignmentId = Number(btn.dataset.reopenAssignment);
        if (!Number.isFinite(assignmentId) || assignmentId <= 0) return;
        if (!confirm('Reopen this completed route? It will move back to IN_PROGRESS.')) return;
        try {
          await req(`${API_BASE}/delivery/assignments/${assignmentId}/reopen`, {
            method: 'POST',
          });
          showToast('Route reopened');
          await loadDeliverySummary();
        } catch (err) {
          showToast(err.message || 'Failed to reopen route', 'error');
        }
      });
    });
}

async function loadAccountingSummary() {
  if (!can('payments:read')) return;
  const data = await req(`${API_BASE}/modules/accounting/summary`);
  const o = data?.overview || {};
  accountingSummary.innerHTML =
    renderSummaryCards([
      { k: 'Total Payments (Today)', v: fmtNum(o.total_payments) },
      { k: 'Pending', v: fmtNum(o.pending) },
      { k: 'Paid', v: fmtNum(o.paid) },
      { k: 'Amount Total', v: `₹${fmtNum(o.amount_total, 2)}` },
      { k: 'Amount Paid', v: `₹${fmtNum(o.amount_paid, 2)}` },
    ]) +
    renderInlineTable(
      ['Provider', 'Transactions', 'Amount'],
      (data?.providers || []).map((it) => [it.provider, fmtNum(it.count), `₹${fmtNum(it.amount, 2)}`]),
    );
}

async function loadCustomersSummary() {
  if (!can('customers:read')) return;
  const data = await req(`${API_BASE}/modules/customers/summary`);
  const o = data?.overview || {};
  customersSummary.innerHTML =
    renderSummaryCards([{ k: 'Total Customers', v: fmtNum(o.total_customers) }]) +
    renderInlineTable(
      ['Name', 'Phone', 'Orders', 'Revenue'],
      (data?.top_customers || []).map((it) => [it.name || '-', it.phone || '-', fmtNum(it.total_orders), `₹${fmtNum(it.revenue, 2)}`]),
    );
}

async function loadRoutesModule() {
  if (!can('routes:read')) return;
  const data = await req(`${API_BASE}/modules/routes`);
  const sectors = data?.sectors || [];
  const routes = data?.routes || [];
  routesState = routes;

  routeSectorId.innerHTML = sectors.length
    ? sectors.map((s) => `<option value="${s.id}">${s.name} (${s.code})</option>`).join('')
    : '<option value="">No sectors</option>';

  routesSummary.innerHTML =
    renderSummaryCards([
      { k: 'Total Sectors', v: fmtNum(sectors.length) },
      { k: 'Total Routes', v: fmtNum(routes.length) },
    ]) +
    renderInlineTable(
      ['Route', 'Sector', 'Max Orders', 'Buildings', 'Status'],
      routes.map((r) => [r.route_code, r.sector_name || r.sector_code, fmtNum(r.max_orders), fmtNum(r.buildings_mapped), r.active ? 'Active' : 'Inactive']),
    );
}

async function loadReportsModule() {
  if (!can('reports:read')) return;
  const rows = await req(`${API_BASE}/modules/reports`);
  reportsSummary.innerHTML = renderInlineTable(
    ['Type', 'Business Date', 'Storage', 'Generated'],
    (rows || []).map((r) => [r.report_type, (r.business_date || '').slice(0, 10), r.storage_url || '-', new Date(r.created_at).toLocaleString('en-IN')]),
  );
}

async function loadNotificationsModule() {
  if (!can('dashboard:read')) return;
  const rows = await req(`${API_BASE}/modules/notifications`);
  notificationsSummary.innerHTML = renderInlineTable(
    ['Time', 'Type', 'Title', 'Message'],
    (rows || []).map((n) => [new Date(n.created_at).toLocaleString('en-IN'), n.kind || '-', n.title || '-', n.body || '-']),
  );
}

async function loadViewData(target) {
  if (target === 'dashboardView') await loadOrders();
  if (target === 'productsView') {
    await loadCategories();
    await loadProducts();
  }
  if (target === 'ordersView') await loadOrders();
  if (target === 'procurementView') await loadProcurementSummary();
  if (target === 'inventoryView') await loadInventorySummary();
  if (target === 'packingView') await loadPackingSummary();
  if (target === 'processingView') await loadProcessingStaff();
  if (target === 'deliveryView') await loadDeliverySummary();
  if (target === 'accountingView') await loadAccountingSummary();
  if (target === 'customersView') await loadCustomersSummary();
  if (target === 'routesView') await loadRoutesModule();
  if (target === 'reportsView') await loadReportsModule();
  if (target === 'notificationsView') await loadNotificationsModule();
  if (target === 'settingsView') await loadSettings();
}

async function loadCategories() {
  const rows = await req(`${CATALOG_BASE}/categories`);
  categories = Array.isArray(rows) ? rows : [];
  categoryId.innerHTML = categories
    .map((c) => `<option value="${c.id}">${c.name} (${c.type})</option>`)
    .join('');
}

function bindProductRowActions() {
  productsBody.querySelectorAll('[data-edit-id]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const id = Number(btn.dataset.editId);
      const found = productsState.find((p) => Number(p.id) === id);
      if (!found) return;
      fillProductForm(found);
      showView('productFormView');
      viewTitle.textContent = 'Edit Product';
    });
  });

  productsBody.querySelectorAll('[data-delete]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = btn.dataset.delete;
      if (!confirm(`Delete product #${id}?`)) return;
      try {
        await req(`${API_BASE}/products/${id}`, { method: 'DELETE' });
        await loadProducts();
      } catch (e) {
        alert(e.message);
      }
    });
  });
}

async function loadProducts() {
  if (!can('products:read')) return;
  const canWriteProducts = can('products:write');
  const rows = await req(`${API_BASE}/products${productRouteQuery()}`);
  productsState = Array.isArray(rows) ? rows : [];

  productsBody.innerHTML = productsState
    .map(
      (p) => `
      <tr>
        <td>${p.id}</td>
        <td>${p.name}</td>
        <td>${p.category_name ?? p.category_id}</td>
        <td>₹${Number(p.price).toFixed(2)}</td>
        <td>${p.unit}</td>
        <td>${p.in_stock ? 'In stock' : 'Out of stock'}</td>
        <td>
          <div class="table-actions">
            ${canWriteProducts
              ? `<button class="small-btn" data-edit-id="${p.id}">Edit</button>
                 <button class="small-btn danger" data-delete="${p.id}">Delete</button>`
              : '<span class="muted">Read only</span>'}
          </div>
        </td>
      </tr>
    `,
    )
    .join('');

  bindProductRowActions();
}

function populateOrderFilters() {
  const sectors = [...new Set(ordersState.map((o) => o.sector_name || o.sector_code || (o.sector_id ? `Sector ${o.sector_id}` : 'Unassigned Sector')))].sort();
  const routes = [...new Set(ordersState.map((o) => o.route_code || (o.route_id ? `Route ${o.route_id}` : 'Unassigned Route')))].sort();

  filterSector.innerHTML = '<option value="">All Sectors</option>' + sectors.map((v) => `<option value="${v}">${v}</option>`).join('');
  filterRoute.innerHTML = '<option value="">All Routes</option>' + routes.map((v) => `<option value="${v}">${v}</option>`).join('');
}

async function loadOrders() {
  if (!can('orders:read')) return;
  const rows = await req(`${API_BASE}/orders`);
  ordersState = Array.isArray(rows) ? rows : [];
  if (!filterDate.value) filterDate.value = localDateString();
  populateOrderFilters();
  renderOrders();
  renderDashboard();
}

async function loadSettings() {
  if (!can('settings:read')) return;
  const list = await req(`${API_BASE}/settings`);
  const map = Object.fromEntries((list || []).map((i) => [i.key, i.value]));
  document.getElementById('cutoffHour').value = map.cutoff_hour ?? 21;
  document.getElementById('gstPercent').value = map.gst_percent ?? 5;
  document.getElementById('serviceCity').value = map.service_city ?? 'Mohali';
  document.getElementById('servicePincodes').value = map.service_pincodes ?? '';
}

function fillProductForm(p) {
  document.getElementById('productId').value = p.id || '';
  categoryId.value = String(p.category_id || categories[0]?.id || '');
  document.getElementById('productName').value = p.name || '';
  document.getElementById('productSubcategory').value = p.subcategory || '';
  document.getElementById('productUnit').value = p.unit || '';
  document.getElementById('productPrice').value = Number(p.price || 0);
  productImageInput.value = p.image_url || '';
  document.getElementById('productStock').value = String(!!p.in_stock);
  updateImagePreview(p.image_url || '');
  productFormTitle.textContent = p.id ? `Edit Product #${p.id}` : 'Add Product';
}

function clearProductForm() {
  productForm.reset();
  document.getElementById('productId').value = '';
  if (categories.length) categoryId.value = String(categories[0].id);
  productImageFile.value = '';
  updateImagePreview('');
  productFormTitle.textContent = 'Add Product';
  productFormMsg.textContent = '';
}

async function uploadSelectedImage(file) {
  if (!file) return;
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    productFormMsg.textContent = 'Only JPG, PNG, WEBP allowed.';
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    productFormMsg.textContent = 'Image too large. Max 5MB.';
    return;
  }

  const dataBase64 = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const text = String(reader.result || '');
      resolve(text.includes(',') ? text.split(',')[1] : text);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });

  productFormMsg.textContent = 'Uploading image...';
  try {
    const uploaded = await req(`${API_BASE}/uploads`, {
      method: 'POST',
      body: JSON.stringify({
        filename: file.name,
        mime_type: file.type,
        data_base64: dataBase64,
      }),
    });
    productImageInput.value = uploaded.url;
    updateImagePreview(uploaded.url);
    productFormMsg.textContent = 'Image uploaded successfully.';
  } catch (err) {
    productFormMsg.textContent = err.message;
  } finally {
    productImageFile.value = '';
  }
}

async function bootstrap() {
  if (!token) return showLogin();

  try {
    meState = await req(`${API_BASE}/me`);
    if (!meState) throw new Error('Invalid admin session');

    adminMeta.textContent = `${meState.name} (${meState.email})\nRole: ${meState.role_code || meState.role}`;
    todayLabel.textContent = new Date().toLocaleString('en-IN', {
      weekday: 'short',
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });

    applyRoleVisibility();
    showApp();

    const firstVisible = navButtons.find((b) => !b.classList.contains('hidden'))?.dataset.view || 'dashboardView';
    showView(firstVisible);
    activateNavButton(firstVisible);

    await loadViewData(firstVisible);
  } catch (e) {
    token = '';
    localStorage.removeItem('admin_token');
    loginError.textContent = e?.message || 'Session expired. Please login again.';
    showLogin();
  }
}

loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  loginError.textContent = '';
  try {
    const data = await req(`${API_BASE}/auth/login`, {
      method: 'POST',
      body: JSON.stringify({
        email: document.getElementById('loginEmail').value.trim(),
        password: document.getElementById('loginPassword').value,
      }),
    });
    token = data.token;
    localStorage.setItem('admin_token', token);
    await bootstrap();
  } catch (err) {
    loginError.textContent = err.message;
  }
});

document.getElementById('logoutBtn').addEventListener('click', () => {
  token = '';
  meState = null;
  localStorage.removeItem('admin_token');
  showLogin();
});

navButtons.forEach((btn) => {
  btn.addEventListener('click', async () => {
    const target = btn.dataset.view;
    activateNavButton(target);
    showView(target);
    await loadViewData(target);
  });
});

document.getElementById('refreshProducts').addEventListener('click', loadProducts);
document.getElementById('refreshOrders').addEventListener('click', loadOrders);
document.getElementById('refreshProcurement')?.addEventListener('click', loadProcurementSummary);
document.getElementById('refreshInventory')?.addEventListener('click', loadInventorySummary);
document.getElementById('refreshPacking')?.addEventListener('click', loadPackingSummary);
document.getElementById('refreshProcessingStaff')?.addEventListener('click', loadProcessingStaff);
document.getElementById('refreshDelivery')?.addEventListener('click', loadDeliverySummary);
document.getElementById('refreshAccounting')?.addEventListener('click', loadAccountingSummary);
document.getElementById('refreshCustomers')?.addEventListener('click', loadCustomersSummary);
document.getElementById('refreshRoutes')?.addEventListener('click', loadRoutesModule);
document.getElementById('refreshReports')?.addEventListener('click', loadReportsModule);
document.getElementById('refreshNotifications')?.addEventListener('click', loadNotificationsModule);
productSearch.addEventListener('input', () => {
  clearTimeout(window.__searchTimer);
  window.__searchTimer = setTimeout(loadProducts, 250);
});
orderStatusFilter.addEventListener('change', loadOrders);
filterDate.addEventListener('change', renderOrders);
filterSector.addEventListener('change', renderOrders);
filterRoute.addEventListener('change', renderOrders);

const today = localDateString();
filterDate.value = today;
if (deliveryBusinessDate) deliveryBusinessDate.value = today;

document.getElementById('openCreateProduct').addEventListener('click', () => {
  clearProductForm();
  showView('productFormView');
  viewTitle.textContent = 'Add Product';
});

document.getElementById('backToProducts').addEventListener('click', async () => {
  showView('productsView');
  viewTitle.textContent = 'Products';
  await loadProducts();
});

document.getElementById('productReset').addEventListener('click', clearProductForm);
productImageFile.addEventListener('change', async (e) => {
  await uploadSelectedImage(e.target.files?.[0]);
});

productForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  productFormMsg.textContent = '';

  const id = document.getElementById('productId').value;
  const payload = {
    category_id: Number(categoryId.value),
    name: document.getElementById('productName').value.trim(),
    subcategory: document.getElementById('productSubcategory').value || null,
    unit: document.getElementById('productUnit').value.trim(),
    price: Number(document.getElementById('productPrice').value),
    image_url: productImageInput.value.trim() || null,
    in_stock: document.getElementById('productStock').value === 'true',
  };

  try {
    saveProductBtn.disabled = true;
    saveProductBtn.textContent = 'Saving...';
    if (id) {
      await req(`${API_BASE}/products/${id}`, { method: 'PUT', body: JSON.stringify(payload) });
      showToast('Product updated successfully');
    } else {
      await req(`${API_BASE}/products`, { method: 'POST', body: JSON.stringify(payload) });
      showToast('Product created successfully');
      clearProductForm();
    }
    await loadProducts();
    showView('productsView');
    viewTitle.textContent = 'Products';
  } catch (err) {
    productFormMsg.textContent = err.message;
    showToast(err.message || 'Failed to save product', 'error');
  } finally {
    saveProductBtn.disabled = false;
    saveProductBtn.textContent = 'Save Product';
  }
});

deliveryExecutiveForm?.addEventListener('submit', async (e) => {
  e.preventDefault();
  const rawName = deliveryExecName.value.trim();
  const rawPhone = deliveryExecPhone.value.trim();
  const code = deliveryExecCode.value.trim();

  if (rawName.length < 2) {
    deliveryModuleMsg.textContent = 'Executive name must be at least 2 characters.';
    return;
  }

  const digits = rawPhone.replace(/\D/g, '');
  if (digits.length !== 10 && digits.length !== 12) {
    deliveryModuleMsg.textContent = 'Phone must be a valid Indian mobile number.';
    return;
  }
  const normalized = digits.length === 10 ? `+91${digits}` : `+${digits}`;

  try {
    await req(`${API_BASE}/delivery/executives`, {
      method: 'POST',
      body: JSON.stringify({
        name: rawName,
        phone: normalized,
        employee_code: code || null,
        active: true,
      }),
    });
    deliveryExecName.value = '';
    deliveryExecPhone.value = '';
    deliveryExecCode.value = '';
    showToast('Delivery executive created');
    await loadDeliverySummary();
  } catch (err) {
    deliveryModuleMsg.textContent = err.message;
  }
});

processingStaffForm?.addEventListener('submit', async (e) => {
  e.preventDefault();
  const rawName = processingStaffName.value.trim();
  const rawPhone = processingStaffPhone.value.trim();
  const code = processingStaffCode.value.trim();

  if (rawName.length < 2) {
    processingStaffMsg.textContent = 'Staff name must be at least 2 characters.';
    return;
  }

  const digits = rawPhone.replace(/\D/g, '');
  if (digits.length !== 10 && digits.length !== 12) {
    processingStaffMsg.textContent = 'Phone must be a valid Indian mobile number.';
    return;
  }
  const normalized = digits.length === 10 ? `+91${digits}` : `+${digits}`;

  try {
    await req(`${API_BASE}/processing/staff`, {
      method: 'POST',
      body: JSON.stringify({
        name: rawName,
        phone: normalized,
        employee_code: code || null,
        active: true,
      }),
    });
    processingStaffName.value = '';
    processingStaffPhone.value = '';
    processingStaffCode.value = '';
    showToast('Processing staff created');
    await loadProcessingStaff();
  } catch (err) {
    processingStaffMsg.textContent = err.message;
    showToast(err.message, 'error');
  }
});

deliveryAssignmentForm?.addEventListener('submit', async (e) => {
  e.preventDefault();
  const businessDate = normalizeBusinessDate(deliveryBusinessDate.value);
  const routeId = Number(deliveryRouteId.value);
  const executiveId = Number(deliveryExecutiveId.value);

  if (!businessDate) {
    deliveryModuleMsg.textContent = 'Business date is required.';
    return;
  }
  if (!Number.isFinite(routeId) || routeId <= 0) {
    deliveryModuleMsg.textContent = 'Select a valid route.';
    return;
  }
  if (!Number.isFinite(executiveId) || executiveId <= 0) {
    deliveryModuleMsg.textContent = 'Select a valid delivery executive.';
    return;
  }

  try {
    await req(`${API_BASE}/delivery/assignments`, {
      method: 'POST',
      body: JSON.stringify({
        business_date: businessDate,
        route_id: routeId,
        delivery_executive_id: executiveId,
      }),
    });
    showToast('Route assigned successfully');
    await loadDeliverySummary();
  } catch (err) {
    deliveryModuleMsg.textContent = err.message;
  }
});

deliveryBusinessDate?.addEventListener('change', loadDeliverySummary);
deliveryMonitorSector?.addEventListener('change', async () => {
  deliveryMonitorLastKey = '';
  await loadDeliverySummary();
});
deliveryMonitorRoute?.addEventListener('change', async () => {
  deliveryMonitorLastKey = '';
  await loadDeliveryRouteMonitor();
});
refreshDeliveryMonitor?.addEventListener('click', async () => {
  deliveryMonitorLastKey = '';
  await loadDeliveryRouteMonitor();
});

routeForm?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!can('routes:write')) return;
  try {
    await req(`${API_BASE}/modules/routes`, {
      method: 'POST',
      body: JSON.stringify({
        route_code: document.getElementById('routeCode').value.trim(),
        sector_id: Number(routeSectorId.value),
        max_orders: Number(document.getElementById('routeMaxOrders').value),
      }),
    });
    document.getElementById('routeCode').value = '';
    showToast('Route created');
    await loadRoutesModule();
  } catch (err) {
    showToast(err.message || 'Failed to create route', 'error');
  }
});

settingsForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  settingsMsg.textContent = '';
  try {
    const serviceCity = document.getElementById('serviceCity').value.trim();
    const servicePincodes = document.getElementById('servicePincodes').value
      .split(',')
      .map((v) => v.trim())
      .filter(Boolean)
      .join(',');

    await req(`${API_BASE}/settings`, {
      method: 'PUT',
      body: JSON.stringify({ key: 'cutoff_hour', value: String(document.getElementById('cutoffHour').value) }),
    });
    await req(`${API_BASE}/settings`, {
      method: 'PUT',
      body: JSON.stringify({ key: 'gst_percent', value: String(document.getElementById('gstPercent').value) }),
    });
    await req(`${API_BASE}/settings`, {
      method: 'PUT',
      body: JSON.stringify({ key: 'service_city', value: serviceCity || 'Mohali' }),
    });
    await req(`${API_BASE}/settings`, {
      method: 'PUT',
      body: JSON.stringify({ key: 'service_pincodes', value: servicePincodes }),
    });
    settingsMsg.textContent = 'Settings saved.';
  } catch (err) {
    settingsMsg.textContent = err.message;
  }
});

document.getElementById('nightReminderBtn').addEventListener('click', async () => {
  settingsMsg.textContent = '';
  try {
    await req(`${API_BASE}/jobs/night-reminder`, { method: 'POST' });
    settingsMsg.textContent = 'Cutoff reminder job queued.';
  } catch (err) {
    settingsMsg.textContent = err.message;
  }
});

bootstrap();
