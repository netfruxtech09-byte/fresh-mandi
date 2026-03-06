const API_BASE = '/api/v1/admin';
const CATALOG_BASE = '/api/v1/catalog';

const views = ['dashboardView', 'productsView', 'ordersView', 'settingsView', 'productFormView'];
const viewTitles = {
  dashboardView: 'Dashboard',
  productsView: 'Products',
  ordersView: 'Orders',
  settingsView: 'Settings',
  productFormView: 'Product Form',
};

const loginView = document.getElementById('loginView');
const appView = document.getElementById('appView');
const loginForm = document.getElementById('loginForm');
const loginError = document.getElementById('loginError');
const adminMeta = document.getElementById('adminMeta');
const viewTitle = document.getElementById('viewTitle');

const navButtons = [...document.querySelectorAll('.nav-btn')];
const kpis = document.getElementById('kpis');
const chart = document.getElementById('chart');
const productsBody = document.getElementById('productsBody');
const ordersBody = document.getElementById('ordersBody');

const productForm = document.getElementById('productForm');
const productFormMsg = document.getElementById('productFormMsg');
const productFormTitle = document.getElementById('productFormTitle');
const saveProductBtn = document.getElementById('saveProductBtn');
const settingsForm = document.getElementById('settingsForm');
const settingsMsg = document.getElementById('settingsMsg');
const toast = document.getElementById('toast');

const productSearch = document.getElementById('productSearch');
const orderStatusFilter = document.getElementById('orderStatusFilter');
const orderDateQuick = document.getElementById('orderDateQuick');
const orderDateFrom = document.getElementById('orderDateFrom');
const orderDateTo = document.getElementById('orderDateTo');
const orderSort = document.getElementById('orderSort');
const categoryId = document.getElementById('categoryId');
const productImageFile = document.getElementById('productImageFile');
const productImageInput = document.getElementById('productImage');
const productImagePreview = document.getElementById('productImagePreview');
const productImageMeta = document.getElementById('productImageMeta');

let token = localStorage.getItem('admin_token') || '';
let categories = [];
let productsState = [];
let ordersState = [];
let toastTimer;

async function req(path, options = {}) {
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(path, {
    ...options,
    headers,
    cache: 'no-store',
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body?.message || `Request failed (${res.status})`);
  return body?.data;
}

function showToast(message, type = 'success') {
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.remove('hidden', 'success', 'error');
  toast.classList.add(type);
  toastTimer = setTimeout(() => toast.classList.add('hidden'), 2600);
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

function orderQuery() {
  const s = orderStatusFilter.value;
  return s ? `?status=${encodeURIComponent(s)}` : '';
}

function renderKpis(totals) {
  const items = [
    ['Users', totals.users],
    ['Orders', totals.orders],
    ['Products', totals.products],
    ['Categories', totals.categories],
    ['Revenue', `₹${Number(totals.revenue).toFixed(0)}`],
  ];
  kpis.innerHTML = items
    .map(([label, value]) => `<div class="kpi"><div class="label">${label}</div><div class="value">${value}</div></div>`)
    .join('');
}

function renderChart(rows) {
  if (!rows.length) {
    chart.innerHTML = '<div class="chart-empty">No recent orders yet.</div>';
    return;
  }

  if (rows.length < 2) {
    chart.innerHTML = `
      <div class="chart-empty">
        Not enough data for trend chart yet.
        <small>Create a few more orders to unlock daily trend visualization.</small>
      </div>
    `;
    return;
  }
  const max = Math.max(...rows.map((r) => Number(r.amount || 0)), 1);
  chart.innerHTML = rows
    .map((r) => {
      const h = Math.max(10, Math.round((Number(r.amount || 0) / max) * 120));
      const parsed = new Date(r.day);
      const label = Number.isNaN(parsed.getTime())
        ? String(r.day).slice(0, 10)
        : parsed.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
      return `<div class="chart-col" style="height:${h}px" title="₹${Number(r.amount || 0).toFixed(2)}">
        <span>${label}</span>
      </div>`;
    })
    .join('');
}

async function loadCategories() {
  categories = await req(`${CATALOG_BASE}/categories`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  if (!Array.isArray(categories)) categories = [];
  categoryId.innerHTML = categories.map((c) => `<option value="${c.id}">${c.name} (${c.type})</option>`).join('');
  if (categories.length) categoryId.value = String(categories[0].id);
}

async function loadDashboard() {
  const data = await req(`${API_BASE}/dashboard`);
  renderKpis(data.totals || {});
  renderChart(data.orders_by_day || []);
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
        await Promise.all([loadProducts(), loadDashboard()]);
      } catch (e) {
        alert(e.message);
      }
    });
  });
}

async function loadProducts() {
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
            <button class="small-btn" data-edit-id="${p.id}">Edit</button>
            <button class="small-btn danger" data-delete="${p.id}">Delete</button>
          </div>
        </td>
      </tr>
    `,
    )
    .join('');

  bindProductRowActions();
}

async function loadOrders() {
  const rows = await req(`${API_BASE}/orders${orderQuery()}`);
  ordersState = Array.isArray(rows) ? rows : [];
  renderOrders();
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function renderOrders() {
  const quick = orderDateQuick?.value || 'all';
  const from = orderDateFrom?.value || '';
  const to = orderDateTo?.value || '';
  const sort = orderSort?.value || 'latest';
  const now = new Date();
  const todayStart = startOfDay(now);
  const yStart = new Date(todayStart);
  yStart.setDate(todayStart.getDate() - 1);

  let data = [...ordersState];

  data = data.filter((o) => {
    const dt = new Date(o.created_at || o.createdAt || 0);
    if (Number.isNaN(dt.getTime())) return quick === 'all';
    const day = startOfDay(dt);
    if (quick === 'today') return day.getTime() === todayStart.getTime();
    if (quick === 'yesterday') return day.getTime() === yStart.getTime();
    if (quick === 'range') {
      if (!from && !to) return true;
      const fromDt = from ? startOfDay(new Date(from)) : null;
      const toDt = to ? startOfDay(new Date(to)) : null;
      if (fromDt && day < fromDt) return false;
      if (toDt && day > toDt) return false;
    }
    return true;
  });

  data.sort((a, b) => {
    const da = new Date(a.created_at || 0).getTime();
    const db = new Date(b.created_at || 0).getTime();
    const ta = Number.isNaN(da) ? Number(a.id) : da;
    const tb = Number.isNaN(db) ? Number(b.id) : db;
    return sort === 'oldest' ? ta - tb : tb - ta;
  });

  ordersBody.innerHTML = data
    .map((o) => {
      const statusOpts = ['PENDING_PAYMENT', 'CONFIRMED', 'PACKED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED']
        .map((s) => `<option value="${s}" ${o.status === s ? 'selected' : ''}>${s}</option>`)
        .join('');
      const created = new Date(o.created_at || 0);
      const createdText = Number.isNaN(created.getTime())
        ? '-'
        : created.toLocaleString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
          });
      return `
      <tr>
        <td>#${o.id}</td>
        <td>${createdText}</td>
        <td>${o.user_name || '-'}</td>
        <td>${o.user_phone || '-'}</td>
        <td>₹${Number(o.total).toFixed(2)}</td>
        <td><select class="status-select" data-order-status="${o.id}">${statusOpts}</select></td>
        <td>${o.slot_label || '-'}</td>
        <td>${o.line1}, ${o.city}, ${o.state} ${o.pincode}</td>
      </tr>
    `;
    })
    .join('');

  ordersBody.querySelectorAll('[data-order-status]').forEach((el) => {
    el.addEventListener('change', async () => {
      try {
        await req(`${API_BASE}/orders/${el.dataset.orderStatus}/status`, {
          method: 'PATCH',
          body: JSON.stringify({ status: el.value }),
        });
      } catch (e) {
        alert(e.message);
      }
    });
  });
}

async function loadSettings() {
  const list = await req(`${API_BASE}/settings`);
  const map = Object.fromEntries((list || []).map((i) => [i.key, i.value]));
  document.getElementById('cutoffHour').value = map.cutoff_hour ?? 21;
  document.getElementById('gstPercent').value = map.gst_percent ?? 5;
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
    // Allow selecting the same file again (browser won't fire change otherwise).
    productImageFile.value = '';
  }
}

async function bootstrap() {
  if (!token) return showLogin();

  try {
    const me = await req(`${API_BASE}/me`);
    if (!me) throw new Error('Invalid admin session');

    adminMeta.textContent = `${me.name} (${me.email})`;
    showApp();
    showView('dashboardView');

    await Promise.allSettled([loadCategories(), loadDashboard(), loadProducts(), loadOrders(), loadSettings()]);
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
  localStorage.removeItem('admin_token');
  showLogin();
});

navButtons.forEach((btn) => {
  btn.addEventListener('click', async () => {
    const target = btn.dataset.view;
    activateNavButton(target);
    showView(target);

    if (target === 'dashboardView') await loadDashboard();
    if (target === 'productsView') await loadProducts();
    if (target === 'ordersView') await loadOrders();
    if (target === 'settingsView') await loadSettings();
  });
});

document.getElementById('refreshProducts').addEventListener('click', loadProducts);
document.getElementById('refreshOrders').addEventListener('click', loadOrders);
productSearch.addEventListener('input', () => {
  clearTimeout(window.__searchTimer);
  window.__searchTimer = setTimeout(loadProducts, 250);
});
orderStatusFilter.addEventListener('change', loadOrders);
orderDateQuick.addEventListener('change', () => {
  const isRange = orderDateQuick.value === 'range';
  orderDateFrom.disabled = !isRange;
  orderDateTo.disabled = !isRange;
  renderOrders();
});
orderDateFrom.addEventListener('change', renderOrders);
orderDateTo.addEventListener('change', renderOrders);
orderSort.addEventListener('change', renderOrders);
orderDateFrom.disabled = true;
orderDateTo.disabled = true;

document.getElementById('openCreateProduct').addEventListener('click', () => {
  if (!categories.length) {
    productFormMsg.textContent = 'Categories not loaded yet. Refresh and try again.';
  }
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

  if (!Number.isFinite(payload.category_id) || payload.category_id <= 0) {
    productFormMsg.classList.add('error-text');
    productFormMsg.textContent = 'Category is required.';
    showToast('Please select category', 'error');
    return;
  }

  try {
    saveProductBtn.disabled = true;
    saveProductBtn.textContent = 'Saving...';
    productFormMsg.classList.remove('error-text');
    if (id) {
      await req(`${API_BASE}/products/${id}`, { method: 'PUT', body: JSON.stringify(payload) });
      productFormMsg.textContent = 'Product updated successfully.';
      showToast('Product updated successfully');
    } else {
      await req(`${API_BASE}/products`, { method: 'POST', body: JSON.stringify(payload) });
      productFormMsg.textContent = 'Product created successfully.';
      showToast('Product created successfully');
      clearProductForm();
    }
    await Promise.all([loadProducts(), loadDashboard()]);
    showView('productsView');
    viewTitle.textContent = 'Products';
  } catch (err) {
    productFormMsg.classList.add('error-text');
    productFormMsg.textContent = err.message;
    showToast(err.message || 'Failed to save product', 'error');
  } finally {
    saveProductBtn.disabled = false;
    saveProductBtn.textContent = 'Save Product';
  }
});

settingsForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  settingsMsg.textContent = '';
  try {
    await req(`${API_BASE}/settings`, {
      method: 'PUT',
      body: JSON.stringify({ key: 'cutoff_hour', value: String(document.getElementById('cutoffHour').value) }),
    });
    await req(`${API_BASE}/settings`, {
      method: 'PUT',
      body: JSON.stringify({ key: 'gst_percent', value: String(document.getElementById('gstPercent').value) }),
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
    settingsMsg.textContent = 'Night reminder queued for all users.';
  } catch (err) {
    settingsMsg.textContent = err.message;
  }
});

bootstrap();
