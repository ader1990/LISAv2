# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.


<#
.Synopsis
    This script tests the file copy negative functionality test.

.Description
    The script will verify fail to copy a random generated 10MB file from Windows host to
	the Linux VM, when target folder is immutable, 'Guest Service Interface' disabled and
	hyperverfcopyd is disabled.

#>

param([String] $TestParams,
      [object] $AllVmData)

function Main {
    param (
        $VMName,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir,
        $TestParams
    )

    $testfile = "$null"

    #######################################################################
    #
    #	Main body script
    #
    #######################################################################

    #
    # Change the working directory for the log files
    Set-Location $RootDir
    # If host build number lower than 9600, skip test
    $BuildNumber = Get-HostBuildNumber -hvServer $HvServer
    if ($BuildNumber -eq 0) {
        return "FAIL"
    }
    elseif ($BuildNumber -lt 9600) {
        Write-LogInfo "Hyper-v host version $BuildNumber does not support fcopy, skipping test."
        return "ABORTED"
    }

    # If vm does not support systemd, skip test.
    $null = Check-Systemd -Ipv4 $Ipv4 -SSHPort $VMPort -Username $VMUserName -Password $VMPassword
    if ( -not $True) {
        Write-LogInfo "Systemd is not being used. Test Skipped"
        return "FAIL"
    }


    # Delete any previous test files
    .\Tools\plink.exe -C -pw $VMPassword -P $VMPort $VMUserName@$Ipv4 "rm -rf /tmp/testfile-* 2>/dev/null"
    #
    # Setup: Create temporary test file in the host
    #
    # Get VHD path of tested server; file will be created there
    $vhd_path = Get-VMHost -ComputerName $HvServer | Select-Object -ExpandProperty VirtualHardDiskPath

    # Fix path format if it's broken
    if ($vhd_path.Substring($vhd_path.Length - 1, 1) -ne "\") {
        $vhd_path = $vhd_path + "\"
    }
    $vhd_path_formatted = $vhd_path.Replace(':', '$')
    # Define the file-name to use with the current time-stamp
    $testfile = "testfile-$(Get-Date -uformat '%H-%M-%S-%Y-%m-%d').file"
    $filePath = $vhd_path + $testfile
    $file_path_formatted = $vhd_path_formatted + $testfile

    # Create a 10MB sample file
    Write-LogInfo "Creating a 10MB sample file..."
    $createfile = fsutil file createnew \\$HvServer\$file_path_formatted 10485760

    if ($createfile -notlike "File *testfile-*.file is created") {
        Write-LogErr "Could not create the sample test file in the working directory!"
        return "FAIL"
    }

    #
    # Verify if the Guest services are enabled for this VM
    #
    $gsi = Get-VMIntegrationService -VMname $VMName -ComputerName $HvServer -Name "Guest Service Interface"
    if (-not $gsi) {
        Write-LogErr "Unable to retrieve Integration Service status from VM '${VMname}'"
        return "ABORTED"
    }
    if (-not $gsi.Enabled) {
        Write-LogWarn "The Guest services are not enabled for VM '${VMname}'"
        if ((Get-VM -ComputerName $HvServer -Name $VMName).State -ne "Off") {
            Stop-VM -ComputerName $HvServer -Name $VMName -Force -Confirm:$false
        }
        # Waiting until the VM is off
        while ((Get-VM -ComputerName $HvServer -Name $VMName).State -ne "Off") {
            Write-LogInfo "Turning off VM:'${VMname}'"
            Start-Sleep -Seconds 5
        }
        Write-LogInfo "Enabling  Guest services on VM:'${VMname}'"
        Enable-VMIntegrationService -Name "Guest Service Interface" -VMname $VMName -ComputerName $HvServer
        Write-LogInfo "Starting VM:'${VMname}'"
        Start-VM -Name $VMName -ComputerName $HvServer
        # Waiting for the VM to run again and respond
        Write-LogInfo "Waiting for the VM to run again and respond ..."
        if (-not (Wait-ForVMToStartSSH -Ipv4addr $Ipv4 -StepTimeout 200)) {
            Write-LogErr  "Test case timed out waiting for VM to be running again!"
            return "FAIL"
        }
    }
    # The fcopy daemon must be running on the Linux guest VM
    $sts = Check-FcopyDaemon  -VMPassword $VMPassword -VMPort $VMPort -VMUserName $VMUserName -Ipv4 $Ipv4
    if (-not $sts[-1]) {
        Write-LogErr "File copy daemon is not running inside the Linux guest VM!"
        return "FAIL"
    }
    #
    # Step 1: verify the file cannot copy to vm when target folder is immutable
    #
    Write-LogInfo "Info: Step 1: fcopy file to vm when target folder is immutable"

    # Verifying if /tmp folder on guest exists; if not, it will be created
    .\Tools\plink.exe -C -pw $VMPassword -P $VMPort $VMUserName@$ipv4 "sudo [ -d /test ] || mkdir /test ; chattr +i /test"

    if (-not $?) {
        Write-LogErr "Fail to change the permission for /test"
    }

    $Error.Clear()
    Copy-VMFile -vmName $VMName -ComputerName $HvServer -SourcePath $filePath -DestinationPath "/test" -FileSource host -ErrorAction SilentlyContinue

    if ( $? -eq $true ) {
        Write-LogErr  "File has been copied to guest VM even  target folder immutable"
        return "FAIL"
    }
    elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*FAIL to initiate copying files to the guest*")) {
        Write-LogInfo  "Info: File could not be copied to VM as expected since target folder immutable"
    }

    #
    # Step 2: verify the file cannot copy to vm when "Guest Service Interface" is disabled
    #
    Write-LogInfo "Info: Step 2: fcopy file to vm when 'Guest Service Interface' is disabled"
    Disable-VMIntegrationService -Name "Guest Service Interface" -vmName $VMName -ComputerName $HvServer
    if ( $? -eq $false) {
        Write-LogErr "Fail to disable 'Guest Service Interface'"
        return "FAIL"
    }

    $Error.Clear()
    Copy-VMFile -vmName $VMName -ComputerName $HvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

    if ( $? -eq $true ) {
        Write-LogErr "File has been copied to guest VM even 'Guest Service Interface' disabled"
        return "FAIL"
    }
    elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*FAIL to initiate copying files to the guest*")) {
        Write-LogInfo "Info: File could not be copied to VM as expected since 'Guest Service Interface' disabled"

        #
        # Step 3: verify the file cannot copy to vm when hypervfcopyd is stopped
        #
        Write-LogInfo "Info: Step 3: fcopy file to vm when hypervfcopyd stopped"
        Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $VMName -ComputerName $HvServer
        if ( $? -ne $true) {
            Write-LogErr "Fail to enable 'Guest Service Interface'"
            return "FAIL"
        }

        # Stop fcopy daemon to do negative test
        $sts = Stop-FcopyDaemon -VmPassword $VMPassword -vmPort $VMPort -vmUserName $VMUserName -ipv4 $Ipv4
        if (-not $sts[-1]) {
            Write-LogErr "FAIL to stop hypervfcopyd inside the VM!"
            return "FAIL"
        }

        $Error.Clear()
        Copy-VMFile -vmName $VMName -ComputerName $HvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

        if ( $? -eq $true ) {
            Write-LogErr "File has been copied to guest VM even hypervfcopyd stopped"
            return "FAIL"
        }
        elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*FAIL to initiate copying files to the guest*")) {
            Write-LogInfo "Info: File could not be copied to VM as expected since hypervfcopyd stopped "
        }

        # Verify the file does not exist after hypervfcopyd start
        $daemonName = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $VMUserName@$Ipv4 "sudo systemctl list-unit-files | grep fcopy"
        $daemonName = $daemonName.Split(".")[0]
        .\Tools\plink.exe -C -pw $VMPassword -P $VMPort $VMUserName@$Ipv4 "sudo systemctl start $daemonName"
        Start-Sleep -s 2
        .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $VMUserName@$Ipv4 "sudo ls /tmp/testfile-*"
        if ($? -eq $true) {
            Write-LogErr "File has been copied to guest vm after restart hypervfcopyd"
            return "FAIL"
        }
        # Removing the temporary test file
        Remove-Item -Path \\$hvServer\$file_path_formatted -Force
        if ($? -ne "True") {
            Write-LogErr "Cannot remove the test file '${testfile}'!"
        }

        return "PASS"
    }

}

Main -VMName $AllVMData.RoleName -HvServer $GlobalConfig.Global.Hyperv.Hosts.ChildNodes[0].ServerName `
    -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
    -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory `
    -TestParams $testParams
