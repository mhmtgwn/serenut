// core_next/web_portal/src/App.tsx
import { useState } from 'react';
import { formatTL, DashboardMetrics, ProductDto, CustomerDto, SaleSummaryDto } from './types/portal.ts';

// Örnek Tip Güvenli Başlangıç Verileri
const mockMetrics: DashboardMetrics = {
  todayRevenueCents: 485250, // 4.852,50 TL
  todaySalesCount: 38,
  totalCustomerDebtCents: 1250000, // 12.500,00 TL
  criticalStockCount: 4,
  onlineDevicesCount: 3,
};

const mockProducts: ProductDto[] = [
  { id: '1', barcode: '8690123456789', name: 'Organik Zeytinyağı 1L', categoryName: 'Gıda', priceCents: 24999, vatRate: 10, stockQuantity: 18, criticalThreshold: 5, isActive: true },
  { id: '2', barcode: '8690504123456', name: 'Doğal Dağ İnciri 500g', categoryName: 'Kuru Meyve', priceCents: 8550, vatRate: 20, stockQuantity: 3, criticalThreshold: 5, isActive: true },
  { id: '3', barcode: '8690876543210', name: 'Hakiki Çam Balı 850g', categoryName: 'Kahvaltılık', priceCents: 32000, vatRate: 10, stockQuantity: 24, criticalThreshold: 5, isActive: true },
  { id: '4', barcode: '8690111222333', name: 'Köy Yumurtası 30lu', categoryName: 'Şarküteri', priceCents: 11000, vatRate: 1, stockQuantity: 2, criticalThreshold: 5, isActive: true },
];

const mockCustomers: CustomerDto[] = [
  { id: '1', name: 'Ahmet Yılmaz', phone: '0555 123 45 67', balanceCents: -15000, creditLimitCents: 100000, isActive: true },
  { id: '2', name: 'Fatma Hanım (Manav)', phone: '0532 987 65 43', balanceCents: -42500, creditLimitCents: 200000, isActive: true },
  { id: '3', name: 'Mehmet Demir', phone: '0544 555 12 34', balanceCents: 5000, creditLimitCents: 50000, isActive: true },
];

const mockSales: SaleSummaryDto[] = [
  { id: 's1', receiptNo: '20261012-0038', customerName: 'Ahmet Yılmaz', totalCents: 15000, paidCents: 0, debtCents: 15000, itemCount: 2, createdAt: '14:45' },
  { id: 's2', receiptNo: '20261012-0037', customerName: 'Perakende Müşteri', totalCents: 24999, paidCents: 24999, debtCents: 0, itemCount: 1, createdAt: '14:22' },
  { id: 's3', receiptNo: '20261012-0036', customerName: 'Perakende Müşteri', totalCents: 8550, paidCents: 8550, debtCents: 0, itemCount: 1, createdAt: '13:58' },
];

