#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

param([String] $TestParams)

$RELOAD_COMMAND = @'
#!/bin/bash

pass=0
while [ $pass -lt 25 ]
do
    modprobe -r hv_netvsc
    sleep 1
    modprobe hv_netvsc
    sleep 1
    pass=$((pass+1))
    echo $pass > reload_netvsc.log
done
ifdown eth0 && ifup eth0
'@

function Main {
    param (
        $HvServer,
        $VMName,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir
    )

    # Start changing MTU on VM
    $mtu_values = 1505, 2048, 4096, 8192, 16384
    $iteration = 1
    foreach ($i in $mtu_values) {
        Write-LogInfo "Changing MTU on VM to $i"

        $null = Run-LinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort `
            -command "sleep 5 && ip link set dev eth0 mtu $i" -RunAsSudo

        Start-Sleep -s 30
        Test-Connection -ComputerName $ipv4
        if (-not $?) {
            Write-LogErr "VM became unresponsive after changing MTU on VM to $i on iteration $iteration "
            return "FAIL"
        }
        $iteration++
    }
    Write-LogInfo "Successfully changed MTU for $iteration times"

    $scriptPath = Join-Path $LogDir "reload_netvsc.sh"

    if (Test-Path $scriptPath) {
        Remove-Item $scriptPath
    }

    Add-Content $scriptPath "$RELOAD_COMMAND"
    Copy-RemoteFiles -uploadTo $Ipv4 -port $VMPort -password $VMPassword -username $VMUserName `
        -files $scriptPath -upload
    $null = Run-LinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort `
        -command "dos2unix reload_netvsc.sh && sleep 5 && bash reload_netvsc.sh" -RunInBackGround  -RunAsSudo

    Start-Sleep -s 600
    Get-IPv4AndWaitForSSHStart -VmName $VMName -HvServer $HvServer -Vmport $VMPort `
        -Password $VMPassword -username $VMUserName -StepTimeout 1000

    if (-not $?) {
        Write-LogErr "VM became unresponsive after reloading hv_netvsc"
        return "FAIL"
    }
    else {
        Write-LogInfo "Successfully reloaded hv_netvsc for 25 times"
        return "PASS"
    }
}

Main -VMName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
         -ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
         -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory
