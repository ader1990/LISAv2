########################################################################
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
########################################################################

<#
.Synopsis
    MTU & netvsc reload test

#>

function Main {
    param (
        $VMName,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir
    )
    ##############################################################################
    #
    # Main script body
    #
    ##############################################################################
    # Change working directory to root dir
    Set-Location  $RootDir
    LogMsg "Changed working directory to $RootDir"
    # Start changing MTU on VM
    $mtu_values = 1505, 2048, 4096, 8192, 16384
    $iteration = 1
    foreach ($i in $mtu_values) {
        LogMsg "Changing MTU on VM to $i"
        RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort "echo 'sleep 5 && ip link set dev eth0 mtu $i &' > /home/$VMUserName/changeMTU.sh"
        RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort "bash /home/$VMUserName/changeMTU.sh > changeMTU.log 2>&1" -runAsSudo
        Start-Sleep -s 30
        Test-Connection -ComputerName $ipv4
        if (-not $?) {
            LogErr  "VM became unresponsive after changing MTU on VM to $i on iteration $iteration "
            return "FAIL"
        }
        $iteration++
    }
    LogMsg "Successfully changed MTU for $iteration times"


    # Start unloading/loading netvsc for 25 times
    $reloadCommand = @'
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

    # Check for file
    if (Test-Path ".\reload_netvsc.sh") {
        Remove-Item ".\reload_netvsc.sh"
    }

    Add-Content "reload_netvsc.sh" "$reloadCommand"
    $upload = RemoteCopy -uploadTo $Ipv4 -port $VMPort -files "reload_netvsc.sh" -username $VMUserName -password $VMPassword -upload
    $sts = RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort `
        "echo 'sleep 5 && bash $RootDir\reload_netvsc.sh &' > $RootDir\runtest.sh" -runAsSudo
    $test = RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort `
        "bash $RootDir\runtest.sh > $RootDir\reload_netvsc.log 2>&1" -runAsSudo
    $getlogs = RemoteCopy -download -downloadFrom $Ipv4 -files "$RootDir\reload_netvsc.log" `
        -downloadTo $LogDir -port $VMPort -username $VMUserName -password $VMPassword
    Start-Sleep -s 60

    $ipv4reload = Get-IPv4ViaKVP $VMName $HvServer
    LogMsg "${vmName} IP Address after reloading hv_netvsc: ${$ipv4reload}"
    Test-Connection -ComputerName $ipv4reload
    if (-not $?) {
        LogErr "VM became unresponsive after reloading hv_netvsc"
        return "FAIL"
    }
    else {
        LogMsg "Successfully reloaded hv_netvsc for 25 times"
        return "PASS"
    }
}
Main -VMName $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Host.ServerName `
    -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
    -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory
