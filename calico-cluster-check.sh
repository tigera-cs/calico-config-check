#!/bin/bash

grep_filter="grep -i error"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
kubeconfig=$HOME/.kube/config
failure_array=()
success_array=()


function check_kube_config {
        echo -e "-------Checking and exporting kubconfig-------"
        if [ -f $kubeconfig ]
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
                echo -e "The client version is $client_version"
                echo -e "The server version is $server_version\n"
                echo -e "\n"

}

function check_cluster_pod_cidr {
                echo -e "-------Checking Cluster and Pod CIDRs-------"
                cluster_cidr=`kubectl cluster-info dump | grep -i "\-\-cluster\-cidr" |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                pod_cidr=`kubectl get ippool -o yaml | grep cidr | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                if [ "$cluster_cidr" == "$pod_cidr" ]
                then
                        echo -e "The Cluster CIDR and Pod CIDR match, current Cluster CIDR is $cluster_cidr and Pod CIDR is $pod_cidr"
                        success_array+=("$GREEN Cluster CIDR check passed $NC")
                else

                        echo -e "$RED Please make sure the Cluter and Pod CIDR match $NC, current Cluster CIDR is $cluster_cidr and Pod CIDR is $pod_cidr"
                        failure_array+=("$RED Cluster CIDR check failed $NC")
                fi
                echo -e "\n"
}

function check_tigera_version {
        echo -e "-------Checking Calico Enterprise Version-------"
        calico_enterprise_version=`kubectl get clusterinformations.projectcalico.org default -o yaml | grep -i "cnxVersion" | awk '{print $2}'`
        echo -e "Calico Enterprise version is $calico_enterprise_version"
        echo -e "\n"
}

