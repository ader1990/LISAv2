#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

# This script will do setup huge pages
# and OVS installation on client and server machines.

HOMEDIR=$(pwd)
export RTE_SDK="${HOMEDIR}/dpdk"
export RTE_TARGET="x86_64-native-linuxapp-gcc"
export OVS_DIR="${HOMEDIR}/ovs"
UTIL_FILE="./utils.sh"

# Source utils.sh
. utils.sh || {
	echo "ERROR: unable to source utils.sh!"
	echo "TestAborted" > state.txt
	exit 0
}

# Source constants file and initialize most common variables
UtilsInit

function setup_huge_pages () {
	LogMsg "Huge page setup is running"
	ssh "${1}" "mkdir -p /mnt/huge && mkdir -p /mnt/huge-1G"
	ssh "${1}" "mount -t hugetlbfs nodev /mnt/huge && mount -t hugetlbfs nodev /mnt/huge-1G -o 'pagesize=1G'"
	check_exit_status "Huge pages are mounted on ${1}"
	ssh "${1}" "echo 4096 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages"
	check_exit_status "4KB huge pages are configured on ${1}"
	ssh "${1}" "echo 8 > /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages"
	check_exit_status "1GB huge pages are configured on ${1}"
}

function install_ovs () {
	SetTestStateRunning
	LogMsg "Configuring ${1} ${DISTRO_NAME} ${DISTRO_VERSION} for OVS test..."
	packages=(gcc make git tar wget dos2unix psmisc make)
	case "${DISTRO_NAME}" in
		ubuntu|debian)
			ssh "${1}" "until dpkg --force-all --configure -a; sleep 10; do echo 'Trying again...'; done"
			if [[ "${DISTRO_VERSION}" != "18.04" ]];
			then
				echo "Distro unsupported ${DISTRO_VERSION}"
				SetTestStateAborted
				exit 1
			fi
			ssh "${1}" ". ${UTIL_FILE} && update_repos"
			packages+=(autoconf libtool)
			;;
		*)
			echo "Unknown distribution"
			SetTestStateAborted
			exit 1
	esac
	ssh "${1}" ". ${UTIL_FILE} && install_package ${packages[@]}"

	if [[ $ovsSrcLink =~ .tar ]];
	then
		ovsSrcTar="${ovsSrcLink##*/}"
		ovsVersion=$(echo "$ovsSrcTar" | grep -Po "(\d+\.)+\d+")
		LogMsg "Installing OVS from source file $ovsSrcTar"
		ssh "${1}" "wget $ovsSrcLink -P /tmp"
		ssh "${1}" "tar xf /tmp/$ovsSrcTar"
		check_exit_status "tar xf /tmp/$ovsSrcTar on ${1}"
		ovsSrcDir="${ovsSrcTar%%".tar"*}"
		LogMsg "ovs source on ${1} $ovsSrcDir"
		ssh "${1}" "mv ${ovsSrcDir} ${OVS_DIR}"
	elif [[ $ovsSrcLink =~ ".git" ]] || [[ $ovsSrcLink =~ "git:" ]];
	then
		ovsSrcDir="${ovsSrcLink##*/}"
		LogMsg "Installing OVS from source file $ovsSrcDir"
		ssh "${1}" git clone "$ovsSrcLink"
		check_exit_status "git clone $ovsSrcLink on ${1}"
		LogMsg "ovs source on ${1} $ovsSrcLink"
	else
		LogMsg "Provide proper link $ovsSrcLink"
	fi

	ssh "${1}" "cd ${OVS_DIR} && ./boot.sh"

	LogMsg "Starting OVS configure on ${1}"
	ssh "${1}" "cd ${OVS_DIR} && ./configure --with-dpdk=${RTE_SDK}/${RTE_TARGET} --prefix=/usr --localstatedir=/var --sysconfdir=/etc"

	LogMsg "Starting OVS build on ${1}"
	ssh "${1}" "cd ${OVS_DIR} && make -j16 && make install"
	check_exit_status "ovs build on ${1}"

	ssh "${1}" "/usr/share/openvswitch/scripts/ovs-ctl start"
	check_exit_status "ovs start on ${1}"

	ssh "${1}" "ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true"
	ssh "${1}" "ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-lcore-mask=0xFF"
	ssh "${1}" "ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask=0xFF"

	OVS_BRIDGE="br-dpdk"
	ssh "${1}" "ovs-vsctl add-br "${OVS_BRIDGE}" -- set bridge "${OVS_BRIDGE}" datapath_type=netdev"
	check_exit_status "ovs bridge ${OVS_BRIDGE} create on ${1}"

	ssh "${1}" "ovs-vsctl add-port "${OVS_BRIDGE}" p1 -- set Interface p1 type=dpdk options:dpdk-devargs=net_tap_vsc0,iface=eth1"

	LogMsg "*********INFO: Installed OVS version on ${1} is ${ovsVersion} ********"
}


# Script start from here

LogMsg "*********INFO: Script execution Started********"
echo "server-vm : eth0 : ${server}"
echo "client-vm : eth0 : ${client}"

LogMsg "*********INFO: Starting Huge page configuration*********"
LogMsg "INFO: Configuring huge pages on client ${client}..."
setup_huge_pages "${client}"

LogMsg "*********INFO: Starting setup & configuration of OVS*********"
LogMsg "INFO: Installing OVS on client ${client}..."
install_ovs "${client}"

if [[ ${client} == ${server} ]];
then
	LogMsg "Skip OVS setup on server"
	SetTestStateCompleted
else
	LogMsg "INFO: Configuring huge pages on server ${server}..."
	setup_huge_pages "${server}"
	LogMsg "INFO: Installing OVS on server ${server}..."
	install_ovs "${server}"
fi
LogMsg "*********INFO: OVS setup completed*********"
