#!/bin/bash
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
source $ENV_FILE
export BASTION_HOSTNAME=$(nslookup ${BASTION_IP} | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | cut -d. -f1)
export USER_DIR="${VMSTORE_DIR}/${OWNER_NAME}/${CLUSTER_NAME}"
if [ -z $USER_DIR ];then
    echo "ERROR: USER_DIR should not be empty"
    exit 1
fi
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} DESTROY NODES ${NC} ";echo -e "=================================================\n"
    echo -n "======> Checking if any VMs available on KVM Host with Name : ${BASTION_HOSTNAME}: "
    vms_list=`virsh list --all --name | grep -i ${BASTION_HOSTNAME}`
    if [ -n "${vms_list}" ];then
        echo -e "\n        Found Available VMs:"
        for m in $vms_list;do
            echo -n "        Deleting $m:"
            virsh destroy $m 2>/dev/null 1>/dev/null;
            virsh undefine $m --remove-all-storage 2>/dev/null 1>/dev/null;
            echo -e "${GREEN} Done ${NC}"
        done
    else
        echo -e "${GREEN} No VMs Found ${NC}"
    fi

    if [ -d ${USER_DIR} ];then
    echo -n "======> Checking if User Directory = ${USER_DIR} has stale files:"
    rm -f ${USER_DIR}/*.qcow2 
    rm -f ${USER_DIR}/haproxy.cfg
    rm -f ${USER_DIR}/install-config.yaml
    fi
    echo -e "${GREEN} Done ${NC}"