function check_tigera_license {
        license_name=`kubectl get licensekeys.projectcalico.org -o yaml | grep name | awk '{print $2}'`
        if [[ -n $license_name ]]
        then
                expiry=`kubectl get licensekeys.projectcalico.org default -o yaml | grep -i "expiry" | awk '{print $2}'`
                expiry=${expiry%T*}
                expiry=${expiry#\"}
                date=$(date '+%Y-%m-%d')
                if [[ $date <  $expiry ]]
                then
                        echo -e "$GREEN Calico Enterprise license is valid till $expiry $NC"
                        success_array+=("$GREEN Calico Enterprise license is valid till $expiry $NC")
                else
                        echo -e "$RED Calico Enterprise license has expired $NC on $expiry"
                        failure_array+=("$RED Calico Enterprise license has expired $NC on $expiry $NC")
                fi
        elif [[ $license_name == "" ]]
        then
                echo -e "$RED Calico enterprise license is not applied $NC"
                failure_array+=("$RED Calico enterprise license is not applied $NC")
        fi
}



function check_tigerastatus {
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

function check_es_pv_status {
                echo -e "-------Checking Elasticsearch PV bound status-------"
                bound_status=`kubectl get pv | grep 'tigera-elasticsearch' | awk '{print $5}'`
                if [ "$bound_status" == "Bound" ]
                then
                        echo -e "Elasticsearch PV is bounded"
                        success_array+=("$GREEN Elasticsearch PV is bounded $NC")
                else
                        echo -e "$RED Elasticsearch PV is not bouded $NC"
                        failure_array+=("$RED Elasticsearch PV is not bouded $NC")
                fi
                echo -e "\n"
}

function check_tigera_namespaces {
                echo -e "-------- Checking if all Tigera specific namespaces are present -------"
                tigera_namespaces=`kubectl get ns | grep tigera | wc -l`
                if [ "$tigera_namespaces" == "10" ]
                then
                        echo -e "All tigera namespaces are present"
                        success_array+=("$GREEN All tigera namespaces are present $NC")
                else
                        echo -e "$RED All Tigera namespaces are not present $NC"
                        ailure_array+=("$RED All Tigera namespaces are not present $NC")
                fi
                echo -e "\n"

}

function check_apiserver_status {
                echo -e "-------Checking kube-apiserver and tigera-apiserver status-------"
                tigera_apiserver=`kubectl get po -l k8s-app=tigera-apiserver -n tigera-system | awk 'NR==2{print $3}'`
                kube_apiserver=`kubectl get po -l component=kube-apiserver -n kube-system | awk 'NR==2{print $3}'`
                if [ "$kube_apiserver" == "Running" ]
                then 
                        echo -e "kube-apiserver pod is $kube_apiserver"
                        success_array+=("$GREEN kube-apiserver pod is $kube_apiserver $NC")
                elif [ "$kube_apiserver" ! "Running" ]
                then
                        echo -e "$RED kube-apiserver pod is $kube_apiserver $NC"
                        failure_array+=("$RED kube-apiserver pod is $kube_apiserver $NC")
                fi
                        if [ "$tigera_apiserver" == "Running" ]
                then
                        echo -e "tigera-apiserver pod is $tigera_apiserver"
                        success_array+=("$GREEN tigera-apiserver pod is $tigera_apiserver $NC")
                elif [ "$tigera_apiserver" ! "Running" ]
                then
                        echo -e "$RED tigera-apiserver pod is $tigera_apiserver $NC"
                        failure_array+=("$RED tigera-apiserver pod is $tigera_apiserver $NC")
                fi
                echo -e "\n"
}

function check_calico_pods {
                echo -e "-------Checking calico-node deamonset status-------"
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
                        echo -e "$RED calico-node deamonset is not up to date, desired pods are $desired_pod_count and current pods are $current_pod_count $NC"
                        failure_array+=("$RED calico-node deamonset is not up to date $NC")

                fi
                echo -e "\n"
                echo -e "-------Checking calico-node pod logs-------"
                kubectl logs -l k8s-app=calico-node -n calico-system | $grep_filter >> calico_node_error_logs
                [ -s calico_node_error_logs ]
                if [ $? == 0 ]
                then
                        cp calico_node_error_logs /tmp/
                        echo -e "$RED Error logs found, logs present in file /tmp/calico_node_logs $NC"
                        failure_array+=("$RED calico-node : Error logs found, logs present in file /tmp/calico_node_logs $NC")
                        rm calico_node_error_logs
                else
                        echo -e "No errors found in calico-node pods"

                fi
                echo "Complete calico-node logs are dumped at /tmp/calico_node_logs"
                kubectl logs -l k8s-app=calico-node -n calico-system >> /tmp/calico_node_logs
                echo -e "\n"

}

function check_tigera_pods {
        tigera_apps=( tigera-manager tigera-operator )
        for i in "${tigera_apps[@]}"
        do
                echo -e "-------$i pod status-------"
                kubectl get po -n $i -l k8s-app=$i -o wide
                echo -e "\n"
                echo -e "-------Checking $i pod logs-------"
                kubectl logs -n $i -l k8s-app=$i -c $i | $grep_filter  >> ${i}_error_logs
                [ -s ${i}_error_logs ]
                if [ $? == 0 ]
                then
                        cp ${i}_error_logs /tmp/
                        echo -e "$RED Error logs found, logs present in file /tmp/${i}_error_logs $NC"
                        failure_array+=("$RED ${i} : Error logs found, logs present in file /tmp/ /tmp/${i}_error_logs $NC")
                        rm ${i}_error_logs
                else
                        kubectl logs -n $i -l k8s-app=$i -c $i >> /tmp/${i}_logs
                        echo -e "No errors found in ${i}, logs present at /tmp/${i}_logs"
                fi
                echo -e "\n"
        done
        echo -e "-------tigera-kibana pod status-------"
        kubectl get po -n tigera-kibana -l k8s-app=tigera-secure -o wide
        echo -e "\n"
        echo -e "-------Checking tigera-kibana pod logs-------"
        kubectl logs -n tigera-kibana -l k8s-app=tigera-secure | $grep_filter  >> tigera_secure_error_logs
        [ -s tigera_secure_error_logs ]
        if [ $? == 0 ]
        then
                cp tigera_secure_error_logs /tmp/
                echo -e "$RED Error logs found, logs present in file /tmp/tigera_secure_error_logs $NC"
                failure_array+=("$RED tigera-secure : tigera-secure Error logs found, logs present in file /tmp/tigera_secure_error_logs $NC")
                rm tigera_secure_error_logs
        else
                kubectl logs -n tigera-kibana -l k8s-app=tigera-secure >> /tmp/tigera_secure_logs
                echo -e "No errors found in tigera_secure, logs present at /tmp/tigera_secure_logs"
        fi
        echo -e "\n"
        echo -e "-------tigera-fluentd pod status-------"
        kubectl get po -n tigera-fluentd -l k8s-app=fluentd-node -o wide
        echo -e "\n"
        echo -e "-------Checking tigera-fluentd pod logs-------"
        kubectl logs -n tigera-fluentd -l k8s-app=fluentd-node | $grep_filter  >> fluentd_node_error_logs
        [ -s fluentd_node_error_logs ]
        if [ $? == 0 ]
        then
                cp fluentd_node_error_logs /tmp/
                echo -e "$RED Error logs found, logs present in file /tmp/fluentd_node_error_logs $NC"
                rm fluentd_node_error_logs
        else
                 kubectl logs -n tigera-fluentd -l k8s-app=fluentd-node >> /tmp/fluentd_node_logs
                 echo -e "No errors found in fluentd-node, logs present at /tmp/fluentd_node_logs"
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

function calico_diagnostics {
	echo -e "--------Calico Diagnostics----------"
	sudo curl -o /usr/local/bin/kubectl-calico https://docs.tigera.io/v2.8/maintenance/kubectl-calico -s
	sudo chmod +x /usr/local/bin/kubectl-calico
	currwd=`pwd`
	log_time=`date +'%m-%d-%y--%H:%M'`
#	echo $currwd
	kubectl calico diags
	mv /tmp/tmp.* $currwd/diag_logs_$log_time
}

function display_summary {
        echo -e "--------Summary of execution--------"
        echo -e "Success results"
        ( IFS=$'\n'; echo -e "${success_array[*]}")
        echo -e "\n"
        echo -e "Failed results"
        ( IFS=$'\n'; echo -e  "${failure_array[*]}")
}

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
