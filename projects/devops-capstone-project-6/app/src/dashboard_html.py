"""SupplyShield DevSecOps Platformu — Modern İnteraktif Web Frontend Arayüzü.
Bu modül, FastAPI üzerinden doğrudan sunulan tek sayfalık (SPA) modern ve responsive
bir DevSecOps vitrini sağlar.
"""

DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SupplyShield — DevSecOps & Supply Chain Security</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🛡️</text></svg>">
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    body { background-color: #0b1120; color: #e2e8f0; font-family: ui-sans-serif, system-ui, -apple-system, sans-serif; }
    .glass-card { background: rgba(30, 41, 59, 0.7); backdrop-filter: blur(12px); border: 1px solid rgba(255, 255, 255, 0.08); }
    .pulse-dot { animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite; }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .3; } }
  </style>
</head>
<body class="min-h-screen flex flex-col">

  <!-- ÜST MENÜ & BAŞLIK -->
  <header class="border-b border-slate-800 bg-slate-900/80 sticky top-0 z-50 backdrop-blur-md">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3 flex flex-wrap items-center justify-between gap-4">
      <div class="flex items-center space-x-3">
        <span class="text-3xl">🛡️</span>
        <div>
          <div class="flex items-center space-x-2">
            <h1 class="text-xl font-bold text-white tracking-tight">SupplyShield</h1>
            <span class="bg-emerald-500/10 text-emerald-400 text-xs font-semibold px-2.5 py-0.5 rounded-full border border-emerald-500/20">DevSecOps v1.0</span>
          </div>
          <p class="text-xs text-slate-400">Zero-Trust Software Supply Chain & Artifact Security (RKE2 Cluster)</p>
        </div>
      </div>

      <!-- Hızlı Bağlantı Butonları -->
      <div class="flex flex-wrap items-center gap-2 text-xs">
        <a id="link-harbor" href="#" target="_blank" class="px-3 py-1.5 rounded-lg bg-sky-900/40 text-sky-300 border border-sky-700/50 hover:bg-sky-800/50 transition">📦 Harbor OCI</a>
        <a id="link-jenkins" href="#" target="_blank" class="px-3 py-1.5 rounded-lg bg-red-900/40 text-red-300 border border-red-700/50 hover:bg-red-800/50 transition">⚙️ Jenkins CI</a>
        <a id="link-argocd" href="#" target="_blank" class="px-3 py-1.5 rounded-lg bg-orange-900/40 text-orange-300 border border-orange-700/50 hover:bg-orange-800/50 transition">🐙 ArgoCD</a>
        <a id="link-grafana" href="#" target="_blank" class="px-3 py-1.5 rounded-lg bg-yellow-900/40 text-yellow-300 border border-yellow-700/50 hover:bg-yellow-800/50 transition">📊 Grafana</a>
        <a href="/docs" target="_blank" class="px-3 py-1.5 rounded-lg bg-emerald-900/40 text-emerald-300 border border-emerald-700/50 hover:bg-emerald-800/50 transition">📖 Swagger Docs</a>
        <a href="/metrics" target="_blank" class="px-3 py-1.5 rounded-lg bg-purple-900/40 text-purple-300 border border-purple-700/50 hover:bg-purple-800/50 transition">📈 Prometheus</a>
      </div>
    </div>
  </header>

  <!-- ANA İÇERİK -->
  <main class="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6">

    <!-- SİSTEM DURUM KARTLARI -->
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
      <!-- Pod & Host Bilgisi -->
      <div class="glass-card rounded-xl p-4">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-slate-400">Canlı Pod / Düğüm</span>
          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold bg-emerald-950 text-emerald-400 border border-emerald-800/50">
            <span class="w-2 h-2 mr-1.5 rounded-full bg-emerald-400 pulse-dot"></span> Canlı
          </span>
        </div>
        <p id="pod-hostname" class="text-sm font-mono font-bold text-white mt-2 truncate">yükleniyor...</p>
        <p class="text-xs text-slate-500 mt-1">Namespace: <span class="text-slate-300 font-mono">app</span> (vm-worker-app)</p>
      </div>

      <!-- PostgreSQL Durumu -->
      <div class="glass-card rounded-xl p-4">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-slate-400">PostgreSQL 16 (Data)</span>
          <span id="badge-postgres" class="text-xs font-mono font-semibold px-2 py-0.5 rounded bg-slate-800 text-slate-300">...</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-2">
          <span id="latency-postgres" class="text-lg font-bold text-white">- ms</span>
          <span class="text-xs text-slate-500">sorgu gecikmesi</span>
        </div>
        <p class="text-xs text-slate-500 mt-1">Stateful ACID İşlem Tablosu</p>
      </div>

      <!-- Redis Durumu -->
      <div class="glass-card rounded-xl p-4">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-slate-400">Redis Cache (Data)</span>
          <span id="badge-redis" class="text-xs font-mono font-semibold px-2 py-0.5 rounded bg-slate-800 text-slate-300">...</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-2">
          <span id="latency-redis" class="text-lg font-bold text-white">- ms</span>
          <span class="text-xs text-slate-500">önbellek PING süresi</span>
        </div>
        <p class="text-xs text-slate-500 mt-1">İdempotency & Metrik Önbelleği</p>
      </div>

      <!-- Harbor OCI Durumu -->
      <div class="glass-card rounded-xl p-4">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-slate-400">Harbor + Trivy Gate</span>
          <span id="badge-harbor" class="text-xs font-mono font-semibold px-2 py-0.5 rounded bg-slate-800 text-slate-300">...</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-2">
          <span id="latency-harbor" class="text-lg font-bold text-white">- ms</span>
          <span class="text-xs text-slate-500">v2.0 REST API yanıtı</span>
        </div>
        <p class="text-xs text-slate-500 mt-1">SecOps İmaj & CVE Doğrulama</p>
      </div>
    </div>

    <!-- İKİ KOLONLU İNTERAKTİF FORMLAR -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">

      <!-- FORM 1: OCI KONTEYNER ARTEFAKT DOĞRULAMA -->
      <div class="glass-card rounded-xl p-5 space-y-4">
        <div class="flex items-center space-x-2 pb-2 border-b border-slate-800">
          <span class="text-xl">🔍</span>
          <div>
            <h2 class="text-base font-bold text-white">Konteyner İmaj & CVE Güvenlik Kapısı</h2>
            <p class="text-xs text-slate-400">Harbor Trivy tarama sonuçlarını sisteme kaydeder (<code class="text-emerald-400">POST /api/artifacts/verify</code>)</p>
          </div>
        </div>

        <form id="form-verify-artifact" class="space-y-3 text-xs">
          <div>
            <label class="block text-slate-400 mb-1">Harbor İmajı & Etiketi (Image FQDN):</label>
            <input type="text" id="art-image" required
              value="harbor.MASTER_IP.nip.io/supplyshield/supplyshield-api:1.0.0"
              class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 font-mono focus:border-cyan-500 focus:outline-none">
          </div>
          <div>
            <label class="block text-slate-400 mb-1">OCI SHA256 Digest:</label>
            <input type="text" id="art-digest" required
              value="sha256:7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069"
              class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 font-mono text-[11px] focus:border-cyan-500 focus:outline-none">
          </div>
          <div class="grid grid-cols-3 gap-2">
            <div>
              <label class="block text-slate-400 mb-1">Trivy Durumu:</label>
              <select id="art-status" class="w-full bg-slate-900 border border-slate-700 rounded-lg px-2.5 py-2 text-slate-200 focus:border-cyan-500 focus:outline-none">
                <option value="PASSED" selected>PASSED (Temiz)</option>
                <option value="WARN">WARN (Düşük CVE)</option>
                <option value="BLOCKED">BLOCKED (Kritik)</option>
              </select>
            </div>
            <div>
              <label class="block text-slate-400 mb-1">Critical CVEs:</label>
              <input type="number" id="art-crit" min="0" value="0" class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 focus:border-cyan-500 focus:outline-none">
            </div>
            <div>
              <label class="block text-slate-400 mb-1">Jenkins Build #:</label>
              <input type="text" id="art-build" value="1" class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 focus:border-cyan-500 focus:outline-none">
            </div>
          </div>

          <button type="submit" class="w-full bg-cyan-600 hover:bg-cyan-500 text-white font-semibold py-2.5 px-4 rounded-lg transition flex items-center justify-center space-x-2">
            <span>🛡️ İmajı Doğrula & Veritabanına Kaydet</span>
          </button>
        </form>

        <div id="alert-artifact" class="hidden text-xs p-3 rounded-lg border"></div>
      </div>

      <!-- FORM 2: YAZILIM TEDARİK & LİSANS SİPARİŞİ -->
      <div class="glass-card rounded-xl p-5 space-y-4">
        <div class="flex items-center space-x-2 pb-2 border-b border-slate-800">
          <span class="text-xl">💳</span>
          <div>
            <h2 class="text-base font-bold text-white">Yazılım Tedarik & Lisans Siparişi</h2>
            <p class="text-xs text-slate-400">PostgreSQL veri defterine güvenli lisans kaydı oluşturur (<code class="text-emerald-400">POST /api/orders</code>)</p>
          </div>
        </div>

        <form id="form-create-order" class="space-y-3 text-xs">
          <div>
            <label class="block text-slate-400 mb-1">Birim / Müşteri ID:</label>
            <input type="text" id="ord-customer" required
              value="secops-platform-core"
              class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 focus:border-emerald-500 focus:outline-none">
          </div>
          <div>
            <label class="block text-slate-400 mb-1">Yazılım Paketi / Servis Adı:</label>
            <input type="text" id="ord-package" required
              value="supplyshield-enterprise-scanner"
              class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 focus:border-emerald-500 focus:outline-none">
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="block text-slate-400 mb-1">Lisans Adedi:</label>
              <input type="number" id="ord-qty" min="1" value="2" class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 focus:border-emerald-500 focus:outline-none">
            </div>
            <div>
              <label class="block text-slate-400 mb-1">Toplam Tutar ($ USD):</label>
              <input type="number" step="0.01" id="ord-amount" value="499.80" class="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 focus:border-emerald-500 focus:outline-none">
            </div>
          </div>

          <button type="submit" class="w-full bg-emerald-600 hover:bg-emerald-500 text-white font-semibold py-2.5 px-4 rounded-lg transition flex items-center justify-center space-x-2">
            <span>✨ Lisans Siparişini Onayla & Yaz</span>
          </button>
        </form>

        <div id="alert-order" class="hidden text-xs p-3 rounded-lg border"></div>
      </div>

    </div>

    <!-- TABLOLAR: SON DOĞRULANAN İMAJLAR VE SİPARİŞLER -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">

      <!-- Artefakt Listesi -->
      <div class="glass-card rounded-xl p-5 space-y-3">
        <div class="flex items-center justify-between border-b border-slate-800 pb-2">
          <h3 class="text-sm font-bold text-white flex items-center gap-2">
            <span>📋</span> Doğrulanan OCI Konteyner İmajları
          </h3>
          <button onclick="loadArtifacts()" class="text-xs text-cyan-400 hover:underline">Yenile</button>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs">
            <thead class="text-slate-400 border-b border-slate-800">
              <tr>
                <th class="py-2">İmaj / Digest</th>
                <th class="py-2">Trivy Durumu</th>
                <th class="py-2">Kritik CVE</th>
                <th class="py-2">Build #</th>
              </tr>
            </thead>
            <tbody id="table-artifacts" class="divide-y divide-slate-800 text-slate-300">
              <tr><td colspan="4" class="py-4 text-center text-slate-500">Kayıtlar yükleniyor...</td></tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Sipariş Listesi -->
      <div class="glass-card rounded-xl p-5 space-y-3">
        <div class="flex items-center justify-between border-b border-slate-800 pb-2">
          <h3 class="text-sm font-bold text-white flex items-center gap-2">
            <span>🧾</span> Kayıtlı Yazılım Tedarik Siparişleri
          </h3>
          <button onclick="loadOrders()" class="text-xs text-emerald-400 hover:underline">Yenile</button>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs">
            <thead class="text-slate-400 border-b border-slate-800">
              <tr>
                <th class="py-2">Müşteri</th>
                <th class="py-2">Paket</th>
                <th class="py-2">Adet</th>
                <th class="py-2">Tutar</th>
              </tr>
            </thead>
            <tbody id="table-orders" class="divide-y divide-slate-800 text-slate-300">
              <tr><td colspan="4" class="py-4 text-center text-slate-500">Kayıtlar yükleniyor...</td></tr>
            </tbody>
          </table>
        </div>
      </div>

    </div>

  </main>

  <!-- ALT BİLGİ -->
  <footer class="border-t border-slate-800 bg-slate-900/60 py-4 mt-8 text-center text-xs text-slate-500">
    <p>SupplyShield v1.0.0 — RKE2 High-Isolation Architecture (Master 8GB / App 4GB / SecOps 4GB)</p>
  </footer>

  <script>
    // Dinamik IP Tespiti ile Linkleri Güncelle
    const host = window.location.hostname;
    const parts = host.split('.');
    let masterIp = "9.205.89.163";
    if (parts.length >= 6 && parts[parts.length-2] === 'nip' && parts[parts.length-1] === 'io') {
      masterIp = parts.slice(parts.length-6, parts.length-2).join('.');
    }

    document.getElementById('link-harbor').href = `http://harbor.${masterIp}.nip.io`;
    document.getElementById('link-jenkins').href = `http://jenkins.${masterIp}.nip.io`;
    document.getElementById('link-argocd').href = `https://argocd.${masterIp}.nip.io`;
    document.getElementById('link-grafana').href = `http://grafana.${masterIp}.nip.io`;

    // Sistem Durumunu Çek
    async function fetchSystemStatus() {
      try {
        const res = await fetch('/', { headers: { 'Accept': 'application/json' } });
        if (!res.ok) return;
        const data = await res.json();
        document.getElementById('pod-hostname').innerText = data.pod || "unknown";

        const deps = data.dependencies || {};
        updateBadge('postgres', deps.postgres);
        updateBadge('redis', deps.redis);
        updateBadge('harbor', deps.harbor);
      } catch (e) {
        console.error("Durum çekilemedi", e);
      }
    }

    function updateBadge(name, info) {
      const badge = document.getElementById(`badge-${name}`);
      const latency = document.getElementById(`latency-${name}`);
      if (!info) return;

      if (info.status === 'HEALTHY' || info.status === 'UP' || info.status === 'CONNECTED') {
        badge.innerText = "HEALTHY";
        badge.className = "text-xs font-mono font-semibold px-2 py-0.5 rounded bg-emerald-950 text-emerald-400 border border-emerald-800/50";
      } else {
        badge.innerText = info.status || "DOWN";
        badge.className = "text-xs font-mono font-semibold px-2 py-0.5 rounded bg-red-950 text-red-400 border border-red-800/50";
      }
      latency.innerText = `${info.latency_ms || 0} ms`;
    }

    // Artefaktları Listele
    async function loadArtifacts() {
      const tbody = document.getElementById('table-artifacts');
      try {
        const res = await fetch('/api/artifacts');
        if (!res.ok) throw new Error("HTTP " + res.status);
        const list = await res.json();
        if (!list || list.length === 0) {
          tbody.innerHTML = '<tr><td colspan="4" class="py-4 text-center text-slate-500">Henüz doğrulanmış artefakt yok.</td></tr>';
          return;
        }
        tbody.innerHTML = list.slice(0, 5).map(item => `
          <tr>
            <td class="py-2.5">
              <div class="font-medium text-white truncate max-w-xs">${item.image_name}</div>
              <div class="text-[10px] font-mono text-slate-500 truncate max-w-xs">${item.digest}</div>
            </td>
            <td class="py-2.5">
              <span class="px-2 py-0.5 rounded text-[10px] font-bold ${item.trivy_status === 'PASSED' ? 'bg-emerald-950 text-emerald-400 border border-emerald-800' : 'bg-red-950 text-red-400 border border-red-800'}">
                ${item.trivy_status}
              </span>
            </td>
            <td class="py-2.5 text-center font-mono ${item.critical_cves > 0 ? 'text-red-400 font-bold' : 'text-slate-400'}">${item.critical_cves}</td>
            <td class="py-2.5 text-slate-400 font-mono">#${item.build_number}</td>
          </tr>
        `).join('');
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="4" class="py-4 text-center text-red-400">Veriler çekilemedi.</td></tr>';
      }
    }

    // Siparişleri Listele
    async function loadOrders() {
      const tbody = document.getElementById('table-orders');
      try {
        const res = await fetch('/api/orders');
        if (!res.ok) throw new Error("HTTP " + res.status);
        const list = await res.json();
        if (!list || list.length === 0) {
          tbody.innerHTML = '<tr><td colspan="4" class="py-4 text-center text-slate-500">Henüz kayıtlı sipariş yok.</td></tr>';
          return;
        }
        tbody.innerHTML = list.slice(0, 5).map(item => `
          <tr>
            <td class="py-2.5 font-medium text-white">${item.customer_id}</td>
            <td class="py-2.5 text-slate-300 truncate max-w-[150px]">${item.package_name}</td>
            <td class="py-2.5 font-mono text-slate-400">${item.quantity}</td>
            <td class="py-2.5 font-mono text-emerald-400 font-bold">$${parseFloat(item.amount).toFixed(2)}</td>
          </tr>
        `).join('');
      } catch (e) {
        tbody.innerHTML = '<tr><td colspan="4" class="py-4 text-center text-red-400">Veriler çekilemedi.</td></tr>';
      }
    }

    // Form 1 Submit
    document.getElementById('form-verify-artifact').addEventListener('submit', async (e) => {
      e.preventDefault();
      const alert = document.getElementById('alert-artifact');
      alert.className = "text-xs p-3 rounded-lg border bg-slate-900 text-slate-300 border-slate-700 block";
      alert.innerText = "Doğrulanıyor...";

      try {
        const payload = {
          image_name: document.getElementById('art-image').value,
          digest: document.getElementById('art-digest').value,
          trivy_status: document.getElementById('art-status').value,
          critical_cves: parseInt(document.getElementById('art-crit').value) || 0,
          high_cves: 0,
          build_number: document.getElementById('art-build').value,
        };
        const res = await fetch('/api/artifacts/verify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (res.ok) {
          alert.className = "text-xs p-3 rounded-lg border bg-emerald-950/80 text-emerald-300 border-emerald-700 block";
          alert.innerText = `✅ Başarılı! Artefakt Doğrulandı. ID: ${data.id || data.record?.id || 'OK'}`;
          loadArtifacts();
        } else {
          alert.className = "text-xs p-3 rounded-lg border bg-red-950/80 text-red-300 border-red-700 block";
          alert.innerText = `❌ Hata: ${data.detail || JSON.stringify(data)}`;
        }
      } catch (err) {
        alert.className = "text-xs p-3 rounded-lg border bg-red-950/80 text-red-300 border-red-700 block";
        alert.innerText = `❌ İstek başarısız: ${err.message}`;
      }
    });

    // Form 2 Submit
    document.getElementById('form-create-order').addEventListener('submit', async (e) => {
      e.preventDefault();
      const alert = document.getElementById('alert-order');
      alert.className = "text-xs p-3 rounded-lg border bg-slate-900 text-slate-300 border-slate-700 block";
      alert.innerText = "Sipariş işleniyor...";

      try {
        const payload = {
          customer_id: document.getElementById('ord-customer').value,
          package_name: document.getElementById('ord-package').value,
          quantity: parseInt(document.getElementById('ord-qty').value) || 1,
          amount: parseFloat(document.getElementById('ord-amount').value) || 0,
        };
        const res = await fetch('/api/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (res.ok) {
          alert.className = "text-xs p-3 rounded-lg border bg-emerald-950/80 text-emerald-300 border-emerald-700 block";
          alert.innerText = `✅ Başarılı! Sipariş kaydedildi. Sipariş ID: ${data.order_id || 'OK'}`;
          loadOrders();
        } else {
          alert.className = "text-xs p-3 rounded-lg border bg-red-950/80 text-red-300 border-red-700 block";
          alert.innerText = `❌ Hata: ${data.detail || JSON.stringify(data)}`;
        }
      } catch (err) {
        alert.className = "text-xs p-3 rounded-lg border bg-red-950/80 text-red-300 border-red-700 block";
        alert.innerText = `❌ İstek başarısız: ${err.message}`;
      }
    });

    // Sayfa Yüklendiğinde
    fetchSystemStatus();
    loadArtifacts();
    loadOrders();
    setInterval(fetchSystemStatus, 4000);
  </script>
</body>
</html>
"""
