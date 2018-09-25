#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
########################################################################
#
# Description:
#       This script installs and runs Sysbench tests on a guest VM
#
#       Steps:
#       1. Installs dependencies
#       2. Compiles and installs sysbench
#       3. Runs sysbench
#       4. Collects results
#
#       No optional parameters needed
#
########################################################################
ROOT_DIR=$(pwd)
# For changing Sysbench and autoconf version only the following parameter has to be changed
SYSBENCH_VERSION=1.0.9
SYSBENCH_URL=https://github.com/akopytov/sysbench/archive/
AUTOCONF_VERSION=2.69
AUTOCONF_URL= http://ftp.gnu.org/gnu/autoconf/
#######################################################################
# Keeps track of the state of the test
#######################################################################
function Cpu_Test() {
    LogMsg "Creating cpu.log and starting test."
    sysbench cpu --num-threads=1 run >${ROOT_DIR}/cpu.log
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Unable to execute sysbench CPU. Aborting..."
        SetTestStateAborted
    fi

    PASS_VALUE_CPU=$(cat ${ROOT_DIR}/cpu.log | awk '/total time: / {print $3;}')
    if [ $? -ne 0 ]; then
        LogMsg "ERROR: Cannot find cpu.log."
        SetTestStateAborted
    fi

    RESULT_VALUE=$(echo ${PASS_VALUE_CPU} | head -c2)
    if [ $RESULT_VALUE -lt 15 ]; then
        CPU_PASS=0
        LogMsg "CPU Test passed. "
    fi
    LogMsg "$(cat ${ROOT_DIR}/cpu.log)"
    return "$CPU_PASS"
}
# Run Fileio test
function File_IO() {
    sysbench fileio --num-threads=1 --file-test-mode=$1 prepare >/dev/null 2>&1
    LogMsg "Preparing files to test $1..."
    sysbench fileio --num-threads=1 --file-test-mode=$1 run >${ROOT_DIR}/$1.log
    if [ $? -ne 0 ]; then
        LogErr" Unable to execute sysbench fileio mode $1. Aborting..."
        SetTestStateFailed
    else
        LogMsg "Running $1 tests..."
    fi

    PASS_VALUE_FILEIO=$(cat ${ROOT_DIR}/$1.log | awk '/sum/ {print $2;}' | cut -d. -f1)
    if [ $? -ne 0 ]; then
        LogErr " Cannot find $1.log."
        SetTestStateFailed
    fi

    if [ $PASS_VALUE_FILEIO -lt 12000 ]; then
        FILEIO_PASS=0
        LogMsg "Fileio Test -$1- passed with latency sum: $PASS_VALUE_FILEIO."
    else
        LogErr "Latency sum value is $PASS_VALUE_FILEIO. Test failed."
    fi

    sysbench fileio --num-threads=1 --file-test-mode=$1 cleanup
    LogMsg "Cleaning up $1 test files."

    LogMsg "$(cat ${ROOT_DIR}/$1.log)"
    cat ${ROOT_DIR}/$1.log >>${ROOT_DIR}/fileio.log
    rm ${ROOT_DIR}/$1.log
    return "$FILEIO_PASS"
}
# Install Sysbench
function Install_Sysbench() {
    pushd $ROOT_DIR
    LogMsg "Cloning sysbench"
    wget ${SYSBENCH_URL}/${Sysbench_Version}.zip
    if [ $? -gt 0 ]; then
        LogErr "Failed to download sysbench."
        SetTestStateFailed
        exit 0
    fi
    LogMsg "Unziping sysbench"
    unzip $Sysbench_Version.zip
    if [ $? -gt 0 ]; then
        LogErr "Failed to unzip sysbench."
        SetTestStateFailed
        exit 0
    fi
    GetDistro
    case $DISTRO in
    fedora*)
        pushd $ROOT_DIR
        wget ${AUTOCONF_URL}/autoconf-${AUTOCONF_VERSION}.tar.gz
        tar xvfvz autoconf-${AUTOCONF_VERSION}.tar.gz
        cd autoconf-${AUTOCONF_VERSION}
        ./configure
        make && make install
        yum install devtoolset-2-binutils automake libtool  -y
        ;;

    ubuntu* | debian*)
        apt-get install automake libtool pkg-config -y
        ;;

    suse*)
        zypper install -y vim
        ;;
    esac
    pushd "$ROOT_DIR/sysbench-$Sysbench_Version"
    bash ./autogen.sh
    bash ./configure --without-mysql
    LogMsg "Installing sysbench"
    make && make install
    if [ $? -ne 0 ]; then
        LogErr "Unable to install sysbench. Aborting..."
        SetTestStateAborted
        exit 0
    else
        LogMsg "Sysbench installed successfully."
    fi
}
#######################################################################
#
# Main script body
#
#######################################################################
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 0
}
#
# Source constants file and initialize most common variables
#
UtilsInit
#Install Sysbench
Install_Sysbench
#Run File IO testing
FILEIO_PASS=-1
CPU_PASS=-1
LogMsg "Testing CPU"
Cpu_Test
if [ $CPU_PASS -eq -1 ]; then
        LogMsg "ERROR: CPU Test failed "
        SetTestStateFailed
    fi
LogMsg "Testing fileio. Writing to fileio.log."
for test_item in ${TEST_FILE[*]}; do
    File_IO $test_item
    if [ $FILEIO_PASS -eq -1 ]; then
        LogMsg "ERROR: Test mode $test_item failed "
        SetTestStateFailed
    fi
done

if [ "$FILEIO_PASS" = "$CPU_PASS" ]; then
    LogMsg "All tests completed."
    SetTestStateCompleted
else
    LogMsg "Test Failed."
    SetTestStateFailed
fi
