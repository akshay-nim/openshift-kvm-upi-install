#!/bin/bash
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} CREATING RHCOS NODES ${NC} ";echo -e "=================================================\n"
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
source $ENV_FILE
export BASTION_HOSTNAME=$(nslookup ${BASTION_IP} | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | cut -d. -f1)
export PUBLIC_IP_LIST="${PUBLIC_IP_LIST//,/ }" 
export USER_DIR="${VMSTORE_DIR}/${OWNER_NAME}/${CLUSTER_NAME}"

wait_ip(){
    echo -e "======> Waiting to assign IP for Node $1: "
    TIMEOUT=300; INTERVAL=2;     START_TIME=$(date +%s)
    while true; do
    if ping -c 1 "${1}" &> /dev/null; then
        echo -e "        Server ${1} ${GREEN}is up ${NC}"
        break
    else
        echo -e "        Waiting for server ${1} to be up..."
    fi
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
        echo -e "\n      ERROR: Time limit reached. Server ${1} is still down."
        exit 1
    fi 

    sleep "$INTERVAL" 
done
}

# Generate Array for IP's 
IFS=' ' read -r -a ips_array <<< ${PUBLIC_IP_LIST}

# Generate Guest node names Array
hostname_array=()
hostname_array+=("${BASTION_HOSTNAME}-bootstrap")
for i in $(seq 1 ${N_MASTERS});do
hostname_array+=("${BASTION_HOSTNAME}-m-${i}"); done
for i in $(seq 1 ${N_WORKERS});do
hostname_array+=("${BASTION_HOSTNAME}-w-${i}"); done

worker_index_begin=`expr 1 + ${N_MASTERS}`
worker_index_end=`expr ${N_WORKERS} + ${N_MASTERS}`

bootstrap_mem=$(expr ${BOOT_MEM} \* 1024)
master_mem=$(expr ${MAS_MEM} \* 1024)
worker_mem=$(expr ${WOR_MEM} \* 1024)

BOOTSTRAP_IGNITION_URL="http://${BASTION_IP}:8080/${CLUSTER_NAME}/bootstrap.ign"
MASTER_IGNITION_URL="http://${BASTION_IP}:8080/${CLUSTER_NAME}/master.ign"
WORKER_IGNITION_URL="http://${BASTION_IP}:8080/${CLUSTER_NAME}/worker.ign"
ROOTFS_URL="http://${BASTION_IP}:8080/${CLUSTER_NAME}/rhcos-live-rootfs.x86_64.img"


echo -n "======> Creating Bootstrap Node : ${BASTION_HOSTNAME}-bootstrap : ${ips_array[0]} : "
virt-install --name ${BASTION_HOSTNAME}-bootstrap \
             --disk ${USER_DIR}/${BASTION_HOSTNAME}-bootstrap-bs.qcow2,size=${BOOT_BOOTDISK} \
             --ram ${bootstrap_mem} \
             --cpu host --vcpus ${BOOT_CPU}  \
             --os-variant generic \
             --network bridge=${VIR_NET} \
	     --wait 0 --graphics vnc,listen=0.0.0.0 \
             --console pty,target_type=serial --location ${USER_DIR}/rhcos-live.x86_64.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz \
             --extra-args "coreos.inst.install_dev=sda coreos.live.rootfs_url=${ROOTFS_URL} ip=${ips_array[0]}::${GATEWAY}:255.255.240.0:${BASTION_HOSTNAME}-bootstrap::none nameserver=${DNS} coreos.inst.ignition_url=${BOOTSTRAP_IGNITION_URL} coreos.inst.insecure=yes" >/dev/null 2>&1
echo -e "${GREEN} OK ${NC}"


for ((i=1; i<=${N_MASTERS}; i++));do
    echo -n "======> Creating Master Node : ${hostname_array[$i]} : ${ips_array[$i]} : "
    virt-install --name ${hostname_array[$i]} --disk ${USER_DIR}/${BASTION_HOSTNAME}-m-$i.qcow2,size=${MAS_BOOTDISK} --ram ${master_mem} --cpu host --vcpus ${MAS_CPU} --os-variant generic --network bridge=${VIR_NET} --wait 0 --graphics vnc,listen=0.0.0.0 --console pty,target_type=serial --location ${USER_DIR}/rhcos-live.x86_64.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz --extra-args "coreos.inst.install_dev=sda coreos.live.rootfs_url=${ROOTFS_URL} ip=${ips_array[$i]}::${GATEWAY}:255.255.240.0:${hostname_array[$i]}::none nameserver=${DNS} coreos.inst.ignition_url=${MASTER_IGNITION_URL} coreos.inst.insecure=yes" >/dev/null 2>&1
    echo -e "${GREEN} OK ${NC}"
done


for ((i=${worker_index_begin}; i<=${worker_index_end}; i++));do
    echo -n "======> Creating Worker Node : ${hostname_array[$i]} : ${ips_array[$i]} : "
    virt-install --name ${hostname_array[$i]} --disk ${USER_DIR}/${BASTION_HOSTNAME}-w-$i.qcow2,size=${WOR_BOOTDISK} --ram ${worker_mem} --cpu host --vcpus ${WOR_CPU} --os-variant generic --network bridge=${VIR_NET} --wait 0 --graphics vnc,listen=0.0.0.0 --console pty,target_type=serial --location ${USER_DIR}/rhcos-live.x86_64.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz --extra-args "coreos.inst.install_dev=sda coreos.live.rootfs_url=${ROOTFS_URL} ip=${ips_array[$i]}::${GATEWAY}:255.255.240.0:${hostname_array[$i]}::none nameserver=${DNS} coreos.inst.ignition_url=${WORKER_IGNITION_URL} coreos.inst.insecure=yes" >/dev/null 2>&1
    echo -e "${GREEN} OK ${NC}"
done


echo -e "\n======> Waiting for RHCOS Installation to finish: "
timeout=900; cnt=0
while rvms=$(virsh list --name | grep "${BASTION_HOSTNAME}" | grep -v bastion 2> /dev/null); do
    sleep 5
    echo "    --> VMs with pending installation: $(echo "$rvms" | tr '\n' ' ')"
    cnt=`expr $cnt + 5`
    if [ $cnt -ge $timeout ];then
        echo -e "\n\n\t ERROR: RHCOS installation on Nodes failed . Kindly Validate on Boot Console on Nodes.\n"
        exit 1
    fi
done

# Start VMs
for vm in ${hostname_array[@]};do
    echo -n "======> Starting VM $vm: "
    virsh start ${vm} > /dev/null
    echo -e "${GREEN} OK ${NC}"
done

# Check Nodes are UP
for ip in $PUBLIC_IP_LIST;do
    wait_ip $ip
done

# Delete files now as Nodes are Provisioned
rm -f ${USER_DIR}/rhcos-live-rootfs.x86_64.img
rm -f ${USER_DIR}/rhcos-live.x86_64.iso
rm -f ${USER_DIR}/openshift-install-linux.tar.gz
rm -f ${USER_DIR}/openshift-client-linux.tar.gz
rm -f ${USER_DIR}/install/*.qcow2



