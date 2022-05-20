# calico-config-check
Tool for verifying Calico Enterprise installation, configuration and telemetry data.

## Prerequistes
Bash. 


## How to use

 1. Clone the repository
 2. Make sure your .kube/config is present in $HOME.
 3. You can directly run the script `./calico-cluster-check.sh`.



## How to run

```
./calico-cluster-check.sh | tee execution_summary
```


### What's in the script?


#### Configuration preamble

| config | description |
|---|---|
| `grep_filter="egrep -i error\|failed"` | controls behaviour for seeking error lines if any tailing is required
| `tail_lines=200` | [FLAG 4] limits tailing to 200 lines

#### Common checks, performed on both OSS and Enterprise.

| function | description/strategy |
|---|---|
| `check_operator_based` | [FLAG 1] looks for the `tigera-operator` pods in all namespaces. | 
| `check_kube_config` | checks and exports kubeconfig |
| `check_kubeVersion` | checks for kubernetes client and server versions and its drifts (Note 1). prints out information about distribution type (Note 2), and if `Openshift`, will also check for OCP Platform and Version (Note 3 and 4) |
| `check_cluster_pod_cidr` | Pod CIDR and IPPool dump (Note 5 and 6). Prints errors if not available. |
| `check_calico_pods` | checks calico pod statuses manually by inspecting the calico daemonset. counts desired, current, ready, up-to-date, and available. if desired != current, summary is displayed as an error. |
| `copy_logs` | [FLAG 2] copies `/tmp`-prefixed log directories to a diags package dir |
| `display_summary` | displays summary of all checks performed then tarballs all artifacts in `$calico_logs`) |


#### OSS-only checks

| function | description/strategy |
|---|---|
| `check_kubeapiserver_status` | queries pods with label `k8s-app=-tigera-apiserver` and prints out status. if status is not `Running` the message is printed red indicating an error.  |

#### Calico Enterprise checks

| function | description/strategy |
|---|---|
| `check_tigera_version` | Checks tigera version (Note 7) |
| `check_tigera_license` | Checks tigera license and if it has expired (Note 8 and 9) |
| `check_tigerastatus` | Checks and displays tigera status (basically `kubectl get tigerastatus`) |
| `check_es_pvc_status` | Enumerates PVC, PVs and Storage classes related to elastic search |
| `check_tigera_namespaces` | Checks if specific namespaces are present in this questionably-outdated list (Note 10) |
| `check_apiserver_status` | Enumeration of `tigera-apiserver` status (Note 11) |
| `check_tigera_pods` | [FLAG 3] Checks tigera-related pods in stages (Note 12, 13, 14) |
| `check_tier` | Enumerate for tier "`allow-tigera`" (Note 15) |
| `calico_telemetry` | Collect various telemetry stats stored in calico-logs so it can be included in the final tarball. |

#### Checks performed postscript

Notes

1. `kubectl version --short | awk 'NR==%VAR%{print $3}'` (where `NR==%VAR%` is `1` and `2` for client, server respectively)
2. `kubectl get Installation.operator.tigera.io -o jsonpath='{.items[0].spec.kubernetesProvider`
3. `kubectl get ClusterVersion.config.openshift.io -o jsonpath='{.items[0].status.desired.version`
4. `kubectl get infrastructure.config.openshift.io -o jsonpath='{.items[0].status.platform`
5. `kubectl cluster-info dump | grep -i "\-\-cluster\-cidr" |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}' | head -1`
6. `kubectl get ippool -o yaml | grep cidr | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}` 
7. `kubectl get clusterinformations.projectcalico.org default -o yaml | grep -i "cnxVersion" | awk '{print $2}'`
8. `kubectl get licensekeys.projectcalico.org -o yaml | grep "name:" | awk '{print $2}'`
9. License expiry check is available for Clusters with Calico Enterprise v3.0 onwards
10. `("tigera-compliance" "tigera-eck-operator" "tigera-elasticsearch" "tigera-fluentd" "tigera-intrusion-detection" "tigera-kibana" "tigera-manager" "tigera-operator" "tigera-prometheus" "tigera-system")`
11. `kubectl get po -l k8s-app=tigera-apiserver -n tigera-system | awk 'NR==2{print $3}'`
12. Stage 1: check tigera apps (`tigera-manager`, `tigera-operator`). Enumerate and list find logs for errors in a log tail [FLAG 4]
13. Stage 2: Enumerate kibana pods, their statuses and logs [FLAG 4]
14. Stage 3: Enumerate fluentd pods, statuses and logs [FLAG 4]
15. `kubectl get tier allow-tigera | awk 'NR==2{print $1}'`


Flags

1. WARNING: false positive 
2. Behaviour differs conditionally based on calico type (OSS or Ent)
3. Large-ish function
4. Tail lines limited to 200