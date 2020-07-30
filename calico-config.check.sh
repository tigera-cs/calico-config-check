#!/bin/bash

grep_filter="grep -i error"
RED='\033[0;31m'
NC='\033[0m'
kubeconfig=$HOME/.kube/config

function check_kube_config {
        echo -e "-------Checking and exporting kubconfig-------"
        echo -e "\n"
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
                echo -e "\n"
                client_version=`kubectl version --short | awk 'NR==1{print $3}'`
                server_version=`kubectl version --short | awk 'NR==2{print $3}'`
                echo -e "The client version is $client_version"
                echo -e "The server version is $server_version\n"

           }

function check_cluster_pod_cidr {
                echo -e "-------Checking Cluster and Pod CIDRs-------"
                echo -e "\n"
                cluster_cidr=`kubectl cluster-info dump | grep -i "\-\-cluster\-cidr" |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                pod_cidr=`kubectl get ippool -o yaml | grep cidr | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                if [ "$cluster_cidr" == "$pod_cidr" ]
                then
                        echo -e "The Cluster CIDR and Pod CIDR match, current Cluster CIDR is $cluster_cidr and Pod CIDR is $pod_cidr"
                else

                        echo -e "$RED Please make sure the Cluter and Pod CIDR match $NC, current Cluster CIDR is $cluster_cidr and Pod CIDR is $pod_cidr"
                fi
                echo -e "\n"
}

function check_tigerastatus {
                echo -e "-------Checking Tigera Components-------"
                echo -e "\n"
                tigera_components=(apiserver calico compliance intrusion-detection log-collector log-storage manager)
                for i in "${tigera_components[@]}"
                do
                        available=`kubectl get tigerastatus | grep $i | awk '{print $2}'`
                        if [ "$available" == "True"  ]
                        then
                                echo -e "$i status is $available"
                        elif [ "$available" == "False"  ]
                        then
                                echo -e "$RED $i status is $available $NC"
                        fi
                done
                echo -e "\n"

}

function check_es_pv_status {
                echo -e "-------Checking Elasticsearch PV bound status-------"
                echo -e "\n"
                bound_status=`kubectl get pv | grep 'tigera-elasticsearch' | awk '{print $5}'`
                if [ "$bound_status" == "Bound" ]
                then
                        echo -e "Elasticsearch PV is bounded"
                else
                        echo -e "$RED Elasticsearch PV is not bouded $NC"
                fi
                echo -e "\n"
}

function check_tigera_namespaces {
#       tigera_namespaces=(tigera-compliance tigera-eck-operator tigera-elasticsearch tigera-fluentd tigera-intrusion-detection  tigera-kibana  tigera-manager tigera-operator tigera-prometheus tigera-system)
        echo -e "-------- Checking if all Tigera specific namespaces are present -------"
        echo -e "\n"
        tigera_namespaces=`kubectl get ns | grep tigera | wc -l`
        if [ "$tigera_namespaces" == "10" ]
        then
                echo -e "All tigera namespaces are present"
        else
                echo -e "$RED All Tigera namespaces are not present $NC"
        fi
        echo -e "\n"

}

function check_apiserver_status {
        echo -e "-------Checking kube-apiserver and tigera-apiserver status-------"
        echo -e "\n"
        tigera_apiserver=`kubectl get po -l k8s-app=tigera-apiserver -n tigera-system | awk 'NR==2{print $3}'`
        kube_apiserver=`kubectl get po -l component=kube-apiserver -n kube-system | awk 'NR==2{print $3}'`
        if [ "$kube_apiserver" == "Running" ]
        then 
                echo -e "kube-apiserver pod is $kube_apiserver"
        elif [ "$kube_apiserver" ! "Running" ]
        then
                echo -e "$RED kube-apiserver pod is $kube_apiserver $NC"
        fi
        if [ "$tigera_apiserver" == "Running" ]
        then
                echo -e "tigera-apiserver pod is $tigera_apiserver"
        elif [ "$tigera_apiserver" ! "Running" ]
        then
                echo -e "$RED tigera-apiserver pod is $tigera_apiserver $NC"
        fi
        echo -e "\n"
}

