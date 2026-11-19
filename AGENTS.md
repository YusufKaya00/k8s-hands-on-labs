# Kubernetes Hands-On Labs — Authoring Rules

Follow these mandatory rules whenever creating or updating labs, projects, or lessons in this repository (`/home/ysf/k8s-hands-on-labs`).

## 1. Ingress & Traffic Architecture
- **Use Direct Ingress by default (`Ingress -> Service -> Pod`):** Do NOT deploy an extra custom NGINX `edge-proxy` reverse proxy pod between `ingress-nginx-controller` and backend services unless the user explicitly asks for an internal reverse proxy or API Gateway scenario.
- Route endpoints directly via Kubernetes `Ingress` objects in each service's namespace (sharing the same `host` with distinct paths so `ingress-nginx` merges them cleanly).
- Build cross-namespace networking scenarios (`CoreDNS`, `NetworkPolicy`, `ExternalName`, `Headless StatefulSet`) through real backend-to-backend service calls rather than an artificial `edge-proxy`.
- **No obscure NGINX regex/rewrite-target puzzles:** Do NOT design Ingress defects around cryptic regex capture groups such as `path: "/v2/catalog(/|$)(.*)"`, `pathType: ImplementationSpecific`, `use-regex: "true"`, and `rewrite-target: "/$2"`.
- Focus Ingress troubleshooting strictly on realistic production issues: `pathType: Prefix` vs `Exact`, `ingressClassName`, `host`, `backend.service` name/port, `proxy-body-size`, `proxy-read-timeout`, `backend-protocol`, and TLS/redirect annotations.

## 2. Troubleshooting Lab Standards (`troubleshoot/`)
- **Blind Mode & Zero-Spoiler:** For daily warm-up / general review labs, keep Helm templates, `values.yaml`, `README.md`, and default `./check.sh` output 100% free of spoiler comments or root-cause hints. Put hints behind `./check.sh --hints` and full RCA exclusively in `SOLUTION.md`.
- **Always ship `broken-manifests/`:** Every new `k8-troubleshoot-XX` lab must include `broken-manifests/` (`setup-broken.sh`, `values-broken.yaml`, and `broken-manifests/helm/<chart>/...`) from Day 1 so the lab can always be reset to its exact initial broken state after solving.
- **Zero-Cheat Verification:** In `./check.sh`, verify that security/governance constraints (`NetworkPolicy`, `LimitRange`, `ResourceQuota`, node `Taint`, `runAsNonRoot`, `readOnlyRootFilesystem`) remain enforced rather than deleted.
- **Keep root `README.md` in sync:** Whenever adding a new lab, update the directory tree, English section, Turkish section, and counts in `/home/ysf/k8s-hands-on-labs/README.md`.

## 3. Documentation & Lessons Standards (`lessons/`, `projects/`, `troubleshoot/`)
- **Bilingual READMEs:** Every `README.md` across root, `lessons/`, `projects/`, and `troubleshoot/` must include both Turkish (`🇹🇷 Türkçe`) and English (`🇬🇧 English`) sections.
- **Lessons Isolation:** Daily general review / warm-up labs belong under `troubleshoot/k8-troubleshoot-XX/`. Topic-specific study modules belong under `lessons/<topic>/` with their specific labs (`lab-1/`, `lab-2/`) inside that lesson's folder. Do not add empty boilerplate sections like `Kendi Çalışma Notlarım` or `Günlük Uygulama Rutini`.
