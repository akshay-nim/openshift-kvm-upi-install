#!/bin/bash
echo -e "\n================================================="; echo -e ">>>>>>  ${RED} CHECKING KVM HOST RESOURCES ${NC}";echo -e "=================================================\n"

print_header() {
    printf "%-40s %-40s\n" "RESOURCE" "DETAILS"
    printf "%-40s %-40s\n" "---------------------------" "-------------------"
}

print_row() {
    printf "%-40s %-40s\n" "$1" "$2"
}

# Collect CPU information
num_physical_cpus=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
running_vcpus=$(virsh list --all --name | xargs -I{} virsh vcpuinfo {} 2>/dev/null | grep -c "VCPU:")

# Collect memory information
total_mem=$(free -g | grep "Mem:" | awk '{print $2}')
free_mem=$(free -g | grep "Mem:" | awk '{print $7}')

# Collect disk space information
disk_usage=$(df -h / | awk 'NR==2 {print $3 " used, " $4 " available"}')

required_mem=`expr ${BOOT_MEM} + ${MAS_MEM} + ${WOR_MEM} + 12`

# Print the collected information in a table format
print_header
print_row "Number of physical CPUs" "$num_physical_cpus"
print_row "Number of running vCPUs" "$running_vcpus"
print_row "Total memory" "$total_mem GB"
print_row "Free memory" "$free_mem GB"
print_row "Memory Required for New cluster" "${required_mem} GB"
print_row "Disk usage (root)" "$disk_usage"

if [ `expr $free_mem - 10` -le $required_mem ];then
    echo -e "\n======> WARNING:  There is no enough Memory Available for New cluster"
    echo -e "======> Kindly check Above resource Details. \n"
    exit 1
else
    echo -e "\n======> INFO: Enough Memory Available to create cluster"
fi

echo;df -h