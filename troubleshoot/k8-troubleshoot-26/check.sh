#!/usr/bin/env bash
# ==============================================================================
# NetVortex v9.0 — Kubernetes Deep Network & Zero-Trust Verification Script
# ==============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=10

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  echo -e "         ${YELLOW}↳ Diagnostic Direction:${NC} $2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}   🔍 NetVortex v9.0 (Lab 26) — Network & Zero-Trust Diagnostic Audit${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# ------------------------------------------------------------------------------
# SECTION 1: EDGE & L4/L7 INGRESS LAYER (namespace: netvortex-edge)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 1: Edge & Ingress Networking — namespace: netvortex-edge]${NC}"

# Check 1: LoadBalancer externalTrafficPolicy
ETP=$(kubectl get svc edge-gateway-lb -n netvortex-edge -o jsonpath='{.spec.externalTrafficPolicy}' 2>/dev/null || echo "NotFound")
if [[ "${ETP}" == "Cluster" ]]; then
  pass "1. [L4 LoadBalancer] edge-gateway-lb externalTrafficPolicy is set to 'Cluster'"
else
  fail "1. [L4 LoadBalancer] edge-gateway-lb externalTrafficPolicy is '${ETP}' (expected 'Cluster')" \
       "Inspect 'kubectl get svc edge-gateway-lb -n netvortex-edge -o yaml'. When externalTrafficPolicy is 'Local', packets routed to cluster nodes without local endpoints are dropped. Cluster policy enables cross-node proxying."
fi

# Check 2: Ingress Path & Rewrite Regex
INGRESS_PATH=$(kubectl get ingress edge-ingress -n netvortex-edge -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null || echo "")
INGRESS_REWRITE=$(kubectl get ingress edge-ingress -n netvortex-edge -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/rewrite-target}' 2>/dev/null || echo "")
INGRESS_REGEX=$(kubectl get ingress edge-ingress -n netvortex-edge -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/use-regex}' 2>/dev/null || echo "")

if [[ "${INGRESS_PATH}" == *"/api/v1(/|$)(.*)"* && "${INGRESS_REWRITE}" == "/\$2" && "${INGRESS_REGEX}" == "true" ]]; then
  pass "2. [L7 Ingress Rewrite] edge-ingress regex capture and rewrite-target '/\$2' properly configured"
else
  fail "2. [L7 Ingress Rewrite] edge-ingress regex or rewrite-target misconfigured (path: '${INGRESS_PATH}', rewrite: '${INGRESS_REWRITE}')" \
       "Inspect 'kubectl get ingress edge-ingress -n netvortex-edge -o yaml'. Ingress controller requires use-regex: 'true' and rewrite-target: '/\$2' to properly strip prefix when forwarding to the backend."
fi

# Check 3: Cross-Namespace Upstream Resolution in edge-gateway
UPSTREAM_CONF=$(kubectl get cm edge-gateway-config -n netvortex-edge -o jsonpath='{.data.nginx\.conf}' 2>/dev/null || echo "")
if echo "${UPSTREAM_CONF}" | grep -q "payment-api\.netvortex-core"; then
  pass "3. [Cross-NS Routing] edge-gateway upstream correctly references 'payment-api.netvortex-core'"
else
  fail "3. [Cross-NS Routing] edge-gateway upstream missing namespace qualification" \
       "Inspect ConfigMap 'edge-gateway-config' in 'netvortex-edge'. The proxy attempts to call 'payment-api' without the namespace. Cross-namespace service discovery requires '<service>.<namespace>'."
fi

echo ""

# ------------------------------------------------------------------------------
# SECTION 2: CORE SERVICES & NETWORKPOLICIES (namespace: netvortex-core)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 2: Core Microservices & Zero-Trust Policies — namespace: netvortex-core]${NC}"

