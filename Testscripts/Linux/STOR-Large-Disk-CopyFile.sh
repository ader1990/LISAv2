#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
# STOR_Large_Disk_CopyFile.sh
# Description:
#    This script verifies multiple file copy operations on a disk
#
#     The test performs the following steps:
#    1. Creates partition
#    2. Creates filesystem
#    3. Performs copy operations by copy local file and through wget download
#    4. Unmounts partition
#    5. Deletes partition
#
########################################################################
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 0
}
#
# Source constants file and initialize most common variables
#
UtilsInit
# test dd 5G files, dd one 5G file locally, then copy to /mnt which is mounted to disk
function Test_Local_CopyFile() {
    LogMsg "Start to dd file"
    #dd 5G files
    dd if=/dev/zero of=/root/data bs=2048 count=2500000
    file_size=`ls -l /root/data | awk '{ print $5}' | tr -d '\r'`
    LogMsg "Successful dd file as /root/data"
    LogMsg "Start to copy file to /mnt"
    cp /root/data /mnt
    rm -f /root/data
    file_size1=`ls -l /mnt/data | awk '{ print $5}' | tr -d '\r'`
    LogMsg "file_size after dd=$file_size"
    LogMsg "file_size after copyed= $file_size1"
    if [[ $file_size1 = $file_size ]]; then
        LogMsg "Successful copy file"
        LogMsg "Listing directory: ls /mnt/"
        ls /mnt/
        rm -rf /mnt/*
        LogMsg "Disk test completed for file copy on ${drive_name}1 with filesystem ${fs}."
    else
        LogErr "Copying 5G file for ${drive_name}1 with filesystem ${fs} failed"
        SetTestStateFailed
        exit 0
    fi
}

# test wget file, wget one 5G file to /mnt which is mounted to disk
function Test_Wget_File() {
    file_basename=`basename $wget_path`
    wget -O /mnt/$file_basename $wget_path
    file_size=`curl -sI $wget_path | grep Content-Length | awk '{print $2}' | tr -d '\r'`
    file_size1=`ls -l /mnt/$file_basename | awk '{ print $5}' | tr -d '\r'`
    LogMsg "file_size before wget=$file_size"
    LogMsg "file_size after wget=$file_size1"
    if [[ $file_size = $file_size1 ]]; then
        LogMsg "Drive wget to ${drive_name}1 with filesystem ${fs} successfully"
    else
        LogErr "Drive wget to ${drive_name}1 with filesystem ${fs} failed"
        SetTestStateFailed
        exit 0
    fi
    rm -rf /mnt/*
}

# Format the disk and create a file system, mount and create file on it.
function Test_FileSystem_Copy() {
    drive=$1
    fs=$2
    parted -s -- $drive mklabel gpt
    parted -s -- $drive mkpart primary 64s -64s
    if [ "$?" = "0" ]; then
        sleep 5
        wipefs -a "${drive_name}1"
        mkfs.$fs  ${drive_name}1
        if [ "$?" = "0" ]; then
            LogMsg "mkfs.${fs}   ${drive_name}1 successful..."
            mount ${drive_name}1 /mnt
            if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."
                # step 1: test for local copy file
                LogMsg "Start to test local copy file"
                Test_Local_CopyFile
                # step 2: wget 5GB file to disk
                LogMsg "Start to test wget file"
                Test_Wget_File
                # umount /mnt files
                umount /mnt
                if [ "$?" = "0" ]; then
                      LogMsg "Drive unmounted successfully..."
                fi
            else
               LogErr "Error in mounting drive..."
               SetTestStateFailed
            fi
        else
            LogErr "Error in creating file system ${fs}.."
            SetTestStateFailed
        fi
    else
        LogErr "Error in executing parted  ${drive_name}1 for ${fs}"
        SetTestStateFailed
    fi
}

# Check for call trace log
chmod +x check_traces.sh
./check_traces.sh &

# Count the number of SCSI= and IDE= entries in constants
disk_count=1
for entry in $(cat ./constants.sh)
do
    # Convert to lower case
    low_str="$(tr '[A-Z]' '[a-z' <<<"$entry")"

    # if it starts with ide or scsi, then we increase the count
    if [[ $low_str == ide* ]];
    then
        disk_count=$((disk_count+1))
    fi

    if [[ $low_str == scsi* ]];
    then
        disk_count=$((disk_count+1))
    fi
done

LogMsg "Tests will be performed on $disk_count disks"

# Compute the number of sd* drives on the system
for drive_name in /dev/sd*[^0-9];
do
    # Skip /dev/sda
    if [ ${drive_name} = "/dev/sda" ]; then
        continue
    fi
    if [ ${drive_name} = "/dev/sdb" ]; then
        continue
    fi

    for fs in "${fileSystems[@]}"; do
        LogMsg "Start testing filesystem: $fs"
        start_tst=$(date +%s.%N)
        command -v mkfs.$fs
        if [ $? -ne 0 ]; then
            LogMsg "File-system tools for $fs not present. Skipping filesystem $fs."
        else
            Test_FileSystem_Copy $drive_name $fs
            end_tst=$(date +%s.%N)
            diff_tst=$(echo "$end_tst - $start_tst" | bc)
            LogMsg "End testing filesystem: $fs; Test duration: $diff_tst seconds."
        fi
    done
done

SetTestStateCompleted
exit 0