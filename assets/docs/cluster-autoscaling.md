# GPU Node Cluster Autoscaling

This guide explains how to configure cluster-level GPU node autoscaling for MaaSical Chairs.

## Overview

While KEDA HTTP Add-on handles pod autoscaling (0→N replicas), cluster autoscaling handles node provisioning when GPU capacity is exhausted:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Two-Level Autoscaling                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Level 1: Pod Autoscaling (KEDA HTTP Add-on)                    │
│  ─────────────────────────────────────────────                  │
│  Request → Interceptor → Scale pods 0→1 → Model serves          │
│                                                                  │
│  Level 2: Node Autoscaling (Cluster Autoscaler)                 │
│  ──────────────────────────────────────────────                 │
│  Pod pending (no GPU) → Scale nodes → GPU available → Schedule  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| **ClusterAutoscaler** | Cluster-wide settings for node scaling |
| **MachineAutoscaler** | Per-MachineSet scaling rules (one per AZ) |
| **MachineSet** | Template for GPU node VMs |

## Quick Start

```bash
# Get your cluster's infrastructure ID
INFRA_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
echo "Infrastructure ID: $INFRA_ID"

# Verify GPU MachineSets exist
oc get machinesets -n openshift-machine-api | grep gpu

# Install cluster autoscaler
helm install cluster-autoscaler helm/cluster-autoscaler/ \
  --set cluster.infraId=$INFRA_ID \
  --set machineAutoscaler.minReplicas=0 \
  --set machineAutoscaler.maxReplicas=5

# Verify
oc get clusterautoscaler
oc get machineautoscaler -n openshift-machine-api
```

## Configuration

### values.yaml Parameters

#### ClusterAutoscaler Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `clusterAutoscaler.enabled` | `true` | Enable ClusterAutoscaler |
| `clusterAutoscaler.maxNodeProvisionTime` | `15m` | Max time to wait for node |
| `clusterAutoscaler.logVerbosity` | `4` | Log level (1-4) |
| `clusterAutoscaler.scaleDown.enabled` | `true` | Enable scale-down |
| `clusterAutoscaler.scaleDown.delayAfterAdd` | `10m` | Wait before scale-down after adding node |
| `clusterAutoscaler.scaleDown.unneededTime` | `5m` | Node must be idle this long before removal |
| `clusterAutoscaler.resourceLimits.maxNodesTotal` | `20` | Max total nodes |

#### MachineAutoscaler Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `machineAutoscaler.enabled` | `true` | Enable MachineAutoscalers |
| `machineAutoscaler.minReplicas` | `0` | Min replicas (0 = scale to zero) |
| `machineAutoscaler.maxReplicas` | `5` | Max replicas per AZ |

#### MachineSet Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `machineSet.create` | `false` | Create new MachineSets |
| `machineSet.existingPattern` | `worker-gpu-big` | Pattern for existing MachineSets |
| `machineSet.availabilityZones` | `[us-east-2a, ...]` | AZs to manage |

## Tuning for Production

### Faster Scale-Up

For lower latency on first request to a new model:

```yaml
clusterAutoscaler:
  maxNodeProvisionTime: 10m  # Fail faster if node doesn't come up
  scaleDown:
    delayAfterAdd: 5m        # Allow scale-down sooner (but risks thrashing)
```

### Aggressive Scale-Down (Cost Savings)

```yaml
clusterAutoscaler:
  scaleDown:
    unneededTime: 3m         # Scale down after 3 minutes idle
    delayAfterAdd: 5m        # Start evaluating scale-down sooner
```

### Conservative Scale-Down (Stability)

```yaml
clusterAutoscaler:
  scaleDown:
    unneededTime: 15m        # Keep nodes longer
    delayAfterAdd: 20m       # Don't scale down recently added nodes
```

### High Availability

Ensure models can be scheduled across multiple AZs:

```yaml
machineAutoscaler:
  minReplicas: 1             # Keep 1 GPU node per AZ always ready
  maxReplicas: 10            # Scale up to 10 per AZ under load
```

## Monitoring

### Watch Autoscaling in Action

```bash
# Watch machines scale
oc get machines -n openshift-machine-api -w

# Watch GPU nodes
oc get nodes -l nvidia.com/gpu.present=true -w

# Check cluster autoscaler logs
oc logs -f -n openshift-machine-api -l cluster-autoscaler=default
```

### Check Scale-Up Events

```bash
# See why a node was added
oc get events -n openshift-machine-api --sort-by='.lastTimestamp' | grep -i scale

# Check pending pods that triggered scale-up
oc get pods -A -o wide | grep Pending
```

## Troubleshooting

### Node Not Scaling Up

1. **Check ClusterAutoscaler status:**
   ```bash
   oc get clusterautoscaler default -o yaml
   ```

2. **Verify MachineAutoscaler:**
   ```bash
   oc get machineautoscaler -n openshift-machine-api -o yaml
   ```

3. **Check capacity annotations on MachineSet:**
   ```bash
   oc get machineset -n openshift-machine-api -o yaml | grep -A5 annotations
   ```

   Required annotations for scale-from-zero:
   ```yaml
   annotations:
     capacity.cluster-autoscaler.kubernetes.io/gpu-count: "1"
     capacity.cluster-autoscaler.kubernetes.io/gpu-type: nvidia.com/gpu
   ```

### Node Not Scaling Down

1. **Check for pods preventing scale-down:**
   ```bash
   oc get pods -A -o wide --field-selector spec.nodeName=<node-name>
   ```

2. **Check pod disruption budgets:**
   ```bash
   oc get pdb -A
   ```

3. **Verify scale-down settings:**
   ```bash
   oc get clusterautoscaler default -o jsonpath='{.spec.scaleDown}'
   ```

## Cost Optimization Tips

1. **Use spot instances** - Modify MachineSet to use spot/preemptible instances for non-critical workloads

2. **Right-size GPU nodes** - Match instance type to model requirements (don't use A100 for 3B models)

3. **Set appropriate scale-down times** - Balance cold start latency vs GPU cost

4. **Monitor utilization** - Use OpenShift monitoring to track GPU utilization and adjust scaling parameters

## Related Documentation

- [KEDA HTTP Add-on Demo](./demo-http-addon.md)
- [Troubleshooting Guide](./troubleshooting.md)
- [OpenShift Cluster Autoscaler](https://docs.openshift.com/container-platform/latest/machine_management/applying-autoscaling.html)
