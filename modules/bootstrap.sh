#!/bin/bash
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} WORKING ON BOOTSTRAPPING NODES ${NC} ";echo -e "=================================================\n"
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
source $ENV_FILE
export BASTION_HOSTNAME=$(nslookup ${BASTION_IP} | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | cut -d. -f1)
export USER_DIR="${VMSTORE_DIR}/${OWNER_NAME}/${CLUSTER_NAME}"
export PUBLIC_IP_LIST="${PUBLIC_IP_LIST//,/ }" 
IFS=' ' read -r -a ips_array <<< ${PUBLIC_IP_LIST}
BOOTSTRAP_HOSTNAME="${BASTION_HOSTNAME}-bootstrap"
BOOTSTRAP_IP=${ips_array[0]}
echo "======> Waiting for Boostraping to finish: "
echo "       (Monitoring activity on ${BOOTSTRAP_HOSTNAME})"
a_dones=()
a_conts=()
a_images=()
a_nodes=()
s_api="Down"
btk_started=0
no_output_counter=0

while true; do
    output_flag=0
    if [ "${s_api}" == "Down" ]; then
        $SSH_EXEC  root@${BASTION_IP} oc get --raw / &> /dev/null && \
            { echo "    ==> Kubernetes API is Up"; s_api="Up"; output_flag=1; } || true
    else
        nodes=($($SSH_EXEC  root@${BASTION_IP} oc get nodes 2> /dev/null | grep -v "^NAME" | awk '{print $1 "_" $2}' )) || true
        for n in ${nodes[@]}; do
            if [[ ! " ${a_nodes[@]} " =~ " ${n} " ]]; then
                echo "    --> Node $(echo $n | tr '_' ' ')"
                output_flag=1
                a_nodes+=( "${n}" )
            fi
        done
    fi
    images=($($SSH_EXEC  root@${BASTION_IP} "ssh -o StrictHostKeyChecking=no core@${BOOTSTRAP_IP} sudo podman images 2> /dev/null | grep -v '^REPOSITORY' | awk '{print \$1 \"-\" \$3}'" )) || true
    for i in ${images[@]}; do
        if [[ ! " ${a_images[@]} " =~ " ${i} " ]]; then
            echo "    --> Image Downloaded: ${i}"
            output_flag=1
            a_images+=( "${i}" )
        fi
    done
    dones=($($SSH_EXEC  root@${BASTION_IP} "ssh -o StrictHostKeyChecking=no core@${BOOTSTRAP_IP} ls /opt/openshift/*.done 2> /dev/null" )) || true
    for d in ${dones[@]}; do
        if [[ ! " ${a_dones[@]} " =~ " ${d} " ]]; then
            echo "    --> Phase Completed: $(echo $d | sed 's/.*\/\(.*\)\.done/\1/')"
            output_flag=1
            a_dones+=( "${d}" )
        fi
    done
    conts=($($SSH_EXEC  root@${BASTION_IP} "ssh -o StrictHostKeyChecking=no core@${BOOTSTRAP_IP} sudo crictl ps -a 2> /dev/null | grep -v '^CONTAINER' | rev | awk '{print \$4 \"_\" \$2 \"_\" \$3}' | rev" )) || true
    for c in ${conts[@]}; do
        if [[ ! " ${a_conts[@]} " =~ " ${c} " ]]; then
            echo "    --> Container: $(echo $c | tr '_' ' ')"
            output_flag=1
            a_conts+=( "${c}" )
        fi
    done

    btk_stat=$($SSH_EXEC  root@${BASTION_IP} "ssh -o StrictHostKeyChecking=no core@${BOOTSTRAP_IP}" "sudo systemctl is-active bootkube.service 2> /dev/null" ) || true
    test "$btk_stat" = "active" -a "$btk_started" = "0" && btk_started=1 || true

    test "$output_flag" = "0" && no_output_counter=$(( $no_output_counter + 1 )) || no_output_counter=0

    test "$no_output_counter" -gt "8" && \
        { echo "  --> (bootkube.service is ${btk_stat}, Kube API is ${s_api})"; no_output_counter=0; }

    test "$btk_started" = "1" -a "$btk_stat" = "inactive" -a "$s_api" = "Down" && \
        { echo '[Warning] Some thing went wrong. Bootkube service wasnt able to bring up Kube API'; }
        
    test "$btk_stat" = "inactive" -a "$s_api" = "Up" && break

    sleep 10
    
done

echo -e "\n=================================================";echo -e "\n======> Checking Openshfit Bootstrap Complete: ";echo -e "=================================================\n"
$SSH_EXEC root@${BASTION_IP} "./openshift-install --dir=/root/ocp-install wait-for bootstrap-complete"

echo;echo
echo -n "====> Removing Boostrap VM: "
    virsh destroy ${BASTION_HOSTNAME}-bootstrap > /dev/null || {
        "virsh destroy ${CLUSTER_NAME}-bootstrap failed"
         exit 1
         }
    virsh undefine ${BASTION_HOSTNAME}-bootstrap --remove-all-storage > /dev/null || {
        echo -e "ERROR: virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage"
        exit 1
        }
echo -e "${GREEN} DONE ${NC}" 



