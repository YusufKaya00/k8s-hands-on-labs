#!/usr/bin/env bash
# ==============================================================================
# CloudApex v10.0 — Enterprise Kubernetes Networking & Cloud LoadBalancer Audit
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
echo -e "${CYAN}   🔍 CloudApex v10.0 (Lab 27) — Enterprise Network Diagnostic Audit  ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# ------------------------------------------------------------------------------
# SECTION 1: CLOUD LOADBALANCER & INGRESS GATEWAYS (namespace: cloudapex-edge)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 1: External Cloud LoadBalancers & Ingress Routing — namespace: cloudapex-edge]${NC}"

# Check 1: Azure LB Health Probe Annotation
LB_PROBE=$(kubectl get svc order-gateway-lb -n cloudapex-edge -o jsonpath='{.metadata.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path}' 2>/dev/null || echo "")
if [[ "${LB_PROBE}" == "/api/health" ]]; then
  pass "1. [Azure LoadBalancer Probe] order-gateway-lb probe path matches application health endpoint ('/api/health')"
else
  fail "1. [Azure LoadBalancer Probe] order-gateway-lb probe path is '${LB_PROBE}' (expected '/api/health')" \
       "Inspect 'kubectl get svc order-gateway-lb -n cloudapex-edge -o yaml' annotations vs container logs. When Azure LB probes '/healthz', the app returns 404, causing Azure to mark all node probes as down and reject external public IP traffic."
fi

# Check 2: Ingress Orders PathType (Prefix vs Exact)
ORDERS_PATHTYPE=$(kubectl get ingress cloudapex-ingress -n cloudapex-edge -o jsonpath='{.spec.rules[0].http.paths[?(@.path=="/api/orders")].pathType}' 2>/dev/null || echo "")
if [[ "${ORDERS_PATHTYPE}" == "Prefix" ]]; then
  pass "2. [L7 Ingress Routing] cloudapex-ingress /api/orders pathType is 'Prefix' (routes sub-paths cleanly)"
else
  fail "2. [L7 Ingress Routing] cloudapex-ingress /api/orders pathType is '${ORDERS_PATHTYPE}' (expected 'Prefix')" \
       "Inspect 'kubectl get ingress cloudapex-ingress -n cloudapex-edge -o yaml'. When set to 'Exact', requests to sub-paths like '/api/orders/checkout' do not match the rule and return 404."
fi

# Check 3: Ingress L7 Cookie Sticky Session
INGRESS_AFFINITY=$(kubectl get ingress cloudapex-ingress -n cloudapex-edge -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/affinity}' 2>/dev/null || echo "")
if [[ "${INGRESS_AFFINITY}" == "cookie" ]]; then
  pass "3. [L7 Session Affinity] cloudapex-ingress manages session stickiness via cookie-based routing"
else
  fail "3. [L7 Session Affinity] cloudapex-ingress missing cookie-based affinity annotation" \
       "Inspect 'kubectl get ingress cloudapex-ingress -n cloudapex-edge -o yaml'. In modern Ingress meshes, session stickiness must be handled at L7 using 'nginx.ingress.kubernetes.io/affinity: cookie' rather than L4 ClientIP."
fi

echo ""

# ------------------------------------------------------------------------------
# SECTION 2: CORE MICROSERVICES & ZERO-TRUST MESH (namespace: cloudapex-core)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 2: Core Microservices & Zero-Trust Policies — namespace: cloudapex-core]${NC}"

# Check 4: Service L4 SessionAffinity (No Hotspotting)
SVC_AFFINITY=$(kubectl get svc order-service -n cloudapex-core -o jsonpath='{.spec.sessionAffinity}' 2>/dev/null || echo "")
if [[ "${SVC_AFFINITY}" == "None" ]]; then
  pass "4. [L4 Load Balancing] order-service sessionAffinity is 'None' (eliminates proxy hotspotting)"
else
  fail "4. [L4 Load Balancing] order-service sessionAffinity is '${SVC_AFFINITY}' (expected 'None')" \
       "Inspect 'kubectl get svc order-service -n cloudapex-core -o yaml'. When 'sessionAffinity: ClientIP' is enabled on a Service behind Ingress, all clients arriving via Ingress share the same IP, causing 100% traffic skew to a single pod."
fi

# Check 5: Calico Egress to Cloud IMDS (169.254.169.254/32)
IMDS_EGRESS=$(kubectl get netpol order-service-netpol -n cloudapex-core -o jsonpath='{.spec.egress[?(@.to[0].ipBlock.cidr=="169.254.169.254/32")].to[0].ipBlock.cidr}' 2>/dev/null || echo "")
if [[ "${IMDS_EGRESS}" == "169.254.169.254/32" ]]; then
  pass "5. [Cloud IMDS Egress] order-service-netpol permits egress to Azure IMDS ('169.254.169.254/32')"
else
  fail "5. [Cloud IMDS Egress] order-service-netpol blocks link-local IMDS ('169.254.169.254/32')" \
       "Inspect 'kubectl get netpol order-service-netpol -n cloudapex-core -o yaml'. Pods requiring Azure Managed Identity tokens must have link-local IP 169.254.169.254/32 explicitly permitted in egress rules."
fi

