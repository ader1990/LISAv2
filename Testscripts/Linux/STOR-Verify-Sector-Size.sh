#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

# Description:
#    This script will verify logical sector size for 512 only and physical
#    sector size is 4096, mainly for 4k alignment feature.
#     step
#    1. Fdisk with {n,p,w}, fdisk -lu (by default display sections units )
#    2. Verify the first sector of the disk can divide 8
#    3. Verify the logical sector and physical size
#    Note: for logical size is 4096, already 4k align, no need to test.
#

# Source utils.sh
. utils.sh || {
    LogErr "unable to source utils.sh!"
    SetTestStateAborted
    exit 0
}

UtilsInit
# Need to add one disk before test
drive_name=/dev/sdc
#Check if parted is installed. If yes, create partition.
parted --help > /dev/null 2>&1
if [ $? -eq 0 ] ; then
    parted $drive_name mklabel msdos
    parted $drive_name mkpart primary 0% 100%
else
    SetTestStateAborted
    exit 0
fi

start_sector=`fdisk -lu $drive_name | tail -1 | awk '{print $2}'`
logical_sector_size=`fdisk -lu $drive_name | grep -i 'Sector size' | grep -oP '\d+' | head -1`
physical_sector_size=`fdisk -lu $drive_name | grep -i 'Sector size' | grep -oP '\d+' | tail -1`

if [ $(($start_sector%8)) -eq 0 ]; then
   LogMsg "Check the first sector size on $drive_name disk $start_sector can divide 8: Success"
else
  LogErr "First sector size on $drive_name disk Failed"
  SetTestStateAborted
  exit 0
fi

#
# check logical sector size is 512 and physical sector is 4096
# 4k alignment only needs to test in 512 sector
#
if [[ $logical_sector_size = 512 && $physical_sector_size = 4096 ]]; then

   LogMsg "Check logical and physical sector size on disk $drive_name : Success"
else

   LogErr "Check logical and physical sector size on disk  $drive_name : Failed "
   SetTestStateAborted
   exit 0
fi

SetTestStateCompleted
exit 0