export function App() {
  const [activeTab, setActiveTab] = useState<'dashboard' | 'products' | 'customers'>('dashboard');
  const [productSearch, setProductSearch] = useState('');

  const filteredProducts = mockProducts.filter(
    (p) => p.name.toLowerCase().includes(productSearch.toLowerCase()) || p.barcode.includes(productSearch)
  );

  return (
    <div className="app-container">
      {/* ── SOL MENÜ ──────────────────────────────────────────────────────── */}
      <aside className="sidebar">
        <div className="sidebar-logo">
          <div className="logo-badge">S</div>
          <div>
            <h1>Serenut OS</h1>
            <p style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Enterprise v2.0</p>
          </div>
        </div>

        <ul className="nav-links">
          <li
            className={`nav-item ${activeTab === 'dashboard' ? 'active' : ''}`}
            onClick={() => setActiveTab('dashboard')}
          >
            📊 Genel Bakış
          </li>
          <li
            className={`nav-item ${activeTab === 'products' ? 'active' : ''}`}
            onClick={() => setActiveTab('products')}
          >
            📦 Ürün Kataloğu
          </li>
          <li
            className={`nav-item ${activeTab === 'customers' ? 'active' : ''}`}
            onClick={() => setActiveTab('customers')}
          >
            👥 Cari Defter
          </li>
        </ul>
      </aside>

      {/* ── ANA İÇERİK ────────────────────────────────────────────────────── */}
      <main className="main-content">
        <header className="top-header">
          <div>
            <h2 className="page-title">
              {activeTab === 'dashboard' && 'Yönetim Paneli'}
              {activeTab === 'products' && 'Ürün Kataloğu'}
              {activeTab === 'customers' && 'Cari Hesap Defteri'}
            </h2>
            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
              Merkez Şube • Anlık Senkronize
            </p>
          </div>
          <div className="status-pill">
            <span className="status-dot"></span>
            {mockMetrics.onlineDevicesCount} Kasa Aktif
          </div>
        </header>

        {/* ── 1. DASHBOARD GÖRÜNÜMÜ ────────────────────────────────────────── */}
        {activeTab === 'dashboard' && (
          <>
            <div className="metrics-grid">
              <div className="metric-card">
                <span className="metric-label">Bugünkü Ciro</span>
                <span className="metric-value" style={{ color: 'var(--success)' }}>
                  {formatTL(mockMetrics.todayRevenueCents)}
                </span>
              </div>
              <div className="metric-card">
                <span className="metric-label">Bugünkü Satış Adedi</span>
                <span className="metric-value">{mockMetrics.todaySalesCount} Fiş</span>
              </div>
              <div className="metric-card">
                <span className="metric-label">Toplam Veresiye Borcu</span>
                <span className="metric-value" style={{ color: 'var(--danger)' }}>
                  {formatTL(mockMetrics.totalCustomerDebtCents)}
                </span>
              </div>
              <div className="metric-card">
                <span className="metric-label">Kritik Stok Uyarısı</span>
                <span className="metric-value" style={{ color: 'var(--warning)' }}>
                  {mockMetrics.criticalStockCount} Ürün
                </span>
              </div>
            </div>

            <section className="card-section">
              <div className="section-header">
                <h3 className="section-title">Son Kasa Satışları (Canlı Akış)</h3>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Fiş No</th>
                    <th>Saat</th>
                    <th>Müşteri</th>
                    <th>Adet</th>
                    <th>Tutar</th>
                    <th>Durum</th>
                  </tr>
                </thead>
                <tbody>
                  {mockSales.map((s) => (
                    <tr key={s.id}>
                      <td style={{ fontWeight: 600 }}>{s.receiptNo}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{s.createdAt}</td>
                      <td>{s.customerName}</td>
                      <td>{s.itemCount} kalem</td>
                      <td style={{ fontWeight: 600 }}>{formatTL(s.totalCents)}</td>
                      <td>
                        {s.debtCents > 0 ? (
                          <span className="badge badge-warning">Veresiye</span>
                        ) : (
                          <span className="badge badge-success">Tahsil Edildi</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>
          </>
        )}

        {/* ── 2. ÜRÜNLER GÖRÜNÜMÜ ──────────────────────────────────────────── */}
        {activeTab === 'products' && (
          <section className="card-section">
            <div className="section-header">
              <h3 className="section-title">Kayıtlı Ürünler ({filteredProducts.length})</h3>
              <input
                type="text"
                placeholder="Barkod veya ürün adı ile ara..."
                className="search-input"
                value={productSearch}
                onChange={(e) => setProductSearch(e.target.value)}
              />
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Barkod</th>
                  <th>Ürün Adı</th>
                  <th>Kategori</th>
                  <th>Fiyat (Kuruş Tam)</th>
                  <th>KDV</th>
                  <th>Stok Durumu</th>
                </tr>
              </thead>
              <tbody>
                {filteredProducts.map((p) => {
                  const isLow = p.stockQuantity <= p.criticalThreshold;
                  return (
                    <tr key={p.id}>
                      <td style={{ fontFamily: 'monospace', color: 'var(--text-secondary)' }}>
                        {p.barcode}
                      </td>
                      <td style={{ fontWeight: 600 }}>{p.name}</td>
                      <td>{p.categoryName}</td>
                      <td style={{ fontWeight: 700, color: 'var(--accent-primary)' }}>
                        {formatTL(p.priceCents)}
                      </td>
                      <td>%{p.vatRate}</td>
                      <td>
                        <span className={`badge ${isLow ? 'badge-danger' : 'badge-success'}`}>
                          {p.stockQuantity} Adet {isLow && '(Kritik)'}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </section>
        )}

        {/* ── 3. CARİLER GÖRÜNÜMÜ ──────────────────────────────────────────── */}
        {activeTab === 'customers' && (
          <section className="card-section">
            <div className="section-header">
              <h3 className="section-title">Cari Hesap Defteri ({mockCustomers.length})</h3>
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Müşteri Adı</th>
                  <th>Telefon</th>
                  <th>Bakiye Durumu</th>
                  <th>Kredi Limiti</th>
                  <th>Durum</th>
                </tr>
              </thead>
              <tbody>
                {mockCustomers.map((c) => {
                  const isDebtor = c.balanceCents < 0;
                  return (
                    <tr key={c.id}>
                      <td style={{ fontWeight: 600 }}>{c.name}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{c.phone}</td>
                      <td
                        style={{
                          fontWeight: 700,
                          color: isDebtor ? 'var(--danger)' : 'var(--success)',
                        }}
                      >
                        {formatTL(c.balanceCents)}
                      </td>
                      <td>{formatTL(c.creditLimitCents)}</td>
                      <td>
                        <span className={`badge ${isDebtor ? 'badge-danger' : 'badge-success'}`}>
                          {isDebtor ? 'Borçlu' : 'Bakiyeli'}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </section>
        )}
      </main>
    </div>
  );
}
