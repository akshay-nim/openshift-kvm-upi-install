#!/bin/bash
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} CREATING BASTION NODE ${NC} ";echo -e "=================================================\n"
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
source $ENV_FILE
export BASTION_HOSTNAME=$(nslookup ${BASTION_IP} | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | cut -d. -f1)
export PUBLIC_IP_LIST="${PUBLIC_IP_LIST//,/ }" 
export USER_DIR="${VMSTORE_DIR}/${OWNER_NAME}/${CLUSTER_NAME}"
[ ! -f ${BASTION_TEMPLATE} ] && {
	echo -e "\n\t ERROR: ${BASTION_TEMPLATE} doens exist on KVM\n"
	exit 1
}
print_header() {
    printf "%-30s %-20s %-5s %-5s\n" "------------------------" "---------------"  "-------" "------------"
    printf "%-30s %-20s %-5s %-5s\n" "     VM NAME " "      IP " " MEMORY " "BOOT DISK "
    printf "%-30s %-20s %-5s %-5s\n" "------------------------" "---------------"  "-------" "------------"
}

print_row() {
    printf "%-30s %-20s %-10s %-10s\n" "$1" "$2" "$3" "$4"
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


print_header
print_row "${BASTION_HOSTNAME}-bastion" "${BASTION_IP}" " ${BASTION_MEM} GB" " 15 GB"
print_row "${BASTION_HOSTNAME}-bootstrap" "${ips_array[0]}" " ${BOOT_MEM} GB" " ${BOOT_BOOTDISK} GB"
for ((i=1; i<=${N_MASTERS}; i++));do
    print_row "${hostname_array[$i]}" "${ips_array[$i]}" " ${MAS_MEM} GB" " ${MAS_BOOTDISK} GB"
done

worker_index_begin=`expr 1 + ${N_MASTERS}`
worker_index_end=`expr ${N_WORKERS} + ${N_MASTERS}`

for ((i=${worker_index_begin}; i<=${worker_index_end}; i++));do
    print_row "${hostname_array[$i]}" "${ips_array[$i]}" " ${WOR_MEM} GB" " ${WOR_BOOTDISK} GB"
done

cp ${BASTION_TEMPLATE} $USER_DIR ##coping template to user directory
BASTION_IMAGE_NAME=`echo ${BASTION_TEMPLATE} |  awk -F"/" '{print $NF}'`

# Convert resource GB into MB
bastion_mem=$(expr ${BASTION_MEM} \* 1024)
BASTION_PASSWORD="Gyp.s8m"

echo -e "\n\n======> Setting Up BASTION NODE:  # ${BASTION_HOSTNAME} :: ${BASTION_IP} :"
virt-customize -a "${USER_DIR}/${BASTION_IMAGE_NAME}" \
            --hostname ${BASTION_HOSTNAME}-bastion \
            --root-password password:${BASTION_PASSWORD} \
            --run-command "echo -e 'BOOTPROTO=none\nNAME=enp1s0\nDEVICE=enp1s0\nIPADDR=${BASTION_IP}\nPREFIX=20\nGATEWAY=$GATEWAY\nDNS1=$DNS\nDOMAIN=$BASE_DOM' > /etc/sysconfig/network-scripts/ifcfg-enp1s0 && systemctl restart NetworkManager && echo -e 'y/n' | ssh-keygen -f /root/.ssh/id_rsa -N ''" \
            --copy-in /root/.ssh/id_rsa.pub:/tmp  \
            --run-command "cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"

echo -n "======> Creating Bastion Node: "
virt-install  --name ${BASTION_HOSTNAME}-bastion \
              --memory memory=${bastion_mem}  \
              --vcpus vcpus=${BASTION_CPU} \
              --cpu mode=host-passthrough \
              --network bridge=${VIR_NET}  \
              --import --disk ${USER_DIR}/${BASTION_IMAGE_NAME} \
              --os-variant rhel8.6 \
              --wait 0 --graphics vnc,listen=0.0.0.0 > /dev/null 2>&1
echo -e "${GREEN} OK ${NC}"

echo -e "======> Waiting to Boot Up Bastion Node: "
TIMEOUT=300; INTERVAL=2;     START_TIME=$(date +%s)
while true; do
    if ping -c 1 "${BASTION_IP}" &> /dev/null; then
        echo -e "        Server ${BASTION_IP} ${GREEN}is up ${NC}"
        break
    else
        echo -e "        Waiting for server ${BASTION_IP} to be up..."
    fi
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
        echo -e "\n      ERROR: Time limit reached. Server ${BASTION_IP} is still down."
        exit 1
    fi 

    sleep "$INTERVAL" 
done


# Add Node entry in hosts file of bastion
CONNECT_BASTION="$SSH_EXEC root@${BASTION_IP}"

echo -n "======> Adding Nodes entry in ${BASTION_HOSTNAME}:/etc/hosts : "
$CONNECT_BASTION "echo '${BASTION_HOSTNAME} ${BASTION_IP} ${BASTION_HOSTNAME}-bastion' >> /etc/hosts"
$CONNECT_BASTION "echo '${BASTION_HOSTNAME}-bootstrap ${ips_array[0]}' >> /etc/hosts"

for ((i=1; i<=${N_MASTERS}; i++));do
     $CONNECT_BASTION "echo '${hostname_array[$i]} ${ips_array[$i]}' >> /etc/hosts"
done

for ((i=1; i<=${N_WORKERS}; i++));do
     $CONNECT_BASTION "echo '${hostname_array[$i]} ${ips_array[$i]}' >> /etc/hosts"
done
echo -e "${GREEN} Done ${NC}"


echo -n "======> Generating Bastion SSH Key:"
$SSH_EXEC root@${BASTION_IP} "echo -e 'y/n' | ssh-keygen -f /root/.ssh/id_rsa -N ''  >/dev/null"
echo -e "${GREEN} Done ${NC}"

