#!/bin/bash

# Replace comma with space in PUBLIC_IP_LIST if present
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
source $ENV_FILE
export PUBLIC_IP_LIST="${PUBLIC_IP_LIST//,/ }" 
ROOT_DIR=`pwd`
echo -e "\n================================================="; echo -e ">>>>>>  ${RED} WRITING ENVIRONMENT ${NC}";echo -e "=================================================\n"

 echo  "
#   OCP_MAJOR_RELEASE                   : "${OCP_MAJOR_RELEASE}"
#   OCP_MINOR_VERSION                   : "${OCP_MINOR_VERSION}"
#   N_MASTERS                           : "3"
#   N_WORKERS                           : "3"
#   MAS_CPU                             : "6"
#   MAS_MEM                             : "12" GB
#   MAS_BOOTDISK                        : "${MAS_BOOTDISK}" GB
#   WOR_CPU                             : "8"
#   WOR_MEM                             : "16" GB
#   WOR_BOOTDISK                        : "${WOR_BOOTDISK}" GB
#   CLUSTER_NAME                        : "${CLUSTER_NAME}"
#   BASE_DOM:                           : "vxindia.veritas.com"
#   VIR_NET                             : "${VIR_NET}"
#   OWNER_NAME                          : "${OWNER_NAME}"
#   VMSTORE_DIR                         : "${VMSTORE_DIR}"
#   PULL_SECRET                         : "${PULL_SECRET}"
#   BASTION_IP                          : "${BASTION_IP}"
#   PUBLIC_IP_LIST                      : "${PUBLIC_IP_LIST}"
#   OCP_MIRROR_ROOT_LINK                : "https://mirror.openshift.com/pub/openshift-v4"

"

if [ "X${AUTO_APPROVE}" != "XYES" ]; then
        echo -e "\n ${YELLOW}   OPENSHIFT VERSION TO INSTALL ${NC}= ${OCP_MAJOR_RELEASE} : ${OCP_MINOR_VERSION}  \n\n"
        echo -n "Press [Enter] to continue, [Ctrl]+C to abort: "; echo; read userinput;
fi

[ "${FORCE}" == "YES" ] && ${ROOT_DIR}/modules/destroy.sh

export BASTION_HOSTNAME=$(nslookup ${BASTION_IP} | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | cut -d. -f1)
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} DEPENDENCIES & SANITY CHECKS ${NC}";echo -e "=================================================\n"

releasevar=$(echo "$OCP_MAJOR_RELEASE")
versionvar=$(echo "$OCP_MINOR_VERSION")

echo -n "======> Checking we have ssh public Key Available: "
filename="id_rsa.pub";  path="$HOME/.ssh"
if [ ! -f "$path/$filename" ];then
    ssh-keygen -t rsa -f "$path/$filename"
fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking if we have all the dependencies: "
for x in virsh virt-install virt-customize systemctl wget
do
    builtin type -P $x &> /dev/null || { "executable $x not found";exit 1; }
done
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking Relese Format:"
if [[ ! $releasevar =~ ^[0-9]\.[0-9][0-9]$ ]]; then echo "Error: Invalid release format"; exit 1;fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking if API Alias is DNS Registered:"
canonical=$(nslookup api.${CLUSTER_NAME}.${BASE_DOM} | grep "canonical name =" | awk '{print $5}' |  sed 's/\.$//' | cut -d. -f1)
if [ -z "$canonical" ];then
    echo -e "\n\n\tERROR:  API Alias : api.${CLUSTER_NAME}.${BASE_DOM} is Not DNS Registered"
    echo -e "\n\tINFO NOTE : We need to add DNS Entry with provide Cluster Name as: api.${CLUSTER_NAME}.${BASE_DOM} \n"
    echo -e "\tINFO:  RUN: ./openshift_upi_kvm.sh -h \n"
    exit 1
else
    if [ ${BASTION_HOSTNAME} != "${canonical}" ];then
        echo -e "\n\n\tERROR:  API Alias : \"api.${CLUSTER_NAME}.${BASE_DOM}\" has Different DNS Hostname than provided Bastion IP: ${BASTION_IP}"
        echo -e "\n\tINFO : api.${CLUSTER_NAME}.${BASE_DOM} should match with BASTION IP :  RUN:   nslookup ${BASTION_IP} \n"
        exit 1
    fi
fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking Relese Format:"
if [[ ! $releasevar =~ ^[0-9]\.[0-9][0-9]$ ]]; then echo "Error: Invalid release format"; exit 1;fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking If vmstore directory present on cluster:"
if [ ! -d "${VMSTORE_DIR}" ]; then
    echo -e "\n\n\tERROR: Directory ${VMSTORE_DIR} does not exist on KVM Host"
    exit 1
fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking User \"${OWNER_NAME}\" Directory with Cluster Name \"${CLUSTER_NAME}\":"
if [ -d "${USER_DIR}" ]; then
    #if [ "$(find ${USER_DIR} -mindepth 1 | grep -v install | head -n 1)" ];then
    if ls "$DIRECTORY"/*.qcow2 1> /dev/null 2>&1; then
        echo -e "\n\n\tERROR: Directory \"${USER_DIR}\" Already Present on KVM Host which is not empty. Create New cluster Name"
	find "$DIRECTORY" -type f -name "*.qcow2"
        echo -e "\tIf you want to create anyway with this Cluster Name. \n"
        echo -e "\tFOR JENKINS RUN: ${GREEN} Use FORCE_DESTROY=yes ${NC}"
        echo -e "\tFOR CLI: RUN: ./openshift_upi_kvm.sh destroy\n\n"
        exit 1
    fi
fi
mkdir -p ${USER_DIR}
echo -e "${GREEN} Done ${NC}"


echo -n "======> Checking Specified $versionvar align with release version $releasevar:"
if [ $versionvar != 'latest' ];then
    if ! echo "$versionvar" | grep -q "$releasevar"; then
        echo -e "\n\n\tERROR: version specified ${versionvar} doesn't align with release version ${releasevar} \n"
        exit 1
    fi
fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking Node count and IP count matches:"
TOTAL_NODES=`expr ${N_MASTERS} + ${N_WORKERS} + 1`
ARRAY=' ' read -r -a LIST <<< "$PUBLIC_IP_LIST"
array_length=${#LIST[@]}
if [ $TOTAL_NODES -ne ${array_length} ];then
    echo -e "\n\n\tERROR: Node Count: ${TOTAL_NODES}, but Public IP Count: ${array_length}"
    exit 1
fi
echo -e "${GREEN} OK ${NC}"


echo "======> Checking if Provided IP's are DNS Registered:"
for ip in ${BASTION_IP} $PUBLIC_IP_LIST;do
   echo -n "        Validating $ip:"
   nslookup $ip | grep -q "name =" || {
        echo "        ERROR: IP: $ip is Not DNS Registered"
        exit 1
   }
   echo -e "${GREEN} OK ${NC}"
done


echo -n "======> Checking if any Duplicates IP in IP List:"
duplicates=$(echo "$PUBLIC_IP_LIST" | awk -F ' ' '{
    for (i = 1; i <= NF; i++) {
        if (++seen[$i] == 2) {
            print $i
            exit
        }
    }
}')

if [ -n "$duplicates" ]; then
    echo -e "\n\n\tERROR: Duplicate found in PUBLIC_IP_LIST: $duplicates"
    exit 1
fi
echo -e "${GREEN} OK ${NC}"


echo "======> Checking if Provided IP's are Free to Use:"
for ip in ${BASTION_IP} $PUBLIC_IP_LIST;do
   echo -n "        Validating $ip:"
   if ping -c 1 -W 1 "$ip" &>/dev/null;then
    
        echo "        ERROR: Looks like IP: $ip is Used by another server"
        exit 1
    fi
   echo -e "${GREEN} FREE ${NC}"
done


echo -n "======> Checking If we have any existing leftover VMs with ${BASTION_HOSTNAME}: "
existing=$(virsh list --all --name | grep -qi "${BASTION_HOSTNAME}")
if [ $? -eq 0 ];then 
    echo -e "\n\n\tERROR: Found Existing VM with Bastion Host name: ${BASTION_HOSTNAME}\n"
    virsh list --all --name | grep ${BASTION_HOSTNAME} | xargs; echo
    exit 1
fi
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking if libvirtd is running: "
systemctl -q is-active libvirtd || {
        echo -n "libvirtd is Not running on Host. Restating..."
        systemctl restart libvirtd
        systemctl -q is-active libvirtd || {
            echo -e "\n\n\tERROR: still libvirtd is not active"
            exit 1
        }
    }
echo -e "${GREEN} OK ${NC}"


echo -n "======> Checking if libvirt bridge Network is present: "
nmcli connection show | grep -qw "$VIR_NET" || {
    echo -e "\n\n\tERROR: Provided Libvirt Network: $VIR_NET is not Present on Host"
    exit 1
}
echo -e "${GREEN} OK ${NC}"