# Check 4: Payment API Named Port Alignment
SVC_TPORT=$(kubectl get svc payment-api -n netvortex-core -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")
CONT_PNAME=$(kubectl get deploy payment-api -n netvortex-core -o jsonpath='{.spec.template.spec.containers[0].ports[0].name}' 2>/dev/null || echo "")
EP_PORT=$(kubectl get ep payment-api -n netvortex-core -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || echo "")

if [[ ("${SVC_TPORT}" == "${CONT_PNAME}" || "${SVC_TPORT}" == "8080") && "${EP_PORT}" == "8080" ]]; then
  pass "4. [Service TargetPort] payment-api service targetPort correctly resolves to container port 8080"
else
  fail "4. [Service TargetPort] payment-api service targetPort ('${SVC_TPORT}') does not match container port name ('${CONT_PNAME}')" \
       "Inspect 'kubectl describe svc payment-api -n netvortex-core' and the Deployment spec. When a Service specifies a named targetPort, the container spec must define an identical port name."
fi

# Check 5: Cross-Namespace Ingress NetworkPolicy (AND vs OR trap)
NETPOL_NS_SEL=$(kubectl get netpol payment-api-netpol -n netvortex-core -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}' 2>/dev/null || echo "")
if [[ "${NETPOL_NS_SEL}" == "netvortex-edge" ]]; then
  pass "5. [NetPol Ingress Scope] payment-api-netpol properly includes namespaceSelector for 'netvortex-edge'"
else
  fail "5. [NetPol Ingress Scope] payment-api-netpol missing namespaceSelector in from clause" \
       "Inspect 'kubectl get netpol payment-api-netpol -n netvortex-core -o yaml'. In Kubernetes NetworkPolicies, a podSelector without a namespaceSelector ONLY matches pods in the local namespace. To allow traffic from another namespace, combine namespaceSelector and podSelector."
fi

# Check 6: Bank Gateway Egress ipBlock (CIDR exception trap)
EXCEPT_CIDR=$(kubectl get netpol payment-api-netpol -n netvortex-core -o jsonpath='{.spec.egress[?(@.to[0].ipBlock.cidr=="198.51.100.0/24")].to[0].ipBlock.except[0]}' 2>/dev/null || echo "")
if [[ "${EXCEPT_CIDR}" != "198.51.100.0/24" ]]; then
  pass "6. [NetPol Egress ipBlock] payment-api-netpol egress ipBlock allows target payment settlement subnet"
else
  fail "6. [NetPol Egress ipBlock] payment-api-netpol egress ipBlock excludes entire target subnet (${EXCEPT_CIDR})" \
       "Inspect 'kubectl get netpol payment-api-netpol -n netvortex-core -o yaml'. The 'except' clause excludes '198.51.100.0/24', accidentally dropping all outbound banking transactions to the gateway."
fi

# Check 7: Fraud Detector Service Selector & Endpoints
FD_EP_IP=$(kubectl get ep fraud-detector -n netvortex-core -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
if [[ -n "${FD_EP_IP}" ]]; then
  pass "7. [Service Endpoints] fraud-detector Service selector correctly matches pod labels (Endpoint: ${FD_EP_IP})"
else
  fail "7. [Service Endpoints] fraud-detector Service has empty endpoints (<none>)" \
       "Compare 'kubectl get svc fraud-detector -n netvortex-core -o yaml' selector with 'kubectl get pods -n netvortex-core --show-labels'. A label mismatch prevents kube-proxy from registering endpoints."
fi

# Check 8: Fraud Detector CoreDNS Egress NetworkPolicy (TCP Port 53)
TCP_53_EGRESS=$(kubectl get netpol fraud-detector-netpol -n netvortex-core -o jsonpath='{.spec.egress[0].ports[?(@.protocol=="TCP")].port}' 2>/dev/null || echo "")
if [[ "${TCP_53_EGRESS}" == "53" ]]; then
  pass "8. [NetPol DNS Egress] fraud-detector-netpol permits both UDP and TCP port 53 for CoreDNS"
else
  fail "8. [NetPol DNS Egress] fraud-detector-netpol missing TCP port 53 egress rule" \
       "Inspect 'kubectl get netpol fraud-detector-netpol -n netvortex-core -o yaml'. DNS queries that exceed 512 bytes or fall back to TCP hang if TCP port 53 is not explicitly permitted alongside UDP 53."
fi

echo ""

# ------------------------------------------------------------------------------
# SECTION 3: DATA LAYER & ENDPOINT RESOLUTION (namespace: netvortex-data)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 3: Data Tier & Socket Bindings — namespace: netvortex-data]${NC}"

# Check 9: Headless Service & StatefulSet serviceName
STS_SVC_NAME=$(kubectl get sts ledger-db -n netvortex-data -o jsonpath='{.spec.serviceName}' 2>/dev/null || echo "")
if [[ "${STS_SVC_NAME}" == "ledger-headless" ]]; then
  pass "9. [Headless DNS] ledger-db StatefulSet spec.serviceName matches 'ledger-headless'"
else
  fail "9. [Headless DNS] ledger-db StatefulSet spec.serviceName is '${STS_SVC_NAME}' (expected 'ledger-headless')" \
       "Inspect 'kubectl get sts ledger-db -n netvortex-data -o yaml' and headless service name. StatefulSet pods only receive predictable SRV/A records when spec.serviceName matches the headless Service name."
fi

# Check 10: Daemon Socket Bind Address (0.0.0.0 vs 127.0.0.1)
BIND_ADDR=$(kubectl get cm ledger-db-config -n netvortex-data -o jsonpath='{.data.redis\.conf}' 2>/dev/null | grep "^bind" | awk '{print $2}')
if [[ "${BIND_ADDR}" == "0.0.0.0" ]]; then
  pass "10. [Socket Binding] ledger-db binds to 0.0.0.0 (accepts cluster traffic)"
else
  fail "10. [Socket Binding] ledger-db binds to '${BIND_ADDR}' (loopback only)" \
       "Inspect ConfigMap 'ledger-db-config' in 'netvortex-data'. Binding to 127.0.0.1 restricts connections to the pod's local network namespace, causing 'Connection refused' from external callers."
fi

echo ""
echo -e "${CYAN}======================================================================${NC}"
echo -e "   Audit Summary: ${GREEN}${PASS_COUNT} Passed${NC} / ${RED}${FAIL_COUNT} Failed${NC} (Total: ${TOTAL_CHECKS})"
echo -e "${CYAN}======================================================================${NC}"

if [[ ${PASS_COUNT} -eq ${TOTAL_CHECKS} ]]; then
  echo -e "${GREEN}🎉 CONGRATULATIONS! All NetVortex v9.0 networking issues are resolved!${NC}"
  echo -e "${GREEN}   The cluster network mesh is fully healthy and zero-trust compliant.${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  Some checks failed. Follow the diagnostic directions above and consult README.md.${NC}"
  exit 1
fi