function check_calico_pods {
        echo -e "-------Checking calico-node deamonset status-------"
        echo -e "\n"
        desired_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $2}'`
        current_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $3}'`
        ready_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $4}'`
        uptodate_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $5}'`
        available_pod_count=`kubectl get ds calico-node -n calico-system | awk 'NR==2{print $6}'`
        if [ "$desired_pod_count" == "$current_pod_count" ] && [ "$desired_pod_count" == "$ready_pod_count" ] && [ "$desired_pod_count" == "$uptodate_pod_count" ] && [ "$desired_pod_count" == "$available_pod_count"  ]
        then
                echo -e "calico-node deamonset is up to date, desired pods are $desired_pod_count and current pods are $current_pod_count"
        else
                echo -e "$RED calico-node deamonset is not up to date, desired pods are $desired_pod_count and current pods are $current_pod_count $NC"

        fi
        echo -e "\n"
        echo -e "-------Checking calico-node pod logs-------"
        echo -e "\n"
        kubectl logs -l k8s-app=calico-node -n calico-system | $grep_filter >> calico_node_logs
        [ -s calico_node_logs ]
        if [ $? == 0 ]
        then
                cp calico_node_logs /tmp/
                echo -e "$RED Error logs found, logs present in file /tmp/calico_node_logs $NC"
                rm calico_node_logs
        else
                echo -e "No errors found"
        fi
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
                echo -e "\n"
                kubectl logs -n $i -l k8s-app=$i -c $i | $grep_filter  >> $i
                [ -s $i ]
                if [ $? == 0 ]
                then
                        cp $i /tmp/
                        echo -e "$RED Error logs found, logs present in file /tmp/$i $NC"
                        rm $i
                else
                        echo -e "No errors found"
                fi
                echo -e "\n"
        done
        echo -e "-------tigera-kibana pod status-------"
        kubectl get po -n tigera-kibana -l k8s-app=tigera-secure -o wide
        echo -e "\n"
        echo -e "-------Checking tigera-kibana pod logs-------"
        echo -e "\n"
        kubectl logs -n tigera-kibana -l k8s-app=tigera-secure | $grep_filter  >> tigera-secure
        [ -s tigera-secure ]
        if [ $? == 0 ]
        then
                cp tigera-secure /tmp/
                echo -e "$RED Error logs found, logs present in file /tmp/tigera-secure $NC"
                rm tigera-secure
        else
                 echo -e "No errors found"
        fi
        echo -e "\n"
        echo -e "-------tigera-fluentd pod status-------"
        kubectl get po -n tigera-fluentd -l k8s-app=fluentd-node -o wide
        echo -e "\n"
        echo -e "-------Checking tigera-fluentd pod logs-------"
        echo -e "\n"
        kubectl logs -n tigera-fluentd -l k8s-app=fluentd-node | $grep_filter  >> fluentd-node
        [ -s fluentd-node ]
        if [ $? == 0 ]
        then
                cp fluentd-node /tmp/
                echo -e "$RED Error logs found, logs present in file /tmp/fluentd-node $NC"
                rm fluentd-node
        else
                 echo -e "No errors found"
        fi
        echo -e "\n"




}

function check_tier {
        echo -e "-------checking allow-tigera tier-------"
        echo -e "\n"
        tier_name=`kubectl get tier allow-tigera | awk 'NR==2{print $1}'`
        if [ "$tier_name" == "allow-tigera" ]
        then
                echo -e "Tier allow-tigera  is present"
        else
                echo -e "$RED Check if tier allow-tigera is created $NC"
        fi
        echo -e "\n"
}

check_kube_config
check_kubeVersion
check_cluster_pod_cidr
check_tigerastatus
check_es_pv_status
check_tigera_namespaces
check_apiserver_status
check_calico_pods
check_tigera_pods
check_tier
