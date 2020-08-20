# calico-config-check
Tool for verifying Calico Enterprise installation and configuration

## Prerequistes
Bash and python. 

## How to use
 1. Clone the repository
 2. Make sure your .kube/config is present in $HOME, else change the `kubeconfig` variable in script to point to desrired location.
 3. You can directly run the script ./calico-cluster-check.sh
 4. Otherwise, to run the script as a kubectl plugin (ex. kubectl calicocheck)
 ```
 mv calico-cluster-check.sh kubectl-calicocheck
 chmod +x kubectl-calicocheck
 sudo mv kubectl-calicocheck /usr/local/bin/
 ```

## How to run


```
kubectl-calicocheck | tee execution-summary
```

### Checks performed

```
update_calico_config_check
check_kube_config
check_kubeVersion
check_cluster_pod_cidr
check_tigera_version
check_tigera_license
check_tigerastatus
check_es_pv_status
check_tigera_namespaces
check_apiserver_status
check_calico_pods
check_tigera_pods
check_tier
calico_diagnostics
display_summary
```
