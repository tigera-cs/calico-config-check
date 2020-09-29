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


### Checks performed

#### Calico Enterprise checks

```
check_operator_based
check_kubectl_calico_binary
check_kube_config
check_kubeVersion
check_cluster_pod_cidr
check_tigera_version
check_tigera_license
check_tigerastatus
check_es_pvc_status
check_tigera_namespaces
check_apiserver_status
check_calico_pods
check_tigera_pods
check_tier
calico_diagnostics
copy_logs
calico_telemetry
display_summary
```

#### OSS calico checks

```
check_operator_based
check_kube_config
check_kubeVersion
check_cluster_pod_cidr
check_kubeapiserver_status
check_calico_pods
copy_logs
display_summary
```

