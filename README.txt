========================================================================================================
                                          PRE-REQUISITES
========================================================================================================

=====>    create Lab Request for IP and API Alias Entry

>>

we Need 9 IPs to create Openshift cluster 
KVM host: <server-name>
 
Out of them Need to add below aliases for one IP
cluster-name="<hostname of this IP>  (without FQDN)"
    For example:
<ip-address>  api-int.<cluster-name>.vxindia.veritas.com   api.<cluster-name>.vxindia.veritas.com   *.apps.<cluster-name>.vxindia.veritas.com



=====>  check virt-customize command present if not "yum install libguestfs-tools" or "yum install guestfs-tools"


=====>   Create OpenSwitch on KVM host

cat <<EOF > /root/openswitch.xml
<network>
  <name>OCP-OpenSwitch</name>
  <forward mode='bridge'/>
  <bridge name='<kvm host bridge name>'/>    
  <virtualport type='openvswitch'/>
  <portgroup name='novlan' default='yes'>
  </portgroup>
</network>
EOF

then Execute: 
virsh net-define /root/openswitch.xml
virsh net-start OCP-OpenSwitch
virsh net-autostart OCP-OpenSwitch


=====> 

RUN:  ./openshift_upi_kvm.sh -h 
