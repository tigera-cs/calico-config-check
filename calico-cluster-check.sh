#!/bin/bash

# These variables can be customized
grep_filter="egrep -i error\|failed"
tail_lines=200

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
BOLD='\033[1m'
kubeconfig=$HOME/.kube/config
failure_array=()
success_array=()
currwd=`pwd`
tm_ns=`kubectl get pods -A | grep tigera-manager | awk '{print $1}'`
setup_type=`if [[ "$tm_ns" == "tigera-manager" ]]; then echo "Calico Enterprise"; else echo "Calico"; fi`
currdate=`date "+%Y-%m-%d-%H-%M-%S"`
calico_logs=${currwd}/calico-logs_${currdate}
calico_telemetry_dir=${currwd}/calico-logs_${currdate}/calico-telemetry
calico_diagnostics_dir=${currwd}/calico-logs_${currdate}/calico-diagnostics

mkdir ${calico_logs}

cluster_guid=`kubectl get clusterinformations.crd.projectcalico.org default -oyaml | grep "[^f:]clusterGUID:" | awk '{print $2}'`
echo -e "${GREEN}The Cluster GUID is ${cluster_guid} ${NC}"
echo -e "\n"

function check_operator_based {
        state=`kubectl get pods -A | grep operator | awk '{print $1}'`
        if [[ -z "$state" ]]; then echo "Cluster is not Operator based, this script works only for Operator based Calico Installation"; exit 0;fi
}

function update_calico_config_check {
        currwd=`pwd`
        filepath="$0"
        localfilesize=`stat -c %s $filepath`
        remotefilesize=`curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/tigera-cs/calico-config-check/contents/calico-cluster-check.sh | grep size | awk '{pri
nt $2}' | awk -F , '{print $1}'`
        echo $localfilesize $remotefilesize
        if [[ "$localfilesize" -eq "$remotefilesize" ]]; then
                echo "Script up to date"
        else
            echo "Need to pull the updated script"
            read -p "Do you want to update the calico-check script?(yes/no)" reply
            case $reply in
                    [Yy]es) echo "Updating the script file ....."
                            curl -s -O https://raw.githubusercontent.com/tigera-cs/calico-config-check/master/calico-cluster-check.sh;;
                    [Nn]o) echo "User has opted not to update the script" ;;
                        *) echo "Wrong answer. Print yes or no"
                           unset reply ;;
            esac
        fi
}


function check_kube_config {
        echo -e "-------Checking and exporting kubconfig-------"
        if [[ -v KUBECONFIG ]]
        then
                 echo -e "Using KUBECONFIG=$KUBECONFIG"
                 echo -e "\n"
        elif [ -f $kubeconfig ]
        then
                 echo -e "kubeconfig exists at $kubeconfig."
                 export KUBECONFIG=$kubeconfig
                 echo -e "KUBECONFIG is set to $kubeconfig"
                 echo -e "\n"
        else
                echo -e "$RED kubeconfig does not exits at $kubeconfig $NC, if your kubeconfig is at other location, change the kubeconfig variable path above in the script"
                echo -e "\n"
                echo -e "------Exisiting out of script-------"
                echo -e "\n"
                exit 0
        fi

}


function check_kubeVersion {
                echo -e "-------Checking Kubernetes Client and Server version-------"
                client_version=`kubectl version --short | awk 'NR==1{print $3}'`
                server_version=`kubectl version --short | awk 'NR==2{print $3}'`

                x=`expr "${server_version:3:2}" - "${client_version:3:2}"`
                x=`echo $x | tr -d -`
                if [ $x -gt 1 ]; then echo -e "$YELLOW Warn: Difference between the Kubernetes client and server Minor Versions shouldn't be more than 1 $NC"; else echo "Kubernetes client and server Minor Versions are in range"; fi
                distribution_type=$(kubectl get Installation.operator.tigera.io -o jsonpath='{.items[0].spec.kubernetesProvider}' 2>/dev/null || echo -n 'unknown')
                echo -e "The client version is $client_version"
                echo -e "The server version is $server_version"
                if [ ! -z $distribution_type ]; then echo -e "Tigera operator CR indicates this is a $distribution_type cluster"; fi

                case $distribution_type in
                        OpenShift)
                        ocp_version=$(kubectl get ClusterVersion.config.openshift.io -o jsonpath='{.items[0].status.desired.version}' 2>/dev/null || echo -n 'unknown')
                        ocp_platform=$(kubectl get infrastructure.config.openshift.io -o jsonpath='{.items[0].status.platform}' 2>/dev/null || echo -n 'unknown')

                        echo -e "OpenShift is running on $ocp_platform and the version is $ocp_version"

                        ;;
                        *)
                        ;;
                esac
                echo -e "\n"

}

function cidr_check_status {
subnet1="$1"
subnet2="$2"

read_range () {
    IFS=/ read ip mask <<<"$1"
    IFS=. read -a octets <<< "$ip";
    set -- "${octets[@]}";
    min_ip=$(($1*256*256*256 + $2*256*256 + $3*256 + $4));
    host=$((32-mask))
    max_ip=$(($min_ip+(2**host)-1))
    printf "%d-%d\n" "$min_ip" "$max_ip"
}

check_overlap () {
    IFS=- read min1 max1 <<<"$1";
    IFS=- read min2 max2 <<<"$2";
    if [ "$max1" -lt "$min2" ] || [ "$max2" -lt "$min1" ]; then return; fi
    [ "$max1" -ge "$max2" ] && max="$max2" ||   max="$max1"
    [ "$min1" -le "$min2" ] && min="$min2" || min="$min1"
    printf "%s-%s\n" "$(to_octets $min)" "$(to_octets $max)"
}

to_octets () {
    first=$(($1>>24))
    second=$((($1&(256*256*255))>>16))
    third=$((($1&(256*255))>>8))
    fourth=$(($1&255))
    printf "%d.%d.%d.%d\n" "$first" "$second" "$third" "$fourth"
}

range1="$(read_range $subnet1)"
range2="$(read_range $subnet2)"
overlap="$(check_overlap $range1 $range2)"

if [ -z $overlap ]; then echo "False"; else echo "True"; fi

}

function check_cluster_pod_cidr {
                echo -e "-------Checking Cluster and Pod CIDRs-------"
                cluster_cidr=`kubectl cluster-info dump | grep -i "\-\-cluster\-cidr" |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}' | head -1`
                if [ -z "$cluster_cidr" ]; then echo "Unable to retrieve the cluster cidr information"; else echo "The cluster cidr is $cluster_cidr"; fi
                pod_cidr=`kubectl get ippool -o yaml | grep cidr | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                if [ -z "$pod_cidr" ]; then echo "Unable to retrieve the pod cidr information"; else echo "The pod cidr is $pod_cidr"; fi
                if [  ! -z $pod_cidr ]  &&  [ ! -z $cluster_cidr ]; then cidr_check=$(cidr_check_status $cluster_cidr $pod_cidr); fi
                if [ "$cidr_check" == "True" ] && [ ! -z "$cluster_cidr" ]; then echo "Pod cidr: $pod_cidr is a subset of Cluster cidr: $cluster_cidr"; success_array+=("$GREEN Pod cidr: $pod_cidr is a subset of Cluster cidr: $cluster_cidr  $NC"); elif [ "$cidr_check" == "False" ] && [ ! -z "$cluster_cidr" ]; then echo "$RED Pod cidr is not a subset of Cluster cidr $NC"; failure_array+=("$RED Pod cidr is not a subset of Cluster cidr $NC"); fi
                if [ -f cidrcheck.py ]; then
                        rm cidrcheck.py
                fi
                echo -e "\n"
}


function check_tigera_version {
        echo -e "-------Checking Calico Enterprise Version-------"
        echo -e "-------Calico Enterprise Version-------" >> /tmp/execution_output
        calico_enterprise_version=`kubectl get clusterinformations.projectcalico.org default -o yaml | grep -i "cnxVersion" | awk '{print $2}'`
        echo -e "Calico Enterprise version is $calico_enterprise_version"
        echo "$calico_enterprise_version" >> /tmp/execution_output
        echo -e "\n" >> /tmp/execution_output
        echo -e "\n"
}

function check_tigera_license {
        echo -e "-------Checking Calico Enterprise License-------"
        license_name=`kubectl get licensekeys.projectcalico.org -o yaml | grep "name:" | awk '{print $2}'`
        calico_enterprise_version=`kubectl get clusterinformations.projectcalico.org default -o yaml | grep -i "cnxVersion" | awk '{print $2}'`
        echo -e "Note: License expiry check is available for Clusters with Calico Enterprise v3.0 onwards"
        if [ -n $license_name ] && [[ "$calico_enterprise_version" == *"v3.2"* ]] || [[ "$calico_enterprise_version" == *"v3.1"* ]] || [[ "$calico_enterprise_version" == *"v3.0"* ]]
        then
                expiry=`kubectl get licensekeys.projectcalico.org default -o yaml | grep -i "expiry" | awk '{print $2}'`
                expiry=${expiry%T*}
                expiry=${expiry#\"}
                date=$(date '+%Y-%m-%d')
		if [[  (( "$expiry" == "null" )) ]]
		then
			echo -e "${RED} Calico Enterprise license has expired ${NC}"
                        failure_array+=("${RED} Calico Enterprise license has expired ${NC}")
		elif  [[  (( "$date" < "$expiry" )) || (( "$date" == "$expiry" )) ]]
                then
                        echo -e "${GREEN}Calico Enterprise license is valid till $expiry ${NC}"
			if [[ (( "$date" == "$expiry" )) ]]
			then
				echo -e "${YELLOW}Please contact Tigera team for License renewal${NC}"
			fi	
                        success_array+=("${GREEN} Calico Enterprise license is valid till $expiry ${NC}")
                fi
        elif [[ $license_name == "" ]]
        then
                echo -e "${RED} Calico enterprise license is not applied ${NC}"
                failure_array+=("${RED} Calico enterprise license is not applied ${NC}")
        fi
        echo -e "\n"

}



function check_tigerastatus {
                echo -e "-------Checking Tigera Components-------" >> /tmp/execution_output
		kubectl get tigerastatus >> /tmp/execution_output
		echo -e "\n" >> /tmp/execution_output
		echo -e "-------Checking Tigera Components-------"
		tigera_components=(apiserver calico compliance intrusion-detection log-collector log-storage manager)
                for i in "${tigera_components[@]}"
                do
                        available=`kubectl get tigerastatus | grep $i | awk '{print $2}'`
                        if [ "$available" == "True"  ]
                        then
                                echo -e "$i status is $available"
                                success_array+=("$GREEN ${i} is available  $NC")
                        elif [ "$available" == "False"  ]
                        then
                                echo -e "$RED $i status is $available $NC"
                                failure_array+=("$RED ${i} is not available $NC")
                        fi
                done
                echo -e "\n"

}

function check_es_pvc_status {
                echo -e "-------Checking Elasticsearch PVC bound status-------"
                echo -e "---------------------PVC Status----------------------" >> /tmp/execution_output
                kubectl get pvc -A | grep 'tigera-elasticsearch' >> /tmp/execution_output
                echo -e "\n" >> /tmp/execution_output
                echo -e "---------------------PV Status---------------------" >> /tmp/execution_output
                kubectl get pv | grep 'tigera-elasticsearch' >> /tmp/execution_output
                echo -e "\n" >> /tmp/execution_output
                echo -e "---------------------Storage Class Status---------------------" >> /tmp/execution_output
                kubectl get sc  | grep 'tigera-elasticsearch' >> /tmp/execution_output
                echo -e "\n" >> /tmp/execution_output
		bound_count=`kubectl get pvc -A | grep 'tigera-elasticsearch' | awk '{print $3}' | wc -l`
		pvc_count=`kubectl get pvc -A | grep 'tigera-elasticsearch' | wc -l`
                if [ "$pvc_count" == "$bound_count" ]
                then
                        echo -e "Elasticsearch PVC is bounded"
                        success_array+=("$GREEN Elasticsearch PVC is bounded $NC")
                else
                        echo -e "$RED All Elasticsearch PVC are not bouded $NC"
			echo -e "\n"
			kubectl get pvc -A | grep 'tigera-elasticsearch'
                        failure_array+=("$RED All Elasticsearch PVC are not bouded $NC")
                fi
                echo -e "\n"
}

function check_tigera_namespaces {
                echo -e "--------Checking if all Tigera specific namespaces are present -------"
                echo -e "--------Tigera specific namespaces -------" >> /tmp/execution_output
                kubectl get ns | grep tigera  >> /tmp/execution_output
                echo -e "\n" >> /tmp/execution_output
                existing_namespaces=($(kubectl get ns | grep tigera | awk '{print $1}'))
                tigera_namespaces=("tigera-compliance" "tigera-eck-operator" "tigera-elasticsearch" "tigera-fluentd" "tigera-intrusion-detection" "tigera-kibana" "tigera-manager" "tigera-operator" "tigera-prometheus" "tigera-system")
                namespace_difference=()
                for i in "${tigera_namespaces[@]}"; do
                    skip=
                    for j in "${existing_namespaces[@]}"; do
                        [[ $i == $j ]] && { skip=1; break; }
                    done
                    [[ -n $skip ]] || namespace_difference+=("$i")
                done
#               declare -p namespace_difference
                echo  ${namespace_difference[*]}
                if [ -z "$namespace_difference" ]
                then
                        echo -e "All tigera namespaces are present"
                        success_array+=("$GREEN All tigera namespaces are present $NC")
                else
                        echo -e "Following Tigera namespaces are: " ${namespace_difference[*]}
                        failure_array+=("$RED Following Tigera namespaces are not present: ${namespace_difference[*]} $NC")
                fi
                echo -e "\n"
}

function check_apiserver_status {
                echo -e "-------Checking tigera-apiserver status-------"
                tigera_apiserver=`kubectl get po -l k8s-app=tigera-apiserver -n tigera-system | awk 'NR==2{print $3}'`
                if [ "$tigera_apiserver" == "Running" ]
                then
                        echo -e "tigera-apiserver pod is $tigera_apiserver"
                        success_array+=("$GREEN tigera-apiserver pod is $tigera_apiserver $NC")
                elif [ "$tigera_apiserver" != "Running" ]
                then
                        echo -e "$RED tigera-apiserver pod is $tigera_apiserver $NC"
                        failure_array+=("$RED tigera-apiserver pod is $tigera_apiserver $NC")
                fi
                echo -e "\n"
}

function check_kubeapiserver_status {
                echo -e "-------Checking kube-apiserver status-------"
                kube_apiserver=`kubectl get po -l component=kube-apiserver -n kube-system | awk 'NR==2{print $3}'`
                if [ "$kube_apiserver" == "Running" ]
                then
                        echo -e "kube-apiserver pod is $kube_apiserver"
                        success_array+=("$GREEN kube-apiserver pod is $kube_apiserver $NC")
                elif [ "$kube_apiserver" != "Running" ]
                then
                        echo -e "$RED kube-apiserver pod is $kube_apiserver $NC"
                        failure_array+=("$RED kube-apiserver pod is $kube_apiserver $NC")
                fi
                echo -e "\n"
}

function check_calico_pods {
                echo -e "-------Checking calico-node damonset status-------"
                desired_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $2}'`
                current_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $3}'`
                ready_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $4}'`
                uptodate_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $5}'`
                available_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $6}'`
                if [ "$desired_pod_count" == "$current_pod_count" ] && [ "$desired_pod_count" == "$ready_pod_count" ] && [ "$desired_pod_count" == "$uptodate_pod_count" ] && [ "$desired_pod_count" == "$available_pod_count"  ]
                then
                        echo -e "calico-node deamonset is up to date, desired pods are $desired_pod_count and current pods are $current_pod_count"
                        success_array+=("$GREEN calico-node deamonset is up to date $NC")
                else
                        echo -e "$RED calico-node deamonset is not up to date${NC}"
			kubectl get ds -n calico-system calico-node
                        failure_array+=("$RED calico-node deamonset is not up to date $NC")
			kubectl get ds -n calico-system calico-node >> /tmp/execution_output
			echo -e "\n" >> /tmp/execution_output

                fi
                echo -e "\n"
                echo -e "-------Checking calico-node pod logs-------"
                kubectl logs --tail=${tail_lines}  -l k8s-app=calico-node -n calico-system | $grep_filter >> calico_node_error_logs
                [ -s calico_node_error_logs ]
                if [ $? == 0 ]
                then
                        cp calico_node_error_logs /tmp/
                        echo -e "$RED Error logs found, logs present in file ${calico_diagnostics_dir}/calico-node-error.log $NC"
                        failure_array+=("$RED calico-node : Error logs found, logs will be present in file ${calico_diagnostics_dir}/calico-node-error.log $NC")
                        rm calico_node_error_logs
                else
                        echo -e "No errors found in calico-node pods"

                fi
                if [ -f calico_node_error_logs ]
                then
                        rm calico_node_error_logs
		fi
		if [ "$setup_type" == "Calico Enterprise" ]
		then
			echo -e "calico-node logs will be present at ${calico_diagnostics_dir}/per-node-calico-logs once script execution completes"
		elif [ "$setup_type" == "Calico" ]
		then
			        echo -e "---------------------------------------------"
        			echo -e "${YELLOW} Collecting per-node calico-node logs... ${NC}"
        			mkdir -p ${calico_diagnostics_dir}/per-node-calico-logs
        			for node in $(kubectl get pods -n calico-system -l k8s-app=calico-node -o go-template --template="{{range .items}}{{.metadata.name}} {{end}}"); do
                			echo "Collecting logs for node: $node"
                			mkdir -p ${calico_diagnostics_dir}/per-node-calico-logs/${node}
                			kubectl logs --tail=${tail_lines} -n calico-system $node > ${calico_diagnostics_dir}/per-node-calico-logs/${node}/${node}.log
                			kubectl exec -n calico-system -t $node -- iptables-save -c > ${calico_diagnostics_dir}/per-node-calico-logs/${node}/iptables-save.txt
                			kubectl exec -n calico-system -t $node -- ip route > ${calico_diagnostics_dir}/per-node-calico-logs/${node}/iproute.txt
                		done
        			echo -e "Logs present at ${calico_diagnostics_dir}/per-node-calico-logs"
        			echo -e "---------------------------------------------"
		fi

                echo -e "\n"

}

function check_tigera_pods {
        tigera_apps=( tigera-manager tigera-operator )
        for i in "${tigera_apps[@]}"
        do
                echo -e "-------$i pod status-------"

                kubectl get po -n $i -l k8s-app=$i -o wide
                echo -e "-------$i pod status-------" >> /tmp/execution_output
                kubectl get po -n $i -l k8s-app=$i -o wide  >> /tmp/execution_output
                echo -e "\n" >> /tmp/execution_output
                echo -e "\n"
                echo -e "-------Checking $i pod logs-------"
                kubectl logs --tail=${tail_lines} -n $i -l k8s-app=$i -c $i | $grep_filter  >> ${i}_error_logs
                kubectl logs --tail=${tail_lines} -n $i -l k8s-app=$i -c $i >> /tmp/${i}_logs
                [ -s ${i}_error_logs ]
                if [ $? == 0 ]
                then
                        cp ${i}_error_logs /tmp/
                        echo -e "$RED Error logs found, logs will be present in file ${calico_diagnostics_dir}/${i}_error_logs $NC"
                        failure_array+=("$RED ${i} : Error logs found, logs will be present in file ${calico_diagnostics_dir}/${i}-error.log $NC")
                        rm ${i}_error_logs
                else
                        echo -e "No errors found in ${i}, complete logs will be present at ${calico_diagnostics_dir}/${i}.log"
                fi
                if [ -f tigera-manager_error_logs ]
                then
                        rm tigera-manager_error_logs
                fi
                if [ -f tigera-operator_error_logs ]
                then
                        rm tigera-operator_error_logs
                fi
                echo -e "\n"
        done
        echo -e "-------tigera-kibana pod status-------"
        kubectl get po -n tigera-kibana -l k8s-app=tigera-secure -o wide
        echo -e "-------tigera-kibana pod status-------" >> /tmp/execution_output
        kubectl get po -n tigera-kibana -l k8s-app=tigera-secure -o wide  >> /tmp/execution_output
        echo -e "\n" >> /tmp/execution_output
        echo -e "\n"
        echo -e "-------Checking tigera-kibana pod logs-------"
        kubectl logs --tail=${tail_lines} -n tigera-kibana -l k8s-app=tigera-secure | $grep_filter  >> tigera_secure_error_logs
        kubectl logs --tail=${tail_lines} -n tigera-kibana -l k8s-app=tigera-secure >> /tmp/tigera_secure_logs
        [ -s tigera_secure_error_logs ]
        if [ $? == 0 ]
        then
                cp tigera_secure_error_logs /tmp/
                echo -e "$RED Error logs found, logs present in file ${calico_diagnostics_dir}/tigera-secure-error.log $NC"
                failure_array+=("$RED tigera-secure : tigera-secure Error logs found, logs will be present in file ${calico_diagnostics_dir}/tigera-secure-error.log $NC")
                rm tigera_secure_error_logs
        else
                echo -e "No errors found in tigera_secure, complete logs will be present at  ${calico_diagnostics_dir}/tigera-secure.log"
        fi
        echo -e "\n"
        echo -e "-------tigera-fluentd pod status-------"
        kubectl get po -n tigera-fluentd -l k8s-app=fluentd-node -o wide
        echo -e "-------tigera-fluentd pod status-------" >> /tmp/execution_output
        kubectl get po -n tigera-fluentd -l k8s-app=fluentd-node -o wide  >> /tmp/execution_output
        echo -e "\n" >> /tmp/execution_output
        echo -e "\n"
        echo -e "-------Checking tigera-fluentd pod logs-------"
        kubectl logs --tail=${tail_lines} -n tigera-fluentd -l k8s-app=fluentd-node | $grep_filter  >> fluentd_node_error_logs
        kubectl logs --tail=${tail_lines} -n tigera-fluentd -l k8s-app=fluentd-node >> /tmp/fluentd_node_logs
        [ -s fluentd_node_error_logs ]
        if [ $? == 0 ]
        then
                cp fluentd_node_error_logs /tmp/
                echo -e "$RED Error logs found, logs present in file ${calico_diagnostics_dir}/fluentd-node-error.log $NC"
                rm fluentd_node_error_logs
        else
                echo -e "No errors found in fluentd-node pods, complete logs wil be present at ${calico_diagnostics_dir}/fluentd-nodes.log"
        fi
        if [ -f tigera_secure_error_logs ]
        then
                rm tigera_secure_error_logs
        fi
        if [ -f fluentd_node_error_logs ]
        then
                rm fluentd_node_error_logs
        fi
        echo -e "\n"
}

function check_tier {
        echo -e "-------checking allow-tigera tier-------"
        tier_name=`kubectl get tier allow-tigera | awk 'NR==2{print $1}'`
        if [ "$tier_name" == "allow-tigera" ]
        then
                echo -e "Tier allow-tigera  is present"
                success_array+=("$GREEN Tier allow-tigera  is present $NC")

        else
                echo -e "$RED Check if tier allow-tigera is created $NC"
                failure_array+=("$RED Check if tier allow-tigera is created $NC")
        fi
        echo -e "\n"
}

function copy_logs {
	if [ ! -d ${calico_diagnostics_dir} ]
	then
		mkdir -p ${calico_diagnostics_dir}
	fi
	if [ -d ${calico_diagnostics_dir} ] && [ "$setup_type" == "Calico" ]
	then
                if [ -f /tmp/calico_node_error_logs ]; then cp /tmp/calico_node_error_logs ${calico_diagnostics_dir}/calico-node-error.log; rm /tmp/calico_node_error_logs; fi
		if [ -f /tmp/execution_output ];  then cp /tmp/execution_output ${calico_diagnostics_dir}/commands-output; rm /tmp/execution_output; fi
	fi
        if [ -d ${calico_diagnostics_dir} ] && [ "$setup_type" == "Calico Enterprise" ]
        then
                if [ -f /tmp/calico_node_error_logs ]; then cp /tmp/calico_node_error_logs ${calico_diagnostics_dir}/calico-node-error.log; rm /tmp/calico_node_error_logs; fi
                if [ -f /tmp/tigera-manager_error_logs ]; then cp /tmp/tigera-manager_error_logs ${calico_diagnostics_dir}/tigera-manager-error.log; rm /tmp/tigera-manager_error_logs; fi
                if [ -f /tmp/tigera-operator_error_logs ]; then cp /tmp/tigera-operator_error_logs ${calico_diagnostics_dir}/tigera-operator-error.log; rm /tmp/tigera-operator_error_logs; fi
                if [ -f /tmp/tigera_secure_error_logs ]; then cp /tmp/tigera_secure_error_logs ${calico_diagnostics_dir}/tigera-secure-error.log; rm /tmp/tigera_secure_error_logs; fi
                if [ -f /tmp/fluentd_node_error_logs ]; then cp /tmp/fluentd_node_error_logs ${calico_diagnostics_dir}/fluentd-node-error.log; rm /tmp/fluentd_node_error_logs; fi
                if [ -f /tmp/tigera_secure_logs ]; then cp /tmp/tigera_secure_logs ${calico_diagnostics_dir}/tigera-secure.log; rm /tmp/tigera_secure_logs; fi
                if [ -f /tmp/fluentd_node_logs ]; then cp /tmp/fluentd_node_logs ${calico_diagnostics_dir}/fluentd-nodes.log; rm /tmp/fluentd_node_logs; fi
                if [ -f /tmp/tigera-manager_logs ]; then cp /tmp/tigera-manager_logs ${calico_diagnostics_dir}/tigera-manager.log; rm /tmp/tigera-manager_logs; fi
                if [ -f /tmp/tigera-operator_logs ]; then cp /tmp/tigera-operator_logs ${calico_diagnostics_dir}/tigera-operator.log; rm /tmp/tigera-operator_logs; fi
                if [ -f /tmp/execution_output ];  then cp /tmp/execution_output ${calico_diagnostics_dir}/commands-output; rm /tmp/execution_output; fi

        fi


}


function calico_telemetry {
	if [ ! -d ${calico_telemetry_dir} ] && [ "$setup_type" == "Calico Enterprise" ]; then mkdir ${calico_telemetry_dir}; fi
#        calico_telemetry_dir=${currwd}/calico-logs_${currdate}/calico-telemetry
#	calico_diagnostics_dir=${currwd}/calico-logs_${currdate}/calico-diagnostics
	echo -e "${YELLOW}==============Calico Telemetry collection==============${NC}"
	echo -e "\n"
	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting nodes statistics... ${NC}"
	mkdir -p ${calico_telemetry_dir}/nodes
	kubectl get nodes -o yaml > ${calico_telemetry_dir}/nodes/nodes-yaml.yaml
	kubectl get nodes -o wide > ${calico_telemetry_dir}/nodes/nodes.txt
	echo -e "Logs present at ${calico_telemetry_dir}/nodes"
	echo -e "---------------------------------------------"	
	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting pods statistics... ${NC}"
	mkdir -p ${calico_telemetry_dir}/pods
	# Let us avoid getting all pod YAMLs and get only Tigera-specific pod YAMLs if needed.
	#kubectl get pods --all-namespaces -o yaml > ${calico_telemetry_dir}/pods/pods-yaml.yaml
	kubectl get pods --all-namespaces -o wide > ${calico_telemetry_dir}/pods/pods.txt
	echo -e "Logs present at ${calico_telemetry_dir}/pods"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
        echo -e "${YELLOW} Collecting deployments statistics... ${NC}"
        mkdir -p ${calico_telemetry_dir}/deployments
        kubectl get deployments --all-namespaces -o yaml > ${calico_telemetry_dir}/deployments/deployments-yaml.yaml
        kubectl get deployments --all-namespaces -o wide > ${calico_telemetry_dir}/deployments/deployments.txt
        echo -e "Logs present at ${calico_telemetry_dir}/deployments"
        echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
        echo -e "${YELLOW} Collecting daemonsets statistics... ${NC}"
        mkdir -p ${calico_telemetry_dir}/daemonsets
        kubectl get daemonsets --all-namespaces -o yaml > ${calico_telemetry_dir}/daemonsets/daemonsets-yaml.yaml
        kubectl get daemonsets --all-namespaces -o wide > ${calico_telemetry_dir}/daemonsets/daemonsets.txt
        echo -e "Logs present at ${calico_telemetry_dir}/daemonsets"
        echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting services statistics... ${NC}"
	mkdir -p ${calico_telemetry_dir}/services
	kubectl get services --all-namespaces -o wide > ${calico_telemetry_dir}/services/services.txt
	kubectl get services --all-namespaces -o yaml > ${calico_telemetry_dir}/services/services-yaml.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/services"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting configmaps statistics... ${NC}"
	mkdir -p ${calico_telemetry_dir}/configmaps
	kubectl get configmaps --all-namespaces  > ${calico_telemetry_dir}/configmaps/configmaps.txt
	# CMs may contain confidential info. Let us capture only Tigera specific CM if needed.
	kubectl get configmaps --all-namespaces -o yaml > ${calico_telemetry_dir}/configmaps/configmaps-yaml.txt
	echo -e "Logs present at ${calico_telemetry_dir}/configmaps"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting IPAM diagnostics... ${NC}"
	mkdir -p ${calico_telemetry_dir}/ipam
	kubectl get ipamblocks -o yaml > ${calico_telemetry_dir}/ipam/ipamblocks.yaml
	kubectl get blockaffinities -o yaml > ${calico_telemetry_dir}/ipam/blockaffinities.yaml
	kubectl get ipamhandles -o yaml > ${calico_telemetry_dir}/ipam/ipamhandles.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/ipam"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting per-node calico-node logs... ${NC}"
	mkdir -p ${calico_diagnostics_dir}/per-node-calico-logs
	for node in $(kubectl get pods -n calico-system -l k8s-app=calico-node -o go-template --template="{{range .items}}{{.metadata.name}} {{end}}"); do
	        echo "Collecting logs for node: $node"
	        mkdir -p ${calico_diagnostics_dir}/per-node-calico-logs/${node}
	        kubectl logs --tail=${tail_lines} -n calico-system $node > ${calico_diagnostics_dir}/per-node-calico-logs/${node}/${node}.log
	        kubectl exec -n calico-system -t $node -- iptables-save -c > ${calico_diagnostics_dir}/per-node-calico-logs/${node}/iptables-save.txt
	        kubectl exec -n calico-system -t $node -- ip route > ${calico_diagnostics_dir}/per-node-calico-logs/${node}/iproute.txt
	        done
	echo -e "Logs present at ${calico_diagnostics_dir}/per-node-calico-logs"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting calico-typha logs... ${NC}"
	mkdir -p ${calico_diagnostics_dir}/calico-typha
	for typha in $(kubectl get pods -n calico-system -l k8s-app=calico-typha -o go-template --template="{{range .items}}{{.metadata.name}} {{end}}"); do
	        kubectl logs --tail=${tail_lines} -n calico-system $typha > ${calico_diagnostics_dir}/calico-typha/${typha}.log
	        done
	echo -e "Logs present at ${calico_diagnostics_dir}/calico-typha"
	echo -e "---------------------------------------------"


	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting Tier information... ${NC}"
	mkdir -p ${calico_telemetry_dir}/tiers
	kubectl get tier.projectcalico.org -o yaml > ${calico_telemetry_dir}/tiers/tiers.yaml
	tiers=`kubectl get tiers -o=custom-columns=NAME:.metadata.name --no-headers`
	echo -e "Logs present at ${calico_telemetry_dir}/tiers"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting network policy data for each tier... ${NC}"
	mkdir -p ${calico_telemetry_dir}/network-policies
	for tier in $tiers
	do 
	   kubectl get networkpolicies.p -A -l projectcalico.org/tier==$tier -o yaml > ${calico_telemetry_dir}/network-policies/$tier-np.yaml
	done
	echo -e "Logs present at ${calico_telemetry_dir}/network-policies"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting global network policies... ${NC}"
	mkdir -p ${calico_telemetry_dir}/global-network-policies
	kubectl get globalnetworkpolicies.projectcalico.org -o yaml > ${calico_telemetry_dir}/global-network-policies/global-network-policies.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/global-network-policies"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting bgp statistics... ${NC}"
	mkdir -p ${calico_telemetry_dir}/bgp-statistics
	kubectl get bgppeers.projectcalico.org -o yaml > ${calico_telemetry_dir}/bgp-statistics/bgppeers.yaml
	echo -e "Logs present at  ${calico_telemetry_dir}/bgp-statistics"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting cluster information... ${NC}"
	mkdir -p ${calico_telemetry_dir}/clusterinformations
	kubectl get clusterinformations.projectcalico.org -o yaml > ${calico_telemetry_dir}/clusterinformations/clusterinformations.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/clusterinformations"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting hostendpoints information... ${NC}"
	mkdir -p ${calico_telemetry_dir}/hostendpoints
	kubectl get hostendpoints.projectcalico.org -o yaml > ${calico_telemetry_dir}/hostendpoints/hostendpoints.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/hostendpoints"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting ippool information... ${NC}"
	mkdir -p ${calico_telemetry_dir}/ippools
	kubectl get ippools.projectcalico.org -o yaml > ${calico_telemetry_dir}/ippools/ippools.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/ippools"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting felixconfigurations... ${NC}"
	mkdir -p ${calico_telemetry_dir}/felixconfigurations
	kubectl get felixconfigurations.projectcalico.org -o yaml > ${calico_telemetry_dir}/felixconfigurations/felixconfigurations.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/felixconfigurations"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting licensekey data... ${NC}"
	mkdir -p ${calico_telemetry_dir}/licensekeys
	kubectl get licensekeys.projectcalico.org -o yaml > ${calico_telemetry_dir}/licensekeys/licensekeys.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/licensekeys"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting tigera components statistics (apiserver, calico, compliance, intrusion-detection, log-collector, log-storage, manager)... ${NC}"
	mkdir -p ${calico_telemetry_dir}/tigerastatus
	kubectl get tigerastatuses.operator.tigera.io -o yaml  > ${calico_telemetry_dir}/tigerastatus/tigerastatus-yaml.yaml
	kubectl get installations -o yaml > ${calico_telemetry_dir}/tigerastatus/installations.yaml
	kubectl get apiservers -o yaml > ${calico_telemetry_dir}/tigerastatus/apiservers.yaml
	kubectl get compliances -o yaml > ${calico_telemetry_dir}/tigerastatus/compliances.yaml
	kubectl get intrusiondetections -o yaml > ${calico_telemetry_dir}/tigerastatus/intrusiondetections.yaml
	kubectl get managers -o yaml > ${calico_telemetry_dir}/tigerastatus/managers.yaml
	kubectl get logcollectors -o yaml > ${calico_telemetry_dir}/tigerastatus/logcollectors.yaml
	kubectl get logstorages -o yaml > ${calico_telemetry_dir}/tigerastatus/logstorages.yaml
	kubectl get managementclusterconnections -o yaml > ${calico_telemetry_dir}/tigerastatus/managementclusterconnections.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/tigerastatus"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting networksets and global networksets data... ${NC}"
	mkdir -p ${calico_telemetry_dir}/networksets
	kubectl get networksets.projectcalico.org --all-namespaces -o yaml > ${calico_telemetry_dir}/networksets/networksets.yaml
	kubectl get globalnetworksets.crd.projectcalico.org -o yaml > ${calico_telemetry_dir}/networksets/global-networksets.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/networksets"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting managedclusters data... ${NC}"
	mkdir -p ${calico_telemetry_dir}/managedclusters
	kubectl get managedclusters.projectcalico.org -o yaml > ${calico_telemetry_dir}/managedclusters/managedclusters.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/managedclusters"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting kube-controllers configurations... ${NC}"
	mkdir -p ${calico_telemetry_dir}/kubecontrollersconfigurations
	kubectl get kubecontrollersconfigurations.projectcalico.org -o yaml > ${calico_telemetry_dir}/kubecontrollersconfigurations/kubecontrollersconfigurations.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/kubecontrollersconfigurations"
	echo -e "---------------------------------------------"

	echo -e "---------------------------------------------"
	echo -e "${YELLOW} Collecting globalalerts configurations... ${NC}"
	mkdir -p ${calico_telemetry_dir}/globalalerts
	kubectl get globalalerts.projectcalico.org -o yaml > ${calico_telemetry_dir}/globalalerts/globalalerts.yaml
	echo -e "Logs present at ${calico_telemetry_dir}/globalalerts"
	echo -e "---------------------------------------------"
}


