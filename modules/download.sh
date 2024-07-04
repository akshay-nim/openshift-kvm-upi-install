#!/bin/bash
echo -e "\n=================================================";echo -e ">>>>>>  ${RED} DOWNLOAD PACKAGES ${NC} ";echo -e "=================================================\n"

if [ "${OCP_MINOR_VERSION}" == "latest" ];then
      OCP_MINOR_VERSION=$(curl -s "${OCP_MIRROR_ROOT_LINK}/clients/ocp/stable-${OCP_MAJOR_RELEASE}/release.txt" | grep 'Name:' | awk '{ print $NF }') 
      OCP_CLIENT_URL="${OCP_MIRROR_ROOT_LINK}/clients/ocp/${OCP_MINOR_VERSION}"
else
      OCP_CLIENT_URL="${OCP_MIRROR_ROOT_LINK}/clients/ocp/${OCP_MINOR_VERSION}"
fi

rm -f ${USER_DIR}/rhcos-live-rootfs.x86_64.img
rm -f ${USER_DIR}/rhcos-live.x86_64.iso
rm -f ${USER_DIR}/openshift-install-linux.tar.gz
rm -f ${USER_DIR}/openshift-client-linux.tar.gz

OCP_DEPENDENCY_URL="${OCP_MIRROR_ROOT_LINK}/dependencies/rhcos/${OCP_MAJOR_RELEASE}/latest"

echo -n "======> Checking Openshift mirror registry Accessible:"
status_code=$(curl --write-out "%{http_code}" --silent --output /dev/null "${OCP_CLIENT_URL}/release.txt")
if [[ "$status_code" -ne 200 ]]; then echo "ERROR:  Registry is not Accessible or Openshift minor version is not Avaialble";exit 1; fi  
echo -e "${GREEN} OK ${NC}"

echo -n "======> Downloading ${OCP_MAJOR_RELEASE} rhcos-live-rootfs.x86_64.img :     "
#wget --progress=dot ${OCP_DEPENDENCY_URL}/rhcos-live-rootfs.x86_64.img -O ${USER_DIR}/rhcos-live-rootfs.x86_64.img  2>&1 \
#             | grep --line-buffered "%"  | sed -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
#echo -ne "\b\b\b\b"  
wget --progress=dot ${OCP_DEPENDENCY_URL}/rhcos-live-rootfs.x86_64.img -O ${USER_DIR}/rhcos-live-rootfs.x86_64.img >/dev/null 2>&1
echo -e "${GREEN} Done ${NC}"

echo -n "======> Downloading ${OCP_MAJOR_RELEASE} rhcos-live.x86_64.iso :     "
#wget --progress=dot "${OCP_DEPENDENCY_URL}/rhcos-live.x86_64.iso" -O "${USER_DIR}/rhcos-live.x86_64.iso" >/dev/null 2>&1 \
#                   | grep --line-buffered "%" | sed -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
wget --progress=dot "${OCP_DEPENDENCY_URL}/rhcos-live.x86_64.iso" -O "${USER_DIR}/rhcos-live.x86_64.iso" >/dev/null 2>&1
#echo -ne "\b\b\b\b"
echo -e "${GREEN} Done ${NC}"
 
echo -n "======> Downloading ${OCP_MINOR_VERSION} openshift-install-linux.tar.gz :     "
#wget --progress=dot "${OCP_CLIENT_URL}/openshift-install-linux.tar.gz" -O "${USER_DIR}/openshift-install-linux.tar.gz" 2>&1 \
#             |    grep --line-buffered "%" | sed -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
#echo -ne "\b\b\b\b"
wget --progress=dot "${OCP_CLIENT_URL}/openshift-install-linux.tar.gz" -O "${USER_DIR}/openshift-install-linux.tar.gz" >/dev/null 2>&1
echo -e "${GREEN} Done ${NC}"

echo -n "======> Downloading ${OCP_MINOR_VERSION} openshift-client-linux.tar.gz :     "
#wget --progress=dot "${OCP_CLIENT_URL}/openshift-client-linux.tar.gz" -O "${USER_DIR}/openshift-client-linux.tar.gz" 2>&1  \
#|    grep --line-buffered "%" | sed -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
#echo -ne "\b\b\b\b"
wget --progress=dot "${OCP_CLIENT_URL}/openshift-client-linux.tar.gz" -O "${USER_DIR}/openshift-client-linux.tar.gz" >/dev/null 2>&1
echo -e "${GREEN} Done ${NC}"