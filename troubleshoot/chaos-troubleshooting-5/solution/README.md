# 🛠️ Chaos Troubleshooting Lab 5: Solutions & Post-Mortem

> **[🇬🇧 English](#-english-summary) | [🇹🇷 Türkçe](#-türkçe-özet)**

This directory provides the authoritative root cause analysis (RCA), diagnostic commands, and remediation configurations for **Chaos Troubleshooting Lab 5 (QuantumPay Core)**.

Please refer to the comprehensive root-level solution document:
👉 **[SOLUTION.md (Full English & Turkish Post-Mortem Guide)](../SOLUTION.md)**

---

## 🇬🇧 English Summary

- **T1: Packet Corrupt & Reorder (TCP Retransmit Flood):** Fixed by setting `gateway.downstreamTimeout: 3` and adding socket timeouts.
- **T2: Filesystem EIO Fault (Storage I/O Error):** Fixed by enabling `engine.circuitBreaker.enabled: true` with graceful fallback to read-only mode and 503 Retry-After.
- **T3: Ingress Drain Race Condition:** Fixed by configuring `gateway.preStopEnabled: true` (`sleep 5`) and `terminationGracePeriodSeconds: 30`.
- **T4: Poison Pill & Kafka Rebalance Storm:** Fixed by enabling Dead Letter Queue with `consumer.dlqEnabled: true` and `maxRetries: 3`.
- **T5: Cgroup v2 OOM Killer (ExitCode 137):** Fixed by setting `analytics.enableMemoryTargetLimit: true` and tuning GC limit to 75% of container memory (`192MiB`).
- **T6: Slowloris & Idle Connection Starvation:** Fixed by configuring `gateway.readHeaderTimeout: 2` and `gateway.idleTimeout: 5`.

---

## 🇹🇷 Türkçe Özet

- **T1: Paket Bozulması ve Sıra Kayması (TCP Soket Sızıntısı):** `gateway.downstreamTimeout: 3` ayarlanarak sonsuz beklemelerin önüne geçildi.
- **T2: Dosya Sistemi EIO Hatası (WAL Diski Çöküşü):** `engine.circuitBreaker.enabled: true` yapılarak disk çöktüğünde devre kesici devreye sokuldu ve 503 Retry-After ile zarif düşüş sağlandı.
- **T3: Ingress Drain Yarış Durumu (502 Bad Gateway):** `gateway.preStopEnabled: true` (`sleep 5`) ve `terminationGracePeriodSeconds: 30` ile sıfır kesintili güncelleme sağlandı.
- **T4: Zehirli Mesaj (Poison Pill) ve Rebalance Fırtınası:** `consumer.dlqEnabled: true` ve `maxRetries: 3` ile bozuk mesajlar DLQ'ya aktarıldı.
- **T5: Cgroup v2 OOM Killer (ExitCode 137):** `analytics.enableMemoryTargetLimit: true` ve hedef bellek `192MiB` yapılarak kernel OOM katliamı engellendi.
- **T6: Slowloris ve Askıda Kalan Bağlantılar:** `gateway.readHeaderTimeout: 2` ve `gateway.idleTimeout: 5` ile yavaş bağlantıların soketleri tüketmesi engellendi.

Ayrıntılı adım adım çözümler, diff'ler ve SRE post-mortem analizi için:
👉 **[SOLUTION.md Dosyasını İnceleyin](../SOLUTION.md)**
