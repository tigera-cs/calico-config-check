# calico-config-check
Tool for verifying Calico Enterprise installation and configuration

## Prerequistes
Bash and python. 

## How to use
 1. Clone the repository
 2. Check if `kubectl-calico` binary (comes bundled with the repository) exists in the same directory as `calico-cluster-check.sh` script.
 3. Make sure your .kube/config is present in $HOME, else change the `kubeconfig` variable in script to point to desrired location.
 4. You can directly run the script `./calico-cluster-check.sh`, just make sure you have followed Step 2 and Step 3.
 5. Otherwise, to run the script as a kubectl plugin (ex. kubectl-calicocheck)
 ```
 mv calico-cluster-check.sh kubectl-calicocheck
 chmod +x kubectl-calicocheck
 sudo mv kubectl-calicocheck /usr/local/bin/

 ```
**Note** - Make sure if you follow step 5, other binary `kubectl-calico` should remain in the same cloned repository i.e. `calico-config-check` directory. 

## How to run


```
kubectl-calicocheck | tee execution-summary
```

### Checks performed

#### Calico Enterprise checks

```
update_calico_config_check
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
display_summary
```

#### OSS calico checks

```
update_calico_config_check
check_operator_based
check_kube_config
check_kubeVersion
check_cluster_pod_cidr
check_kubeapiserver_status
check_calico_pods
copy_logs
display_summary
```
