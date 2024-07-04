#!/bin/bash 
########################################################################################
# PURPOSE   : Configure Openshift UPI cluster on KVM (Public IP)
# CONTACT   : nimbalkara42@gmail.com
# CREATED   : 03/06/2024
########################################################################################

start_time=$(date +%s)
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
sed -i "s/FORCE=*.*/FORCE=\"NO\"/" $ENV_FILE

show_help() {
    local script_name
    script_name=$(basename "$0")
    
    cat << ENDHELP

############################################################################################################################################################

    Pre-requisites :
    Raise Lab Request as below before we begin with OCP UPI (Pubic IP) :

   >>>>>>>>>>>>
    
    Need 9 IP's for Openshift cluster.   <<<<<   (for 4 worker node cluster) 
    Also add below aliases for one IP amongst them (This is Bastion IP for our cluster): 

    For example:
    <ip-address>  api-int.<add-new-cluster-name>.vxindia.veritas.com   api.<add-new-cluster-name>.vxindia.veritas.com   *.apps.<add-new-cluster-name>.vxindia.veritas.com

#############################################################################################################################################################



INFO USAGE: $script_name "<create>|<destroy>" "options"

=============================================================================================================================================================
Mandatory Options: 

/openshift_upi_cluster.sh create --release 4.15 --version <4.15.1 | latest> -c <cluster-name> --ips "10.210.1.2,10.210.1.3"  -n OpenSwitch -o <owner-name>

>>>>>    OR

- Update values in ./modules/default.env and then run >
./openshift_upi_cluster.sh create 

=============================================================================================================================================================
    --release:             [mandatory] Openshift major version  
    --version:             [mandatory] Openshift minor version. Valid values: [ <latest> or <specific-version>]
    -c|--cluster-name:     [mandatory] Openshift cluster Name
    -n|--libvirt-network:  [mandatory] Virtual switch Network
    -b|--bastion:          [mandatory] Bastion Node IP
    -i|--ips:              [mandatory] Public IP List  : comma separated or space separated exclude bastion IP
    -o|--owner:            [mandatory] Owner Name
    -s|--vmstore:          [mandatory] Directoty on KVM host where vm disks should present 
    -m|--masters N:        [optional]  Number of Master Nodes     ==> DEFAULT: ${N_MASTERS}
    -w|--workers N:        [optional]  Number of Worker Nodes     ==> DEFAULT: ${N_WORKERS}
    --master-cpu N:        [optional]  Number of CPU for master   ==> DEFAULT: ${MAS_CPU}
    --master-mem(GB):      [optional]  RAM size in GB             ==> DEFAULT: ${MAS_MEM}
    --master-bootdisk:     [optional]  Boot Disk Size in GB       ==> DEFAULT: ${MAS_BOOTDISK} 
    --worker-cpu N:        [optional]  Number of CPU for worker   ==> DEFAULT: ${WOR_CPU}
    --worker-mem(GB):      [optional]  RAM size in GB             ==> DEFAULT: ${WOR_MEM}
    --worker-bootdisk(GB)  [optional]  Boot Disk Size in GB       ==> DEFAULT: ${WOR_BOOTDISK}
    -d|--cluster-domain:   [optional]  Domain Name                ==> DEFAULT: ${BASE_DOM}
    -g|--gateway           [optional]  Network Gateway            
    -t|--dns               [optional]  DNS server IP              
    -p|--pull-secret:      [optional] 
    --force                [optional]  Force Destroy Existing cluster
    --auto-approve         [optional]  Auto approve script Execution
    -h|--help

ENDHELP
}

key=$1
case "$key" in
  create)
    shift
    
    while [[ $# -gt 0 ]];do 
      case $1 in   
        --release)
          export OCP_MAJOR_RELEASE="$2"
          sed -i "s/OCP_MAJOR_RELEASE=*.*/OCP_MAJOR_RELEASE=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --version)
          export OCP_MINOR_VERSION="$2"
          sed -i "s/OCP_MINOR_VERSION=*.*/OCP_MINOR_VERSION=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -m|--masters)
          export N_MASTERS="$2"
          sed -i "s/N_MASTERS=*.*/N_MASTERS=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -w|--workers)
          export N_WORKERS="$2"
          sed -i "s/N_WORKERS=*.*/N_WORKERS=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --master-cpu)
          export MAS_CPU="$2"
          sed -i "s/MAS_CPU=*.*/MAS_CPU=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --master-mem)
          export MAS_MEM="$2"
          sed -i "s/MAS_MEM=*.*/MAS_MEM=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --master-bootdisk)
          export MAS_BOOTDISK="$2"
          sed -i "s/MAS_BOOTDISK=*.*/MAS_BOOTDISK=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --worker-cpu)
          export WOR_CPU="$2"
          sed -i "s/WOR_CPU=*.*/WOR_CPU=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --worker-mem)
          export WOR_MEM="$2"
          sed -i "s/WOR_MEM=*.*/WOR_MEM=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --worker-bootdisk)
          export WOR_BOOTDISK="$2"
          sed -i "s/WOR_BOOTDISK=*.*/WOR_BOOTDISK=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -c|--cluster-name)
          export CLUSTER_NAME="$2"
          sed -i "s/CLUSTER_NAME=*.*/CLUSTER_NAME=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -d|--cluster-domain)
          export BASE_DOM="$2"
          sed -i "s/BASE_DOM=*.*/BASE_DOM=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -n|--libvirt-network)
          export VIR_NET="$2"
          sed -i "s/VIR_NET=*.*/VIR_NET=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -o|--owner)
          export OWNER_NAME="$2"
          sed -i "s/OWNER_NAME=*.*/OWNER_NAME=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -b|--bastion)
          export BASTION_IP="$2"
          sed -i "s/BASTION_IP=*.*/BASTION_IP=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -i|--ips)
          export PUBLIC_IP_LIST="$2"
          sed -i "s/PUBLIC_IP_LIST=*.*/PUBLIC_IP_LIST=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -s|--vmstore)
          export VMSTORE_DIR="$2"
          DIR=$(echo $VMSTORE_DIR |  sed 's/\//\\\//g')
          sed -i "s/VMSTORE_DIR=*.*/VMSTORE_DIR=\"${DIR}\"/" $ENV_FILE
          shift;shift
          ;;
        -p|--pull-secret)
          export PULL_SECRET="$2"
          sed -i "s/PULL_SECRET=*.*/PULL_SECRET=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -g|--gateway)
          export GATEWAY="$2"
          sed -i "s/GATEWAY=*.*/GATEWAY=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        -t|--dns)
          export DNS="${2}"
          sed -i "s/DNS=*.*/DNS=\"${2}\"/" $ENV_FILE
          shift;shift
          ;;
        --auto-approve)
          export AUTO_APPROVE="YES"
          shift;
          ;;
        --force)
          export FORCE="YES"
          sed -i "s/FORCE=*.*/FORCE=\"YES\"/" $ENV_FILE
          shift;
          ;;
        -h|--help)
          show_help
          exit 1
          shift;shift
        ;;
        *)
          echo
	  exit 1
        ;;
      esac
    done

    source $ENV_FILE
    export USER_DIR="${VMSTORE_DIR}/${OWNER_NAME}/${CLUSTER_NAME}"
    ${ROOT_DIR}/modules/check_parameter.sh
    ${ROOT_DIR}/modules/check_kvm_resources.sh; [ $? -ne 0 ] && { exit 1; }
    ${ROOT_DIR}/modules/validation.sh; [ $? -ne 0 ] && { exit 1; }
    ${ROOT_DIR}/modules/download.sh; [ $? -ne 0 ] && { exit 1; }
    ${ROOT_DIR}/modules/create_bastion.sh; [ $? -ne 0 ] && { exit 1; }
    ${ROOT_DIR}/modules/config.sh; [ $? -ne 0 ] && { exit 1; }
    ${ROOT_DIR}/modules/create_rhcos_nodes.sh; [ $? -ne 0 ] && { exit 1; }
    ${ROOT_DIR}/modules/bootstrap.sh; [ $? -ne 0 ] && { exit 1; }
      ;;
  destroy)
      source $ENV_FILE
      ${ROOT_DIR}/modules/check_parameter.sh
      ${ROOT_DIR}/modules/destroy.sh; [ $? -ne 0 ] && { exit 1; }
      ;;
  --info)
        version_info "$@"
      ;;
  *)
        source $ENV_FILE
        show_help
        exit 1
esac


end_time=$(date +%s)
duration=$((end_time - start_time))
duration_formatted=$(date -u -d@"$duration" +%H:%M:%S)
echo -e "\n\n==========================================================="
echo -e "\n    ${GREEN}SCRIPT EXECUTION TIME ${NC}: $duration_formatted\n"
echo -e "==========================================================="
