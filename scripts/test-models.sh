#!/bin/bash
#
# Test all MaaSical Chairs models with chat completions
# Triggers scale-up from zero and demonstrates inference
#

# Note: Not using set -e because we run concurrent background jobs
# and want all models to be tested even if some fail

# Configuration
export NAMESPACE="${NAMESPACE:-maasical-chairs-demo}"
export MAX_TOKENS="${MAX_TOKENS:-100}"
export TIMEOUT="${TIMEOUT:-300}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get cluster domain
export CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

# Model configurations: RELEASE_NAME|MODEL_NAME|PROMPT
MODELS=(
    "llama3-2-3b|llama3-2-3b|What is Kubernetes in one sentence?"
    "granite3-3-8b|granite-8b|Explain KEDA autoscaling briefly."
    "qwen3-4b|qwen3-4b|Hello! How are you today?"
    "granite4-micro|granite-4.0|What is OpenShift AI?"
)

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           MaaSical Chairs - Model Test Suite                   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Namespace: ${YELLOW}${NAMESPACE}${NC}"
echo -e "Cluster:   ${YELLOW}${CLUSTER_DOMAIN}${NC}"
echo -e "Timeout:   ${YELLOW}${TIMEOUT}s${NC} (for cold start)"
echo ""

# Function to test a single model (runs in background, non-blocking)
test_model() {
    local release_name="$1"
    local model_name="$2"
    local prompt="$3"

    local route_host="${release_name}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
    local url="https://${route_host}/v1/chat/completions"

    # Check current pod status
    local pods=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name="$release_name" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$pods" -eq 0 ]; then
        echo -e "[${GREEN}${release_name}${NC}] ${YELLOW}⏳ No pods - scaling from zero...${NC}"
    else
        echo -e "[${GREEN}${release_name}${NC}] ${GREEN}✓ Pod running${NC}"
    fi

    local start_time=$SECONDS

    # Make the request - use full TIMEOUT for connect since interceptor holds connection during scale-up
    local response=$(curl -sk --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" -X POST "$url" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$model_name"'",
            "messages": [{"role": "user", "content": "'"$prompt"'"}],
            "max_tokens": '"$MAX_TOKENS"'
        }' 2>&1)

    local elapsed=$((SECONDS - start_time))

    # Parse response
    if echo "$response" | grep -q '"choices"'; then
        echo -e "[${GREEN}${release_name}${NC}] ${GREEN}✓ Response in ${elapsed}s${NC}"
    elif echo "$response" | grep -q '"error"'; then
        local error_msg=$(echo "$response" | jq -r '.error.message' 2>/dev/null | head -c 60)
        echo -e "[${GREEN}${release_name}${NC}] ${RED}✗ Error: ${error_msg}${NC}"
    elif [ -z "$response" ]; then
        echo -e "[${GREEN}${release_name}${NC}] ${RED}✗ Timeout after ${elapsed}s${NC}"
    else
        echo -e "[${GREEN}${release_name}${NC}] ${RED}✗ Failed after ${elapsed}s${NC}"
    fi
}

# Function to simulate traffic burst
simulate_traffic() {
    local release_name="$1"
    local model_name="$2"
    local count="${3:-5}"

    local route_host="${release_name}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
    local url="https://${route_host}/v1/chat/completions"

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Simulating ${count} concurrent requests to: ${NC}${GREEN}${release_name}${NC}"
    echo ""

    local prompts=(
        "What is machine learning?"
        "Explain containers in one sentence."
        "What is OpenShift?"
        "Define serverless computing."
        "What is GPU acceleration?"
    )

    for i in $(seq 1 "$count"); do
        local prompt="${prompts[$((i % ${#prompts[@]}))]}"
        (
            local start=$SECONDS
            local resp=$(curl -sk --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" -X POST "$url" \
                -H "Content-Type: application/json" \
                -d '{
                    "model": "'"$model_name"'",
                    "messages": [{"role": "user", "content": "'"$prompt"'"}],
                    "max_tokens": 50
                }' 2>&1)
            local elapsed=$((SECONDS - start))
            if echo "$resp" | grep -q '"choices"'; then
                echo -e "  [${release_name}] ${GREEN}✓${NC} Request $i completed in ${elapsed}s"
            else
                echo -e "  [${release_name}] ${RED}✗${NC} Request $i failed after ${elapsed}s"
            fi
        ) &
    done
    wait
    echo ""
}

# Parse arguments
ACTION="${1:-test}"
TARGET="${2:-all}"

case "$ACTION" in
    test)
        if [ "$TARGET" = "all" ]; then
            echo -e "${GREEN}Testing all models concurrently...${NC}"
            echo ""
            # Launch all tests in parallel - use subshell to isolate IFS changes
            for model_config in "${MODELS[@]}"; do
                (
                    IFS='|' read -r release_name model_name prompt <<< "$model_config"
                    test_model "$release_name" "$model_name" "$prompt"
                ) &
            done
            # Wait for all to complete
            wait
        else
            # Find matching model
            found=0
            for model_config in "${MODELS[@]}"; do
                (
                    IFS='|' read -r release_name model_name prompt <<< "$model_config"
                    if [ "$release_name" = "$TARGET" ]; then
                        test_model "$release_name" "$model_name" "$prompt"
                        exit 0
                    fi
                    exit 1
                ) && { found=1; break; }
            done
            if [ "$found" -eq 1 ]; then
                exit 0
            fi
            echo -e "${RED}Model not found: ${TARGET}${NC}"
            echo "Available models: llama3-2-3b, granite3-3-8b, qwen3-4b, granite4-micro"
            exit 1
        fi
        ;;

    traffic)
        COUNT="${3:-5}"
        if [ "$TARGET" = "all" ]; then
            echo -e "${GREEN}Simulating traffic to all models concurrently...${NC}"
            echo ""
            for model_config in "${MODELS[@]}"; do
                (
                    IFS='|' read -r release_name model_name prompt <<< "$model_config"
                    simulate_traffic "$release_name" "$model_name" "$COUNT"
                ) &
            done
            wait
        else
            found=0
            for model_config in "${MODELS[@]}"; do
                (
                    IFS='|' read -r release_name model_name prompt <<< "$model_config"
                    if [ "$release_name" = "$TARGET" ]; then
                        simulate_traffic "$release_name" "$model_name" "$COUNT"
                        exit 0
                    fi
                    exit 1
                ) && { found=1; break; }
            done
            if [ "$found" -eq 0 ]; then
                echo -e "${RED}Model not found: ${TARGET}${NC}"
                exit 1
            fi
        fi
        ;;

    status)
        echo -e "${CYAN}Current Status:${NC}"
        echo ""
        echo -e "${YELLOW}Pods:${NC}"
        oc get pods -n "$NAMESPACE" 2>/dev/null || echo "No pods running"
        echo ""
        echo -e "${YELLOW}HTTPScaledObjects:${NC}"
        oc get httpscaledobject -n "$NAMESPACE"
        ;;

    watch)
        echo -e "${CYAN}Watching pods (Ctrl+C to stop)...${NC}"
        oc get pods -n "$NAMESPACE" -w
        ;;

    --help|-h|help)
        echo "Usage: $0 [action] [target] [count]"
        echo ""
        echo "Actions:"
        echo "  test [model|all]       - Test model(s) with chat completion (default)"
        echo "  traffic [model|all] N  - Simulate N concurrent requests"
        echo "  status                 - Show current pods and scaling status"
        echo "  watch                  - Watch pods scale up/down"
        echo ""
        echo "Environment variables:"
        echo "  NAMESPACE    - Target namespace (default: maasical-chairs-demo)"
        echo "  TIMEOUT      - Request timeout in seconds (default: 300)"
        echo "  MAX_TOKENS   - Max tokens per response (default: 100)"
        echo ""
        echo "Examples:"
        echo "  $0                           # Test all models concurrently"
        echo "  $0 test llama3-2-3b          # Test only Llama"
        echo "  $0 traffic granite3-3-8b 10  # Send 10 concurrent requests to Granite"
        echo "  $0 traffic all 5             # Send 5 requests to each model"
        echo "  $0 status                    # Check current state"
        echo "  $0 watch                     # Watch pods scale"
        echo ""
        echo "  TIMEOUT=600 $0 test all      # Test with 10 minute timeout"
        exit 0
        ;;

    *)
        echo "Unknown action: $ACTION"
        echo "Run '$0 --help' for usage"
        exit 1
        ;;
esac

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                         Done!                                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
