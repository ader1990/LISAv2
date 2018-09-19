# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
 <#
.Synopsis
 Trigger an NMI on a target VM
#>
param([String] $TestParams)

$ErrorActionPreference = "Stop"

$testStates = @{
    "StopState" = $false;
    "SavedState" = $false;
    "PausedState" = $false;
}


function Execute-StopStateTest {
    param(
        $VMName,
        $Ipv4,
        $HvServer="localhost"
    )

    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
    while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
        LogMsg "Waiting for VM to enter Off state"
        Start-Sleep -Seconds 5
    }
    try {
        Debug-VM -Name $VMName -InjectNonMaskableInterrupt `
            -ComputerName $HvServer -Confirm:$False -Force `
            -ErrorAction "Stop"
        LogErr "NMI could be sent when the VM is in stopped state."
    } catch {
        LogMsg "NMI could not be sent when the VM is in stopped state."
        $testStates["StopState"] = $true
    }
}


function Execute-SavedStateTest {
    param(
        $VMName,
        $Ipv4,
        $HvServer="localhost"
    )

    Start-VM -ComputerName $hvServer -Name $vmName
    while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Running") {
        LogMsg "Waiting for VM to enter Running state"
        Start-Sleep -Seconds 5
    }

    do {
        Start-Sleep -Seconds 5
        LogMsg "Waiting for VM to enter Heartbeat OK state"
    } until ((Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer | `
                  Where-Object  { $_.name -eq "Heartbeat" }
              ).PrimaryStatusDescription -eq "OK")

    Save-VM -ComputerName $hvServer -Name $vmName -Confirm:$false
    while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Saved") {
        LogMsg "Waiting for VM to enter Saved state"
        Start-Sleep -Seconds 5
    }
    try {
        Debug-VM -Name $VMName -InjectNonMaskableInterrupt `
            -ComputerName $HvServer -Confirm:$False -Force `
            -ErrorAction "Stop"
        LogErr "NMI could be sent when the VM is in saved state."
    } catch {
        LogMsg "NMI could not be sent when the VM is in saved state."
        $testStates["SavedState"] = $true
    }
}


function Execute-PausedStateTest {
    param(
        $VMName,
        $Ipv4,
        $HvServer="localhost"
    )
    Start-VM -ComputerName $hvServer -Name $vmName
    while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Running") {
        LogMsg "Waiting for VM to enter Running state"
        Start-Sleep -Seconds 5
    }

    do {
        LogMsg "Waiting for VM to enter Heartbeat OK state"
        Start-Sleep -Seconds 5
    } until ((Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer | `
                  Where-Object  { $_.name -eq "Heartbeat" }
              ).PrimaryStatusDescription -eq "OK")

    Suspend-VM -ComputerName $hvServer -Name $vmName -Confirm:$false
    while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Paused") {
        LogMsg "Waiting for VM to enter Paused state"
        Start-Sleep -Seconds 5
    }
    try {
        Debug-VM -Name $VMName -InjectNonMaskableInterrupt `
            -ComputerName $HvServer -Confirm:$False -Force `
            -ErrorAction "Stop"
        LogErr "NMI could be sent when the VM is in suspended state."
    } catch {
        LogMsg "NMI could not be sent when the VM is in suspended state."
        $testStates["SavedState"] = $true
    }
}


function Trigger-FailedNmiInterrupt {
    param(
        $VMName,
        $Ipv4,
        $HvServer="localhost"
    )

    $buildNumber = Get-HostBuildNumber $hvServer
    if (!$buildNumber) {
        return "FAIL"
    }
    if ($BuildNumber -lt 9600) {
        return "ABORTED"
    }

    foreach ($testState in $testStates.clone().Keys) {
        try {
            & "Execute-${testState}Test" -VMName $VMName `
                                         -HvServer $HvServer `
                                         -Ipv4 $Ipv4
        } catch {
            LogErr "$testState has failed to execute."
        }
    }

    $failedStates = $testStates | Where-Object { !$_ }
    if ($failedStates) {
        return "FAIL"
    }

    return "PASS"
}

Trigger-FailedNmiInterrupt -VMName $AllVMData.RoleName `
     -HvServer $xmlConfig.config.Hyperv.Host.ServerName `
     -Ipv4 $AllVMData.PublicIP

