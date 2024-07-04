#!/bin/bash
# Validate mandatory parameter are non-zero
[ -z $OCP_MAJOR_RELEASE ] && { echo "ERROR: --release cannot be empty";exit 1;}
[ -z $OCP_MINOR_VERSION ] && { echo "ERROR: --version cannot be empty";exit 1;}
[ -z $CLUSTER_NAME ] && { echo "ERROR: -c|--cluster-name cannot be empty";exit 1;}
[ -z $VIR_NET ] && { echo "ERROR: -n|--libvirt-network cannot be empty";exit 1;}
[ -z $BASTION_IP ] && { echo "ERROR: -b|--bastion cannot be empty";exit 1;}
[ -z $PUBLIC_IP_LIST ] && { echo "ERROR: -i|--ips cannot be empty";exit 1;}
[ -z $OWNER_NAME ] && { echo "ERROR: -o|--owner cannot be empty";exit 1;}
[ -z $VMSTORE_DIR ] && { echo "ERROR: -s|--vmstore cannot be empty";exit 1;}
[ -z $BASTION_TEMPLATE ] && { echo "ERROR: Provide path for Bastion Template in default.env";exit 1;}
[ -z $USER_DIR ] && { echo "ERROR: USER_DIR should not be empty";exit 1;}