function display_summary {
        echo -e "--------Summary of execution--------"
        ( IFS=$'\n'; echo -e "${success_array[*]}")
        echo -e "\n"
        echo -e "---------Error Notes---------"
        ( IFS=$'\n'; echo -e  "${failure_array[*]}")
        echo -e "\n"
#        if [ "$setup_type" == "Calico Enterprise" ] || 
#        then
        echo -e "---------------Note----------------"
	echo -e "Logs are present in ${calico_logs}  directory"
        echo -e "${YELLOW}${BOLD}Please send $currwd/calico-logs_${currdate}.tar.gz for Tigera team to investigate${NC}"
        echo -e "\n"
        if [ -f execution_summary ]; then mv execution_summary $currwd/calico-logs_${currdate}/; fi
#	mv calico-logs calico-logs_${currdate}
#	tar -czvf calico-logs.tar.gz -P $currwd/calico-logs/ >> /dev/null
	tar -czvf calico-logs_${currdate}.tar.gz  calico-logs_${currdate} >> /dev/null
#	fi

}

if [[ "$setup_type" == "Calico Enterprise" ]]
then
        echo -e "${YELLOW}${BOLD}Cluster type is $setup_type${NC}"
        check_operator_based
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
        copy_logs
	calico_telemetry
        display_summary
else
        echo -e "${YELLOW}${BOLD}Cluster type is $setup_type${NC}"
        check_operator_based
        check_kube_config
        check_kubeVersion
        check_cluster_pod_cidr
        check_kubeapiserver_status
        check_calico_pods
	copy_logs
        display_summary
fi

