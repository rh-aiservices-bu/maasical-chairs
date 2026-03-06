# Demo: Scale-to-Zero with KEDA HTTP Add-on

This demo shows how to enable scale-to-zero for LLM inference services using the KEDA HTTP Add-on. When idle, models scale to 0 replicas (releasing GPU resources), and automatically scale up when requests arrive.

![HTTP Add-On Architecture](./assets/images/http-addon1.png)

## Prerequisites

- OpenShift cluster with GPU nodes (4x for full demo)
- Cluster admin access
- Helm v3+

## Step 1: Install KEDA Operator

```bash
oc create namespace openshift-keda
oc label namespace openshift-keda openshift.io/cluster-monitoring=true

helm install keda-operator helm/keda-operator/ -n openshift-keda
```

## Step 2: Enable User Workload Monitoring

```bash
helm install uwm helm/uwm/ -n openshift-monitoring
```

## Step 3: Configure KEDA Controller

```bash
helm install keda helm/keda/ -n openshift-keda
```

## Step 4: Install HTTP Add-on

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install http-add-on kedacore/keda-add-ons-http -n openshift-keda \
  --set interceptor.replicas.waitTimeout=180s \
  --set interceptor.responseHeaderTimeout=180s
```

Verify all components are running:

```bash
oc get pods -n openshift-keda
```

Expected output:
```
keda-operator-xxx                          1/1     Running
keda-add-ons-http-controller-manager-xxx   1/1     Running
keda-add-ons-http-interceptor-xxx          1/1     Running
keda-add-ons-http-scaler-xxx               1/1     Running
```

## Step 5: Deploy All Models with Scale-to-Zero

**Option A: Use the deployment script (recommended)**

```bash
# Deploy all 4 models with 180s scaledown period
SCALEDOWN_PERIOD=180 ./scripts/deploy-models.sh
```

**Option B: Manual deployment**

```bash
export NAMESPACE=maasical-chairs-demo
oc new-project $NAMESPACE


# Get cluster domain for route hostnames
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

# Deploy Llama 3.2-3B
RELEASE_NAME=llama3-2-3b
ROUTE_HOST="${RELEASE_NAME}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
helm install $RELEASE_NAME helm/llama3.2-3b/ \
  --set keda.enabled=true \
  --set httpAddon.enabled=true \
  --set httpAddon.host=$ROUTE_HOST \
  --set httpAddon.minReplicas=0 \
  --set httpAddon.maxReplicas=1 \
  --set httpAddon.scaledownPeriod=180 \
  -n $NAMESPACE

# Deploy Granite 3.3-8B
RELEASE_NAME=granite3-3-8b
ROUTE_HOST="${RELEASE_NAME}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
helm install $RELEASE_NAME helm/granite3.3-8b/ \
  --set keda.enabled=true \
  --set httpAddon.enabled=true \
  --set httpAddon.host=$ROUTE_HOST \
  --set httpAddon.minReplicas=0 \
  --set httpAddon.maxReplicas=1 \
  --set httpAddon.scaledownPeriod=180 \
  -n $NAMESPACE

# Deploy Qwen3-4B
RELEASE_NAME=qwen3-4b
ROUTE_HOST="${RELEASE_NAME}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
helm install $RELEASE_NAME helm/qwen3-4b/ \
  --set keda.enabled=true \
  --set httpAddon.enabled=true \
  --set httpAddon.host=$ROUTE_HOST \
  --set httpAddon.minReplicas=0 \
  --set httpAddon.maxReplicas=1 \
  --set httpAddon.scaledownPeriod=180 \
  -n $NAMESPACE

# Deploy Gemma-7B
RELEASE_NAME=gemma-7b
ROUTE_HOST="${RELEASE_NAME}-keda-${NAMESPACE}.${CLUSTER_DOMAIN}"
helm install $RELEASE_NAME helm/gemma-7b/ \
  --set keda.enabled=true \
  --set httpAddon.enabled=true \
  --set httpAddon.host=$ROUTE_HOST \
  --set httpAddon.minReplicas=0 \
  --set httpAddon.maxReplicas=1 \
  --set httpAddon.scaledownPeriod=180 \
  -n $NAMESPACE
```

Verify all models are deployed:

```bash
oc get httpscaledobject,routes -n $NAMESPACE
```

Expected output:
```
NAME                                              TARGETWORKLOAD                              MINREPLICAS   MAXREPLICAS   READY
httpscaledobject.http.keda.sh/llama3-2-3b         apps/v1/Deployment/llama3-2-3b-predictor    0             1             True
httpscaledobject.http.keda.sh/granite3-3-8b       apps/v1/Deployment/granite3-3-8b-predictor  0             1             True
httpscaledobject.http.keda.sh/qwen3-4b            apps/v1/Deployment/qwen3-4b-predictor       0             1             True
httpscaledobject.http.keda.sh/gemma-7b            apps/v1/Deployment/gemma-7b-predictor       0             1             True
```

Verify pods are at zero (wait for scaledownPeriod):

```bash
oc get pods -n $NAMESPACE
# Should show: No resources found
```

## Step 6: Watch the Magic

**Terminal 1 - Watch pods:**
```bash
oc get pods -n $NAMESPACE -w
```

**Terminal 2 - Trigger scale-up for each model:**
```bash
# Get route hosts
LLAMA_HOST=$(oc get route -n $NAMESPACE -l app.kubernetes.io/name=llama3-2-3b -o jsonpath='{.items[0].spec.host}')
GRANITE_HOST=$(oc get route -n $NAMESPACE -l app.kubernetes.io/name=granite3-3-8b -o jsonpath='{.items[0].spec.host}')
QWEN_HOST=$(oc get route -n $NAMESPACE -l app.kubernetes.io/name=qwen3-4b -o jsonpath='{.items[0].spec.host}')
GEMMA_HOST=$(oc get route -n $NAMESPACE -l app.kubernetes.io/name=gemma-7b -o jsonpath='{.items[0].spec.host}')

# Trigger Llama (first request takes ~60-90s)
time curl -sk --max-time 300 "https://$LLAMA_HOST/v1/models"

# Trigger Granite (first request takes ~80-120s)
time curl -sk --max-time 300 "https://$GRANITE_HOST/v1/models"

# Trigger Qwen (first request takes ~70-100s)
time curl -sk --max-time 300 "https://$QWEN_HOST/v1/models"

# Trigger Gemma (first request takes ~90-120s)
time curl -sk --max-time 300 "https://$GEMMA_HOST/v1/models"
```

You'll see in Terminal 1:
```
# Initially: no pods (all models at zero)

# After curl to Llama:
llama3-2-3b-predictor-xxx   0/1   Pending             0s
llama3-2-3b-predictor-xxx   0/1   ContainerCreating   1s
llama3-2-3b-predictor-xxx   1/1   Running             65s   ← Ready!

# After 180s idle:
llama3-2-3b-predictor-xxx   1/1   Terminating         3m
# Back to zero - GPU released!
```

## Step 7: Test Chat Completion

```bash
# Chat with Llama
curl -sk "https://$LLAMA_HOST/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3-2-3b",
    "messages": [{"role": "user", "content": "What is Kubernetes?"}],
    "max_tokens": 100
  }'

# Chat with Granite
curl -sk "https://$GRANITE_HOST/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-8b",
    "messages": [{"role": "user", "content": "Explain KEDA in one sentence."}],
    "max_tokens": 100
  }'

# Chat with Qwen
curl -sk "https://$QWEN_HOST/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-4b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'

# Chat with Gemma
curl -sk "https://$GEMMA_HOST/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-7b",
    "messages": [{"role": "user", "content": "Write a haiku about GPUs."}],
    "max_tokens": 100
  }'
```

## Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `keda.enabled` | `false` | Enable KEDA autoscaling |
| `httpAddon.enabled` | `false` | Enable scale-to-zero |
| `httpAddon.host` | `""` | Route hostname (required) |
| `httpAddon.minReplicas` | `0` | Min replicas (0 = scale-to-zero) |
| `httpAddon.maxReplicas` | `1` | Max replicas |
| `httpAddon.scaledownPeriod` | `300` | Seconds idle before scaling down |

## Cleanup

```bash
helm uninstall llama3-2-3b granite3-3-8b qwen3-4b gemma-7b -n $NAMESPACE
oc delete project $NAMESPACE
```

## Troubleshooting

See [Troubleshooting Guide](troubleshooting.md) for common issues.
