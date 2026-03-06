#!/bin/bash
#
# Deploy all MaaSical Chairs models with scale-to-zero
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-maasical-chairs-demo}"
SCALEDOWN_PERIOD="${SCALEDOWN_PERIOD:-180}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/../helm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         MaaSical Chairs - Deploy Models with Scale-to-Zero     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc CLI not found${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm CLI not found${NC}"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Get cluster domain
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
echo -e "Cluster domain: ${YELLOW}${CLUSTER_DOMAIN}${NC}"
echo ""

# Create namespace if needed
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
    oc new-project "$NAMESPACE"
else
    echo -e "${GREEN}Namespace ${NAMESPACE} exists${NC}"
    oc project "$NAMESPACE"
fi
echo ""

# Check KEDA HTTP Add-on
echo -e "${YELLOW}Checking KEDA HTTP Add-on...${NC}"
if ! oc get pods -n openshift-keda -l app.kubernetes.io/name=http-add-on-interceptor &> /dev/null; then
    echo -e "${RED}Warning: KEDA HTTP Add-on may not be installed${NC}"
    echo -e "Install with: helm install http-add-on kedacore/keda-add-ons-http -n openshift-keda"
fi
echo ""

# Define models (parallel arrays for portability)
RELEASE_NAMES="llama3-2-3b granite3-3-8b qwen3-4b granite4-micro"
CHART_NAMES="llama3.2-3b granite3.3-8b qwen3-4b granite4-micro"

echo -e "${GREEN}Deploying models with scale-to-zero...${NC}"
echo -e "  Namespace: ${YELLOW}${NAMESPACE}${NC}"
echo -e "  Scaledown Period: ${YELLOW}${SCALEDOWN_PERIOD}s${NC}"
echo ""

# Deploy each model
set -- $CHART_NAMES
for RELEASE_NAME in $RELEASE_NAMES; do
    CHART_NAME="$1"
    shift
    ROUTE_HOST="${RELEASE_NAME}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"

    echo -e "${YELLOW}Deploying ${RELEASE_NAME}...${NC}"

    # Check if already deployed
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        echo -e "  ${YELLOW}Already deployed, upgrading...${NC}"
        helm upgrade "$RELEASE_NAME" "${HELM_DIR}/${CHART_NAME}/" \
            --set keda.enabled=true \
            --set httpAddon.enabled=true \
            --set httpAddon.host="$ROUTE_HOST" \
            --set httpAddon.minReplicas=0 \
            --set httpAddon.maxReplicas=1 \
            --set httpAddon.scaledownPeriod="$SCALEDOWN_PERIOD" \
            -n "$NAMESPACE"
    else
        helm install "$RELEASE_NAME" "${HELM_DIR}/${CHART_NAME}/" \
            --set keda.enabled=true \
            --set httpAddon.enabled=true \
            --set httpAddon.host="$ROUTE_HOST" \
            --set httpAddon.minReplicas=0 \
            --set httpAddon.maxReplicas=1 \
            --set httpAddon.scaledownPeriod="$SCALEDOWN_PERIOD" \
            -n "$NAMESPACE"
    fi

    echo -e "  ${GREEN}✓ ${RELEASE_NAME} deployed${NC}"
    echo -e "  Route: ${YELLOW}https://${ROUTE_HOST}${NC}"
    echo ""
done

# Wait for HTTPScaledObjects to be ready
echo -e "${YELLOW}Waiting for HTTPScaledObjects to be ready...${NC}"
sleep 5

# Show status
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                     Deployment Status                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}HTTPScaledObjects:${NC}"
oc get httpscaledobject -n "$NAMESPACE"
echo ""

echo -e "${YELLOW}Routes:${NC}"
oc get routes -n "$NAMESPACE"
echo ""

echo -e "${YELLOW}Pods (should be 0 after scaledown):${NC}"
oc get pods -n "$NAMESPACE"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                     Test Commands                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "# Watch pods scale up/down:"
echo -e "oc get pods -n ${NAMESPACE} -w"
echo ""
echo -e "# Trigger scale-up (cold start ~60-120s):"
for RELEASE_NAME in $RELEASE_NAMES; do
    ROUTE_HOST="${RELEASE_NAME}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
    echo -e "curl -sk https://${ROUTE_HOST}/v1/models"
done
echo ""
echo -e "${GREEN}Done!${NC}"
