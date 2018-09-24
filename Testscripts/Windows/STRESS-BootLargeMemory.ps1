########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

<#
.Synopsis
 Check if the VM is able to access all the memory assigned.

.Description
 Check if the VM is able to access more than 67700MB of RAM, in case a higher amount
 is assigned to it.
#>

param([String] $TestParams)

function Main {
    param (
        $VMname,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir,
        $TestParams
    )

    #######################################################################
    #
    #	Main body script
    #
    #######################################################################
    # Change directory
    Set-Location $RootDir
    #Define peak available memory in case of a problem. This value is the maximum value that a VM is able to
    #access in case of MTRR problem. If the guest cannot access more memory than this value the MTRR problem occurs.
    $peakFaultMem = [int]67700
    #Get VM available memory
    $guestReadableMem =  RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort "free -m | grep Mem | xargs | cut -d ' ' -f 2"
    if ($? -ne "True") {
        LogErr "Unable to send command to VM."
        return "FAIL"
    }
    $memInfo =  RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort "cat /proc/meminfo | grep MemTotal | xargs | cut -d ' ' -f 2"
    if ($? -ne "True") {
        LogErr "Unable to send command to VM."
        return "FAIL"
    }
    $memInfo = [math]::floor($memInfo / 1024)
    #Check if free binary and /proc/meminfo return the same value
    if ($guestReadableMem -ne $memInfo) {
        LogWarn "Warning: free and proc/meminfo return different values"
    }
    if ($guestReadableMem -gt $peakFaultMem) {
        LogMsg "VM is able to use all the assigned memory"
        return "PASS"
    }
    else {
        LogErr "VM cannot access all assigned memory."
        LogErr"Assigned: $startupMem MB| VM addressable: $guestReadableMem MB"
        return "FAIL"
    }
}
Main -VMname $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Host.ServerName `
    -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
    -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory `
    -TestParams $TestParams
