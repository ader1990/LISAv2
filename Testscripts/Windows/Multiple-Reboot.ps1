# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
# .Description
#     This is a PowerShell test case script that runs on the on
#     the ICA host rather than the VM.
#
#     This script will reboot a VM as many times as specified in the count parameter
#     and check that the VM reboots successfully.
#
############################################################################
param([String] $TestParams)

function Main {
    param (
        $VMName,
        $HvServer,
        $Ipv4,
        $RootDir,
        $TestParams
    )
    #####################################################################
    #
    # Main script body
    #
    #####################################################################
    #
    # Check input arguments
    #
    if ($VMName -eq $null) {
        LogErr "VM name is null"
        return "FAIL"
    }
    if ($HvServer -eq $null) {
        LogErr "hvServer is null"
        return "FAIL"
    }
    Set-Location $RootDir
    #
    # Check VM exists and running
    #
    $vm = Get-VM $VMName -ComputerName $HvServer
    if (-not $vm) {
        LogErr "Cannot find VM ${vmName} on server ${hvServer}"
        return "FAIL"
    }
    if ($($vm.State) -ne "Running") {
        LogErr "VM ${vmName} is not in the running state"
        return "FAIL"
    }

    LogMsg "Trying to reboot once using ctrl-alt-del from VM's keyboard."
    $VMKB = Get-WmiObject -namespace "root\virtualization\v2" -class "Msvm_Keyboard" -ComputerName $HvServer -Filter "SystemName='$($vm.Id)'"
    $VMKB.TypeCtrlAltDel()
    if ($? -eq "True") {
        LogMsg "VM received the ctrl-alt-del signal successfully."
    }
    else {
        LogErr "VM did not receive the ctrl-alt-del signal successfully."
        return "FAIL"
    }
    Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer
    }
    #
    # Set the $bootcount variable and reboot the machine $count times.
    #
    LogMsg "Setting the boot count to 0 for rebooting the VM"
    $bootcount = 0
    $testStartTime = [DateTime]::Now
    while ($count -gt 0) {
        While ( -not (Test-Port -Ipv4addr $Ipv4) ) {
            Start-Sleep 5
        }
        Restart-VM -VMName $VMName -ComputerName $HvServer -Force
        Start-Sleep 5
        Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer

        #
        # During reboot wait till the TCP port 22 to be available on the VM
        #
        Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer
        Start-Sleep -seconds 10
        $count -= 1
        $bootcount += 1
        LogMsg "Boot count:"$bootcount
    }
    #
    # If we got here, the VM was rebooted successfully $bootcount times
    #
    while ( -not (Test-Port -Ipv4addr $Ipv4) ) {
        Start-Sleep 5
        #
        #Check for Event Code 18602
        #
        if ((Get-VMEvent -VMName $vmName -HvServer $hvServer -StartTime $testStartTime `
        -EventCode 18602 -RetryCount 2 -RetryInterval 1)) {
        LogErr " VM $vmName triggered a critical event 18602 on the host" | `
        Out-File -Append $summaryLog
    return "FAIL "
}

    }
    LogMsg  "VM rebooted $bootcount times successfully"
}
Main -VMName $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Host.ServerName `
    -Ipv4 $AllVMData.PublicIP  -TestParams $TestParams -RootDir $WorkingDirectory
