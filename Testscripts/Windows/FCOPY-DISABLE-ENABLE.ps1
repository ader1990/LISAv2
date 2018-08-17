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
 This script tests the file copy functionality after a cycle of disable and
 enable of the Guest Service Integration.

.Description
 This script will disable and reenable Guest Service Interface for a number
 of times, it will check the service and daemon integrity and if everything is
 fine it will copy a 5GB large file from host to guest and then check if the size
 is matching.


#>
param([String] $TestParams)

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



# Read parameters
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
#    $value = $fields[1].Trim()

    switch ($fields[0].Trim()) {
        "ipv4"      { $ipv4    = $fields[1].Trim() }
        "rootDIR"   { $rootDir = $fields[1].Trim() }
        "DefaultSize"   { $DefaultSize = $fields[1].Trim() }
        "TC_COVERED"    { $TC_COVERED = $fields[1].Trim() }
        "Type"          { $Type = $fields[1].Trim() }
        "SectorSize"    { $SectorSize = $fields[1].Trim() }
        "ControllerType"{ $controllerType = $fields[1].Trim() }
        "CycleCount"    { $CycleCount = $fields[1].Trim() }
        "FcopyFileSize" { $FcopyFileSize = $fields[1].Trim() }
        default     {}  # unknown param - just ignore it
    }
}

# Main script body

# Validate parameters
if (-not $vmName) {
    LogErr "Error: VM name is null!"
    return "FAILED"
}

if (-not $hvServer) {
    Write-Output "Error: hvServer is null!"
    LogErr "FAILED"
}

if (-not $testParams) {
    Write-Output"Error: No testParams provided!"
    return "FAILED"
}

# Change directory
cd $rootDir

# Source TCUtils.ps1
if (Test-Path ".\testscripts\Windows\TCUtils.ps1") {
    . .\testscripts\Windows\TCUtils.ps1
} else {
   LogErr "Error: Could not find setupScripts\TCUtils.ps1"
}

# if host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0)
{
    return "FAILED"
}
elseif ($BuildNumber -lt 9600)
{
    return "Skipped"
}

LogMsg "This script covers test case: ${TC_COVERED}" 


# Check VM state
$currentState = CheckVMState $vmName $hvServer
if ($? -ne "True") {
    LogErr "Error: Cannot check VM state" 
    return "FAILED"
}

# If the VM is in any state other than running power it ON
if ($currentState -ne "Running") {
    LogMsg "Found $vmName in $currentState state. Powering ON ... " 
    Start-VM -vmName $vmName -ComputerName $hvServer
    if ($? -ne "True") {
        LogErr "Error: Unable to Power ON the VM" 
        return "FAILED"
    }
    Start-Sleep 60
}

$checkVM = Check-Systemd
if ($checkVM -eq "True") {

    # Get Integration Services status
    $gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
    if ($? -ne "True") {
            LogErr "Error: Unable to run Get-VMIntegrationService on $vmName ($hvServer)" 
            return "FAILED"
    }

    # If guest services are not enabled, enable them
    if ($gsi.Enabled -ne "True") {
        Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            LogErr "Error: Unable to enable VMIntegrationService on $vmName ($hvServer)" 
            return "FAILED"
        }
    }

    # Disable and Enable Guest Service according to the given parameter
    $counter = 0
    while ($counter -lt $CycleCount) {
        Disable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            LogErr "Error: Unable to disable VMIntegrationService on $vmName ($hvServer) on $counter run"
            return "FAILED"
        }
        Start-Sleep 5

        Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            LogErr "Error: Unable to enable VMIntegrationService on $vmName ($hvServer) on $counter run"
            return "FAILED"
        }
        Start-Sleep 5
        $counter += 1
    }

    LogMsg "Disabled and Enabled Guest Services $counter times" 

    # Get VHD path of tested server; file will be copied there
    $hvPath = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath
    if ($? -ne "True") {
        LogErr "Error: Unable to get VM host" | Tee-Object -Append -file $summaryLog
        return "FAILED"
    }

    # Fix path format if it's broken
    if ($hvPath.Substring($hvPath.Length - 1, 1) -ne "\") {
        $hvPath = $hvPath + "\"
    }

    $hvPathFormatted = $hvPath.Replace(':','$')

    # Define the file-name to use with the current time-stamp
    $testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file"
    $filePath = $hvPath + $testfile
    $filePathFormatted = $hvPathFormatted + $testfile

    # Make sure the fcopy daemon is running and Integration Services are OK
    $timer = 0
    while ((Get-VMIntegrationService $vmName | ?{$_.name -eq "Guest Service Interface"}).PrimaryStatusDescription -ne "OK")
    {
        Start-Sleep -Seconds 5
        LogMsg "Waiting for VM Integration Services $timer"
        $timer += 1
        if ($timer -gt 20) {
            break
        }
    }

    $operStatus = (Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface").PrimaryStatusDescription
    LogMsg "Current Integration Services PrimaryStatusDescription is: $operStatus"
    if ($operStatus -ne "Ok") {
        Write-Output "Error: The Guest services are not working properly for VM $vmName!" 
        return "FAILED"
    }
    else {
        . .\setupscripts\STOR_VHDXResize_Utils.ps1
        $fileToCopySize = ConvertStringToUInt64 $FcopyFileSize

        # Create a 5GB sample file
        $createFile = fsutil.exe file createnew \\$hvServer\$filePathFormatted $fileToCopySize
        if ($createFile -notlike "File *testfile-*.file is created") {
            LogErr "Error: Could not create the sample test file in the working directory!" 
            return "FAILED"
        }
    }

    # Mount attached VHDX
    $sts = Mount-Disk
    if (-not $sts[-1]) {
        LogErr "Error: Failed to mount the disk in the VM." 
        return "FAILED"
    }

    # Daemon name might vary. Get the correct daemon name based on systemctl output
    $daemonName = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "systemctl list-unit-files | grep fcopy"
    $daemonName = $daemonName.Split(".")[0]

    $checkProcess = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "systemctl is-active $daemonName"
    if ($checkProcess -ne "active") {
        LogErr "Warning: $daemonName was not automatically started by systemd. Will start it manually."
         $startProcess = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "systemctl start $daemonName"
    }

    $gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
    if ($gsi.Enabled -ne "True") {
        LogErr "Error: FCopy Integration Service is not enabled"
        return "FAILED"
    }

    # Check for the file to be copied
    Test-Path $filePathFormatted
    if ($? -ne "True") {
        LogErr "Error: File to be copied not found." 
        return "FAILED"
    }

    $Error.Clear()
    $copyDuration = (Measure-Command { Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath `
        "/mnt/" -FileSource host -ErrorAction SilentlyContinue }).totalseconds

    if ($Error.Count -eq 0) {
        LogMsg "Info: File has been successfully copied to guest VM '${vmName}'"
    } else {
        LogErr "Error: File could not be copied!"
        return "FAILED"
    }

    [int]$copyDuration = [math]::floor($copyDuration)
    LogMsg "Info: The file copy process took ${copyDuration} seconds" 

    # Checking if the file is present on the guest and file size is matching
    $sts = CheckFile /mnt/$testfile
    if (-not $sts[-1]) {
        LogErr "Error: File is not present on the guest VM"
        return "FAILED"
    }
    elseif ($sts[0] -eq $fileToCopySize) {
        LogMsg "Info: The file copied matches the $FcopyFileSize size."
        return "PASSED"
    }
    else {
        LogErr "Error: The file copied doesn't match the $FcopyFileSize size!"
        return "FAILED"
    }

    # Removing the temporary test file
    Remove-Item -Path \\$hvServer\$filePathFormatted -Force
    if (-not $?) {
        LogErr "Error: Cannot remove the test file '${testfile}'!"
        return "FAILED"
    }

    # Check if there were call traces during the test
    .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "dos2unix -q check_traces.sh"
    if (-not $?) {
        LogErr "Error: Unable to run dos2unix on check_traces.sh" 
    }
    $sts = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "echo 'sleep 5 && bash ~/check_traces.sh ~/check_traces.log &' > runtest.sh"
    $sts = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "chmod +x ~/runtest.sh"
    $sts = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "./runtest.sh > check_traces.log 2>&1"
    Start-Sleep 6
    $sts = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "cat ~/check_traces.log | grep ERROR"
    if ($sts.Contains("ERROR")) {
        LogMsg "Warning: Call traces have been found on VM"
    }
    if ($sts -eq $NULL) {
        LogMsg "Info: No Call traces have been found on VM"
    }
    return "PASSED"
}
else {
    LogMsg "Systemd is not being used. Test Skipped" 
    return "Skipped"
}
}

Main -vmName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Host.ServerName `
         -ipv4 $AllVMData.PublicIP -vmPort $AllVMData.SSHPort `
         -vmUserName $user -vmPassword $password -rootDir $WorkingDirectory `
         -testParams $testParams