# Check 6: CoreDNS ndots Query Optimization
NDOTS_VAL=$(kubectl get deploy order-service -n cloudapex-core -o jsonpath='{.spec.template.spec.dnsConfig.options[?(@.name=="ndots")].value}' 2>/dev/null || echo "5")
if [[ "${NDOTS_VAL}" == "2" || "${NDOTS_VAL}" == "1" ]]; then
  pass "6. [CoreDNS Optimization] order-service configures ndots=${NDOTS_VAL} (eliminates search domain latency)"
else
  fail "6. [CoreDNS Optimization] order-service dnsConfig ndots is '${NDOTS_VAL}' (expected <= 2)" \
       "Inspect 'kubectl get deploy order-service -n cloudapex-core -o yaml'. In Kubernetes, default ndots: 5 generates 4 failed local search domain queries for external FQDNs (like api.stripe.com), degrading CoreDNS performance."
fi

# Check 7: Auth Service Socket Binding (0.0.0.0 vs 127.0.0.1)
AUTH_BIND=$(kubectl get deploy auth-service -n cloudapex-core -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="BIND_ADDRESS")].value}' 2>/dev/null || echo "")
if [[ "${AUTH_BIND}" == "0.0.0.0" ]]; then
  pass "7. [Socket Binding] auth-service binds to 0.0.0.0 (listens on all container interfaces)"
else
  fail "7. [Socket Binding] auth-service binds to '${AUTH_BIND}' (loopback only)" \
       "Inspect 'kubectl get deploy auth-service -n cloudapex-core -o yaml'. Binding to 127.0.0.1 restricts socket listeners to the container loopback interface, rejecting inter-service calls with 'Connection refused'."
fi

echo ""

# ------------------------------------------------------------------------------
# SECTION 3: INVENTORY MESH & STATEFUL CACHE (namespace: cloudapex-inventory)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 3: Inventory Tier & Distributed Cache — namespace: cloudapex-inventory]${NC}"

# Check 8: Cross-Namespace Ingress NetworkPolicy Label Typo
ALLOWED_NS=$(kubectl get netpol inventory-service-netpol -n cloudapex-inventory -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}' 2>/dev/null || echo "")
if [[ "${ALLOWED_NS}" == "cloudapex-core" ]]; then
  pass "8. [Cross-NS Ingress NetPol] inventory-service-netpol correctly permits traffic from 'cloudapex-core'"
else
  fail "8. [Cross-NS Ingress NetPol] inventory-service-netpol selects namespace '${ALLOWED_NS}' (expected 'cloudapex-core')" \
       "Inspect 'kubectl get netpol inventory-service-netpol -n cloudapex-inventory -o yaml'. The namespace label selector specifies an invalid namespace name, causing Calico to drop inter-service checkout calls with 504 Gateway Timeout."
fi

# Check 9: Inventory Service Named Port & TargetPort Alignment
INV_TPORT=$(kubectl get svc inventory-service -n cloudapex-inventory -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")
INV_PNAME=$(kubectl get deploy inventory-service -n cloudapex-inventory -o jsonpath='{.spec.template.spec.containers[0].ports[0].name}' 2>/dev/null || echo "")
INV_EP_PORT=$(kubectl get ep inventory-service -n cloudapex-inventory -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || echo "")

if [[ ("${INV_TPORT}" == "${INV_PNAME}" || "${INV_TPORT}" == "8081") && "${INV_EP_PORT}" == "8081" ]]; then
  pass "9. [Named Port Resolution] inventory-service targetPort resolves to container port 8081"
else
  fail "9. [Named Port Resolution] inventory-service targetPort ('${INV_TPORT}') does not match container port ('${INV_PNAME}')" \
       "Inspect 'kubectl describe svc inventory-service -n cloudapex-inventory' and Deployment spec. TargetPort 'rpc-http' does not match container port name 'http', leaving endpoint ports unresolved."
fi

# Check 10: Headless Cache StatefulSet serviceName
CACHE_STS_SVC=$(kubectl get sts inventory-cache -n cloudapex-inventory -o jsonpath='{.spec.serviceName}' 2>/dev/null || echo "")
if [[ "${CACHE_STS_SVC}" == "cache-headless" ]]; then
  pass "10. [Headless DNS] inventory-cache StatefulSet spec.serviceName matches 'cache-headless'"
else
  fail "10. [Headless DNS] inventory-cache StatefulSet spec.serviceName is '${CACHE_STS_SVC}' (expected 'cache-headless')" \
       "Inspect 'kubectl get sts inventory-cache -n cloudapex-inventory -o yaml'. StatefulSet spec.serviceName must match the headless Service name ('cache-headless') for deterministic peer discovery."
fi

echo ""
echo -e "${CYAN}======================================================================${NC}"
echo -e "   Audit Summary: ${GREEN}${PASS_COUNT} Passed${NC} / ${RED}${FAIL_COUNT} Failed${NC} (Total: ${TOTAL_CHECKS})"
echo -e "${CYAN}======================================================================${NC}"

if [[ ${PASS_COUNT} -eq ${TOTAL_CHECKS} ]]; then
  echo -e "${GREEN}🎉 CONGRATULATIONS! All CloudApex v10.0 networking issues are resolved!${NC}"
  echo -e "${GREEN}   Both external Azure LoadBalancers and the Zero-Trust mesh are fully healthy.${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  Some checks failed. Follow the diagnostic directions above and consult README.md.${NC}"
  exit 1
fi
