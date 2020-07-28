#!/bin/bash

function kubeVersion {
                echo "-------Checking Kubernetes Client and Server version-------"
                echo -e "\n"
                client_version=`kubectl version --short | awk 'NR==1{print $3}'`
                server_version=`kubectl version --short | awk 'NR==2{print $3}'`
                echo "The client version is $client_version"
                echo -e "The server version is $server_version\n"

           }

function validate_cluster_pod_cidr {
                echo "-------Checking Cluster and Pod CIDRs-------"
                echo -e "\n"
                cluster_cidr=`kubectl cluster-info dump | grep -i "\-\-cluster\-cidr" |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                pod_cidr=`kubectl get ippool -o yaml | grep cidr | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[1-9]\{1,2\}'`
                if [ "$cluster_cidr" == "$pod_cidr" ]
                then
                        echo "The Cluster CIDR and Pod CIDR match, current Cluster CIDR is $cluster_cidr and Pod CIDR is $pod_cidr"
                else

                        echo "Please make sure the Cluter and Pod CIDR match, current Cluster CIDR is $cluster_cidr and Pod CIDR is $pod_cidr"
                fi
                echo -e "\n"
}

function check_tigerastatus {
                echo "-------Checking Tigera Components-------"
                echo -e "\n"
                apiserver_status=`kubectl get tigerastatus | awk 'NR==2{print $2}'`
                calico_status=`kubectl get tigerastatus | awk 'NR==3{print $2}'`
                compliance_status=`kubectl get tigerastatus | awk 'NR==4{print $2}'`
                intrusion_detection_status=`kubectl get tigerastatus | awk 'NR==5{print $2}'`
                log_collector_status=`kubectl get tigerastatus | awk 'NR==6{print $2}'`
                log_storage_status=`kubectl get tigerastatus | awk 'NR==7{print $2}'`
                manager_status=`kubectl get tigerastatus | awk 'NR==8{print $2}'`

                if [ "$apiserver_status" == "True"  ]   
                then
                        echo "Apiserver status is $apiserver_status"
                elif [ "$apiserver_status" == "False"  ]
                then
                        echo "Apiserver status is $apiserver_status"
                fi
                if [ "$calico_status" == "True" ]
                then
                        echo "Calico status is $calico_status"
                elif [ "$calico_status" == "False" ]
                then
                        echo "Calico status is $calico_status"
                fi
                if [ "$compliance_status" == "True" ]
                then
                        echo "Compliance status is $compliance_status"
                elif [ "$compliance_status" == "False" ] 
                then
                        echo "Compliance status is $compliance_status"
                fi
                if [ "$intrusion_detection_status" == "True" ]
                then
                        echo "Intrusion Detection status is $intrusion_detection_status"
                elif [ "$intrusion_detection_status" == "False" ]
                then
                        echo "Intrusion Detection status is $intrusion_detection_status"
                fi
                if [ "$log_collector_status" == "True" ]
                then
                        echo "Log collector status is $log_collector_status"
                elif [ "$log_collector_status" == "False" ]
                then
                        echo "Log collector status is $log_collector_status"
                fi
                if [ "$log_storage_status" == "True" ]
                then
                        echo "Log storage status is $log_storage_status"
                elif [ "$log_storage_status" == "False" ]
                then
                        echo "Log storage status is $log_storage_status"
                fi
                if [ "$manager_status" == "True" ]
                then
                        echo "Manager status is $manager_status"
                elif [ "$manager_status" == "False" ]
                then
                        echo "Manager status is $manager_status"
                fi
                echo -e "\n"

}

function check_es_pv_status {
                echo "-------Checking Elasticsearch PV bound status-------"
                echo -e "\n"
                bound_status=`kubectl get pv | grep 'tigera-elasticsearch' | awk '{print $5}'`
                if [ "$bound_status" == "Bound" ]
                then
                        echo "Elasticsearch PV is bounded"
                else
                        echo "Elasticsearch PV is not bouded"
                fi
                echo -e "\n"
}

function tigera_namespaces {
#       tigera_namespaces=(tigera-compliance tigera-eck-operator tigera-elasticsearch tigera-fluentd tigera-intrusion-detection  tigera-kibana  tigera-manager tigera-operator tigera-prometheus tigera-system)
        echo "-------- Checking if all Tigera specific namespaces are present -------"
        echo -e "\n"
        tigera_namespaces=`kubectl get ns | grep tigera | wc -l`
        if [ "$tigera_namespaces" == "10" ]
        then
                echo "All tigera namespaces are present"
        else
                echo "All Tigera namespaces are not present"
        fi
        echo -e "\n"

}

kubeVersion
validate_cluster_pod_cidr
check_tigerastatus
check_es_pv_status
tigera_namespaces
