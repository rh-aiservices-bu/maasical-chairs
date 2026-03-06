# Troubleshooting Guide

## Cold Start Timeout

**Symptom:** Request times out before pod is ready.

**Fix:** Increase HAProxy timeout on the route:
```bash
oc annotate route <route-name> -n $NAMESPACE \
  haproxy.router.openshift.io/timeout=300s --overwrite
```

Or upgrade HTTP Add-on with longer timeouts:
```bash
helm upgrade http-add-on kedacore/keda-add-ons-http -n openshift-keda \
  --set interceptor.replicas.waitTimeout=300s \
  --set interceptor.responseHeaderTimeout=300s
```

## 503 Errors

**Symptom:** Route returns 503 Service Unavailable.

**Check 1:** Verify interceptor proxy service and endpoints exist:
```bash
oc get svc,endpoints -n $NAMESPACE | grep interceptor
```

**Check 2:** Verify HTTP Add-on pods are running:
```bash
oc get pods -n openshift-keda | grep http
```

**Check 3:** Verify HTTPScaledObject is ready:
```bash
oc get httpscaledobject -n $NAMESPACE
```

## HTTPScaledObject Not Ready

**Symptom:** HTTPScaledObject shows `READY=False`.

**Check logs:**
```bash
oc logs -n openshift-keda -l app.kubernetes.io/name=keda-add-ons-http-controller-manager
```

**Common causes:**
- Interceptor IP not found (HTTP Add-on not installed)
- Target deployment doesn't exist yet
- Invalid host configuration

## Pods Not Scaling Up

**Symptom:** Request sent but pods stay at 0.

**Check 1:** Verify the request is hitting the interceptor:
```bash
oc logs -n openshift-keda -l app=keda-add-ons-http-interceptor
```

**Check 2:** Check KEDA operator logs:
```bash
oc logs -n openshift-keda -l app=keda-operator
```

**Check 3:** Verify route points to interceptor (not predictor):
```bash
oc get route -n $NAMESPACE -o yaml | grep -A5 "to:"
```

## Pods Not Scaling Down

**Symptom:** Pods stay running after idle timeout.

**Check:** Verify `scaledownPeriod` is set correctly:
```bash
oc get httpscaledobject -n $NAMESPACE -o yaml | grep scaledownPeriod
```

**Note:** Default is 300s (5 minutes). For testing, use 60-120s.

## GPU Not Available

**Symptom:** Pod stuck in Pending with GPU resource error.

**Check:** Verify GPU nodes are available:
```bash
oc get nodes -l nvidia.com/gpu.present=true
oc describe node <gpu-node> | grep -A10 "Allocated resources"
```

## Model Load Fails

**Symptom:** Pod starts but model doesn't load.

**Check vLLM logs:**
```bash
oc logs -n $NAMESPACE -l app.kubernetes.io/name=<model-name> -c kserve-container
```

**Common causes:**
- Insufficient GPU memory
- OCI image pull failure
- Invalid model configuration