# Interval in seconds between checks
INTERVAL=10; TIMEOUT=1000; ELAPSED_TIME=0;
START_TIME=$(date +%s)
echo -e "\n=======================================================================================================";
echo -e "======> Monitoring CSRs and approving pending ones until all ${N_WORKERS} Worker nodes are Ready: ";
echo -e "=======================================================================================================\n"

while true; do
    pending_csrs=$($SSH_EXEC root@${BASTION_IP} "oc get csr --no-headers | awk '\$6 == \"Pending\" {print \$1}'")
    minutes=$((ELAPSED_TIME / 60))
    remaining_seconds=$((ELAPSED_TIME % 60))
    time_passed="${minutes}m${remaining_seconds}s"
    if [ -n "$pending_csrs" ]; then
        echo -e "    --> Elapsed $time_passed : Found Pending csr. Approving ..."
        $SSH_EXEC root@${BASTION_IP} "oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{\"\n\"}}{{end}}{{end}}' | xargs oc adm certificate approve >/dev/null 2>&1"
    else
        echo -e "    --> Elapsed $time_passed : No pending CSRs found. still waiting to become all Worker Nodes Ready .. "
    fi

    ready_nodes=$($SSH_EXEC root@${BASTION_IP} "oc get nodes --no-headers | grep worker | awk '\$2 == \"Ready\" {print \$1}' | wc -l")
    echo -e "    --> Elapsed $time_passed : ${GREEN} Ready nodes: $ready_nodes/$N_WORKERS ${NC}"
    if [ $ready_nodes -eq $N_WORKERS ];then
        break
    fi
    
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo -e "Elapsed $time_passed : ERROR Timeout reached. Some worker nodes are still not ready."
        exit 1
    fi
    sleep $INTERVAL
done


# Check Cluster Operators Ready
INTERVAL=15; TIMEOUT=1200; ELAPSED_TIME=0;
START_TIME=$(date +%s)
echo -e "\n=================================================";echo -e "======> Monitoring Openshift Cluster Operators: ";echo -e "=================================================\n"
while true; do
    list=$($SSH_EXEC root@${BASTION_HOSTNAME} "oc get co | awk -vcol=PROGRESSING '(NR==1){colnum=-1;for(i=1;i<=NF;i++)if(\$(i)==col)colnum=i;}{print \$(colnum)}' | grep -v PROGRESSING | grep True | xargs")
    minutes=$((ELAPSED_TIME / 60))
    remaining_seconds=$((ELAPSED_TIME % 60))
    time_passed="${minutes}m${remaining_seconds}s"
    if [[ -n "$list" ]]; then
        opr_list=$($SSH_EXEC root@${BASTION_HOSTNAME} "oc get co | awk '{print \$1 , \$4}' | grep True | awk '{print \$1}' | xargs")
        echo -e "    --> Elapsed $time_passed : still waiting on operators : ${opr_list}"
    else
        echo -e "    --> Elapsed $time_passed : ${GREEN} Looks Like all ooperators Are Ready. Done. ${NC}"
        break
    fi
    

    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo -e "Elapsed $time_passed : ERROR Timeout reached. Some Openshift Operators are still Not Ready."
        exit 1
    fi
    sleep $INTERVAL

done

echo -e "\n======> Checking Openshfit Install Complete: \n"
$SSH_EXEC root@${BASTION_IP} "./openshift-install --dir=/root/ocp-install wait-for install-complete"
$SSH_EXEC root@${BASTION_IP} "rm -f /root/openshift-*"
$SSH_EXEC root@${BASTION_IP} "rm -f /var/www/html/${CLUSTER_NAME}/rhcos-live*"

VERSION=$($SSH_EXEC root@${BASTION_HOSTNAME} "oc get clusterversion | awk -vcol=VERSION '(NR==1){colnum=-1;for(i=1;i<=NF;i++)if(\$(i)==col)colnum=i;}{print \$(colnum)}' | grep -v VERSION")
CONSOLE=$($SSH_EXEC root@${BASTION_HOSTNAME} "oc whoami --show-console")
echo; $SSH_EXEC root@${BASTION_HOSTNAME} "oc get nodes"


echo -e "\n======> Updating Redhat server Credential on Cluster: "
CONNECT_BASTION="$SSH_EXEC root@${BASTION_IP}"
$CONNECT_BASTION "oc get secret/pull-secret -n openshift-config --template='{{index .data \".dockerconfigjson\" | base64decode}}' > global_pull_secret.yaml"
$CONNECT_BASTION "oc registry login --registry=\"registry.redhat.io\" --auth-basic=\"<user:password>\" --to=global_pull_secret.yaml"
$CONNECT_BASTION "oc registry login --registry=\"registry.connect.redhat.com\" --auth-basic=\"vtas-eng:V4La@24!\" --to=global_pull_secret.yaml"
$CONNECT_BASTION "oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=global_pull_secret.yaml"


echo -e "\n======> Finished.  Kindly Monitor MCP:   oc get mcp"


echo -e "\n\n###############################################################################################"
echo -e "#                                                         "
echo -e "#  |   OPENSHIFT INSTALL COMPLETE                         "
echo -e "#  |   VERSION      :  ${VERSION}                         "
echo -e "#  |   BASTION_HOST :  ${BASTION_IP} ${BASTION_HOSTNAME}  "
echo -e "#  |   CONSOLE      :  ${CONSOLE}                         "
echo -e "#                                                         "
echo -e "###############################################################################################"

