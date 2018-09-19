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

function Wait-VMState {
    param(
        $VMName,
        $VMState,
        $HvServer,
        $RetryCount=30,
        $RetryInterval=5
    )

    $offStateRetryCount = 0
    while ($offStateRetryCount -lt $RetryCount -and `
              (Get-VM -ComputerName $hvServer -Name $vmName).State -ne $VMState) {
        LogMsg "Waiting for VM ${VMName} to enter ${VMState} state"
        Start-Sleep -Seconds $RetryInterval
        $offStateRetryCount++
    }
    if ($offStateRetryCount -eq $RetryCount) {
        throw "VM ${VMName} failed to enter ${VMState} state"
    }
}

function Wait-VMHeartbeatOK {
    param(
        $VMName,
        $HvServer,
        $RetryCount=30,
        $RetryInterval=5
    )

    $offStateRetryCount = 0
    do {
        $offStateRetryCount++
        Start-Sleep -Seconds $RetryInterval
        LogMsg "Waiting for VM ${VMName} to enter Heartbeat OK state"
    } until ($offStateRetryCount -ge $RetryCount -or `
                 (Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer | `
                  Where-Object  { $_.name -eq "Heartbeat" }
              ).PrimaryStatusDescription -eq "OK")
    if ($offStateRetryCount -eq $RetryCount) {
        throw "VM ${VMName} failed to enter Heartbeat OK state"
    }
}

function Execute-StopStateTest {
    param(
        $VMName,
        $HvServer
    )

    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Off"
    try {
        Debug-VM -Name $VMName -InjectNonMaskableInterrupt `
            -ComputerName $HvServer -Confirm:$False -Force `
            -ErrorAction "Stop"
        LogErr "NMI could be sent when the VM ${VMName} is in stopped state."
    } catch {
        LogMsg "NMI could not be sent when the VM ${VMName} is in stopped state."
        $testStates["StopState"] = $true
    }
}

function Execute-SavedStateTest {
    param(
        $VMName,
        $HvServer
    )

    Start-VM -ComputerName $hvServer -Name $vmName
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running"
    Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer
    Save-VM -ComputerName $hvServer -Name $vmName -Confirm:$false
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Saved"
    try {
        Debug-VM -Name $VMName -InjectNonMaskableInterrupt `
            -ComputerName $HvServer -Confirm:$False -Force `
            -ErrorAction "Stop"
        LogErr "NMI could be sent when the VM ${VMName} is in saved state."
    } catch {
        LogMsg "NMI could not be sent when the VM ${VMName} is in saved state."
        $testStates["SavedState"] = $true
    }
}

function Execute-PausedStateTest {
    param(
        $VMName,
        $HvServer
    )

    Start-VM -ComputerName $hvServer -Name $vmName
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running"
    Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer
    Suspend-VM -ComputerName $hvServer -Name $vmName -Confirm:$false
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Paused"

    try {
        Debug-VM -Name $VMName -InjectNonMaskableInterrupt `
            -ComputerName $HvServer -Confirm:$False -Force `
            -ErrorAction "Stop"
        LogErr "NMI could be sent when the VM ${VMName} is in suspended state."
    } catch {
        LogMsg "NMI could not be sent when the VM ${VMName} is in suspended state."
        $testStates["SavedState"] = $true
    } finally {
        # Note(v-advlad): Needed by the test framework, as there might be failures
        # if the last test case does not bring the VM up
        Start-VM -ComputerName $hvServer -Name $vmName
        Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running"
    }
}

function Trigger-FailedNmiInterrupt {
    param(
        $VMName,
        $HvServer
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
                                         -HvServer $HvServer
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
     -HvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName

