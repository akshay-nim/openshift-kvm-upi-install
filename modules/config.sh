#!/bin/bash
HAPROXY_FILE="${USER_DIR}/haproxy.cfg"
INSTALL_CONFIG_FILE="${USER_DIR}/install-config.yaml"
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} CONFIGURING OPENSHIFT FILES ${NC} ";echo -e "=================================================\n"
echo -n "======> Generating Haproxy File for cluster:" 
ROOT_DIR=`pwd`
ENV_FILE="${ROOT_DIR}/modules/defaults.env"
source $ENV_FILE
export USER_DIR="${VMSTORE_DIR}/${OWNER_NAME}/${CLUSTER_NAME}"
export PUBLIC_IP_LIST="${PUBLIC_IP_LIST//,/ }" 
export BASTION_HOSTNAME=$(nslookup ${BASTION_IP} | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | cut -d. -f1)
# Generate Array for IP's 
IFS=' ' read -r -a ips_array <<< ${PUBLIC_IP_LIST}

# Generate Guest node names Array
hostname_array=()
hostname_array+=("${BASTION_HOSTNAME}-bootstrap")
for i in $(seq 1 ${N_MASTERS});do
hostname_array+=("${BASTION_HOSTNAME}-m-${i}"); done
for i in $(seq 1 ${N_WORKERS});do
hostname_array+=("${BASTION_HOSTNAME}-w-${i}"); done

# Generate haproxy.cfg
echo "
# Global settings
#---------------------------------------------------------------------
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    log                     global
    mode                    http
    option                  httplog
    option                  dontlognull
    option http-server-close
    option redispatch
    option forwardfor       except 127.0.0.0/8
    retries                 3
    maxconn                 20000
    timeout http-request    10000ms
    timeout http-keep-alive 10000ms
    timeout check           10000ms
    timeout connect         40000ms
    timeout client          300000ms
    timeout server          300000ms
    timeout queue           50000ms

# Enable HAProxy stats
listen stats
    bind :9000
    stats uri /stats
    stats refresh 10000ms

# Kube API Server
frontend k8s_api_frontend
    bind :6443
    default_backend k8s_api_backend
    mode tcp

backend k8s_api_backend
    mode tcp
    balance source" > ${HAPROXY_FILE}


echo "    server ${hostname_array[0]} ${ips_array[0]}:6443 check" >> ${HAPROXY_FILE}

for ((i=1; i<=${N_MASTERS}; i++));do
    echo "    server ${hostname_array[$i]} ${ips_array[$i]}:6443 check" >> ${HAPROXY_FILE}
done

echo "
# OCP Machine Config Server
frontend ocp_machine_config_server_frontend
    mode tcp
    bind :22623
    default_backend ocp_machine_config_server_backend

backend ocp_machine_config_server_backend
    mode tcp
    balance source" >> ${HAPROXY_FILE}

echo "    server ${hostname_array[0]} ${ips_array[0]}:22623 check" >> ${HAPROXY_FILE}

for ((i=1; i<=${N_MASTERS}; i++));do
    echo "    server ${hostname_array[$i]} ${ips_array[$i]}:22623 check" >> ${HAPROXY_FILE}
done

echo "
# OCP Ingress - layer 4 tcp mode for each. Ingress Controller will handle layer 7.
frontend ocp_http_ingress_frontend
    bind :80
    default_backend ocp_http_ingress_backend
    mode tcp

backend ocp_http_ingress_backend
    balance source
    mode tcp" >> ${HAPROXY_FILE}


worker_index_begin=`expr 1 + ${N_MASTERS}`
worker_index_end=`expr ${N_WORKERS} + ${N_MASTERS}`

for ((i=${worker_index_begin}; i<=${worker_index_end}; i++));do
    echo "    server ${hostname_array[$i]} ${ips_array[$i]}:80 check" >> ${HAPROXY_FILE}
done


echo "frontend ocp_https_ingress_frontend
    bind *:443
    default_backend ocp_https_ingress_backend
    mode tcp

backend ocp_https_ingress_backend
    mode tcp
    balance source" >> ${HAPROXY_FILE}

for ((i=${worker_index_begin}; i<=${worker_index_end}; i++));do
    echo "    server ${hostname_array[$i]} ${ips_array[$i]}:443 check" >> ${HAPROXY_FILE}
done
echo -e "${GREEN} OK ${NC}" 



