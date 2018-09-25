########################################################################
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License
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

    Set-Location $RootDir
    # Define peak available memory in case of a problem. This value is the maximum value that a VM is able to
    # access in case of MTRR problem. If the guest cannot access more memory than this value the MTRR problem occurs.
    $peakFaultMem = [int]67700
    # Get VM available memory
    $guestReadableMem = RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 `
     -port $VMPort "free -m | grep Mem | xargs | cut -d ' ' -f 2"
    if ($? -ne "True") {
        LogErr "Unable to send command to VM."
        return "FAIL"
    }
    $memInfo = RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 `
    -port $VMPort "cat /proc/meminfo | grep MemTotal | xargs | cut -d ' ' -f 2"
    if ($? -ne "True") {
        LogErr "Unable to send command to VM."
        return "FAIL"
    }
    $memInfo = [math]::floor($memInfo / 1024)
    # Check if free binary and /proc/meminfo return the same value
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