# Generate Files required For OCP ignition
echo -n "======> Generating Insatll Config File: "
#tar -xvf ${USER_DIR}/openshift-install-linux.tar.gz -C ${USER_DIR}/ > /dev/null
#tar -xvf ${USER_DIR}/openshift-client-linux.tar.gz -C ${USER_DIR}/ > /dev/null

BASTION_SSH_KEY=`$SSH_EXEC root@${BASTION_IP} cat /root/.ssh/id_rsa.pub`
VAR_PULL_SECRET=`cat ${PULL_SECRET}`

echo -e "apiVersion: v1
baseDomain: ${BASE_DOM}
compute:
  - hyperthreading: Enabled
    name: worker
    replicas: 0 # Must be set to 0 for User Provisioned Installation as worker nodes will be manually deployed.
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${N_MASTERS}
metadata:
  name: ${CLUSTER_NAME} # Cluster name
networking:
  clusterNetwork:
    - cidr: 192.168.0.0/14
      hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
    - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '${VAR_PULL_SECRET}'
sshKey: \"${BASTION_SSH_KEY}\"
" > ${INSTALL_CONFIG_FILE}
echo -e "${GREEN} OK ${NC}" 


# Generate manifest/ignition files
echo -e "======> Generating ignition/manifest files on Bastion: "
$SSH_EXEC root@${BASTION_IP} "mkdir -p /root/ocp-install"
$SSH_EXEC root@${BASTION_IP} "rm -rf /var/www/html/*"
$SSH_EXEC root@${BASTION_IP} "mkdir -p /var/www/html/${CLUSTER_NAME}"
$SCP_EXEC ${USER_DIR}/openshift-install-linux.tar.gz ${USER_DIR}/openshift-client-linux.tar.gz root@${BASTION_IP}:/root > /dev/null
$SCP_EXEC ${USER_DIR}/rhcos-live-rootfs.x86_64.img ${USER_DIR}/rhcos-live.x86_64.iso  root@${BASTION_IP}:/var/www/html/${CLUSTER_NAME} > /dev/null
$SCP_EXEC ${USER_DIR}/install-config.yaml root@${BASTION_IP}:/root/ocp-install >/dev/null
$SCP_EXEC ${USER_DIR}/haproxy.cfg root@${BASTION_IP}:/etc/haproxy/ >/dev/null
$SSH_EXEC root@${BASTION_IP} "tar -xvf /root/openshift-install-linux.tar.gz -C /root > /dev/null"
$SSH_EXEC root@${BASTION_IP} "tar -xvf /root/openshift-client-linux.tar.gz -C /root > /dev/null"
$SSH_EXEC root@${BASTION_IP} "mv /root/oc /root/kubectl /usr/local/bin > /dev/null"
$SSH_EXEC root@${BASTION_IP} "~/openshift-install create manifests --dir ~/ocp-install > /dev/null"
$SSH_EXEC root@${BASTION_IP} "sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/ocp-install/manifests/cluster-scheduler-02-config.yml"
$SSH_EXEC root@${BASTION_IP} "~/openshift-install create ignition-configs --dir ~/ocp-install/"
$SSH_EXEC root@${BASTION_IP} "cp -R ~/ocp-install/* /var/www/html/${CLUSTER_NAME}"
$SSH_EXEC root@${BASTION_IP} "chcon -R -t httpd_sys_content_t /var/www/html/${CLUSTER_NAME}/"
$SSH_EXEC root@${BASTION_IP} "chown -R apache: /var/www/html/${CLUSTER_NAME}/"
$SSH_EXEC root@${BASTION_IP} "chmod 755 /var/www/html/${CLUSTER_NAME}/"
$SSH_EXEC root@${BASTION_IP} "systemctl stop firewalld && systemctl disable firewalld 1>/dev/null"
$SSH_EXEC root@${BASTION_IP} "setenforce 0"
$SSH_EXEC root@${BASTION_IP} "sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config"
$SSH_EXEC root@${BASTION_IP} "systemctl restart haproxy && systemctl enable haproxy"
$SSH_EXEC root@${BASTION_IP} "sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf"
$SSH_EXEC root@${BASTION_IP} "systemctl restart httpd && systemctl enable httpd"
$SSH_EXEC root@${BASTION_IP} "echo 'export KUBECONFIG=/root/ocp-install/auth/kubeconfig 2>/dev/null' >> /root/.bashrc"


