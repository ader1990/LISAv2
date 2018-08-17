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
    This script tests the functionality of copying a 3GB large file multiple times.
.Description
    The script will copy a random generated 2GB file multiple times from a Windows host to
    the Linux VM, and then checks if the size is matching.

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

$testfile = $null
$gsi = $null

#######################################################################
#
#   Checks if the file copy daemon is running on the Linux guest
#
#######################################################################
function check_fcopy_daemon()
{
	$filename = ".\fcopy_present"

    .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "ps -ef | grep '[h]v_fcopy_daemon\|[h]ypervfcopyd' > /tmp/fcopy_present"
    if (-not $?) {
        LogErr  "ERROR: Unable to verify if the fcopy daemon is running" 
        return "ABORTED"
    }

    .\Tools\pscp.exe -C -pw $vmPassword -P $vmPort $vmUserName@${ipv4}:/tmp/fcopy_present .
    if (-not $?) {
		LogErr "ERROR: Unable to copy the confirmation file from the VM"
		return "ABORTED"
    }

    # When using grep on the process in file, it will return 1 line if the daemon is running
    if ((Get-Content $filename  | Measure-Object -Line).Lines -eq  "1" ) {
		Write-Output "Info: hv_fcopy_daemon process is running."
		$retValue = "PASSED"
    }

    del $filename
    return $retValue
}


#######################################################################
#
#   Checks if test file is present
#
#######################################################################
function check_file([String] $testfile)
{
    .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "wc -c < /tmp/$testfile"
    if (-not $?) {
        LogErr "ERROR: Unable to read file" 
        return "FAILED"
    }
	return "PASSED"
}

#######################################################################
#
#   Mount disk
#
#######################################################################
function mount_disk()
{
    . .\testscripts\Windows\TCUtils.ps1

    $driveName = "/dev/sdb"

    $sts = SendCommandToVM $vmPassword  $vmPort $vmUserName $ipv4 "(echo d;echo;echo w)|fdisk ${driveName}"
    if (-not $sts) {
        LogErr "ERROR: Failed to format the disk in the VM $vmName." 
        return "Failed"
    }

    $sts = SendCommandToVM $vmPassword  $vmPort $vmUserName $ipv4 "(echo n;echo p;echo 1;echo;echo;echo w)|fdisk ${driveName}" 
    if (-not $sts) {
        LogErr "ERROR: Failed to format the disk in the VM $vmName."
        return "Failed"
    }

    $sts = SendCommandToVM $vmPassword  $vmPort $vmUserName $ipv4 "mkfs.ext3 ${driveName}1"
    if (-not $sts) {
        LogErr "ERROR: Failed to make file system in the VM $vmName." 
        return "Failed"
    }

    $sts = SendCommandToVM $vmPassword  $vmPort $vmUserName $ipv4 "mount ${driveName}1 /mnt"
    if (-not $sts) {
        LogErr "ERROR: Failed to mount the disk in the VM $vmName." 
        return "Failed"
    }

    LogMsg "Info: $driveName has been mounted to /mnt in the VM $vmName."
    return "PASSED"
}

#################################################################
#
# Remove file from vm
#
#################################################################
function remove_file_vm(){
    . .\testscripts\Windows\TCUtils.ps1
    $sts = SendCommandToVM $vmPassword  $vmPort $vmUserName $ipv4 "rm -f /mnt/$testfile"
    if (-not $sts) {
        return "FAILED"
    }
    return "PASSED"
}

################################################################
#
# Copy the file to the Linux guest VM
#
################################################################
function copy_file_vm(){
    $Error.Clear()
    Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/mnt/" -FileSource host -ErrorAction SilentlyContinue
    if ($Error.Count -ne 0) {
        return "FAILED"
    }
    return "PASSED"
}

####################################################################################
#
# Checking if the file is present on the guest and file size is matching
#
####################################################################################
function check_file_vm(){
    $sts = check_file $testfile
    if (-not $sts[-1]) {
        LogErr "ERROR: File is not present on the guest VM '${vmName}'!" | Tee-Object -Append -file $summaryLog
        return "FAILED"
    }
    elseif ($sts[0] -ne $fileSize) {
        LogErr "ERROR: The file copied doesn't match the ${originalFileSize} size!" | Tee-Object -Append -file $summaryLog
        return "FAILED"
    }
    return "PASSED"
}

#######################################################################
#
#   Main body script
#
#######################################################################
$retVal = $false

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $retVal
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "ipv4") {
        $IPv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "FileSize") {
        $fileSize = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
   LogErr "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
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
# Delete any previous summary.log file, then create a new one
LogMsg "This script covers test case: ${TC_COVERED}" 
$retVal = "PASSED"

#
# Verify if the Guest services are enabled for this VM
#
$originalFileSize = $fileSize
$fileSize = $fileSize/1

$gsi = Get-VMIntegrationService -vmName $vmName -ComputerName $hvServer -Name "Guest Service Interface"
if (-not $gsi) {
    LogErr "Error: Unable to retrieve Integration Service status from VM '${vmName}'" 
    return "Aborted"
}

if (-not $gsi.Enabled) {
    LogMsg "Warning: The Guest services are not enabled for VM '${vmName}'" 
	if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
		Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
	}

	# Waiting until the VM is off
	while ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
        LogMsg "Turning off VM:'${vmName}'" 
        Start-Sleep -Seconds 5
	}
    LogMsg "Enabling  Guest services on VM:'${vmName}'"
    Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
    LogMsg "Starting VM:'${vmName}'"
	Start-VM -Name $vmName -ComputerName $hvServer

	# Waiting for the VM to run again and respond to SSH - port 22
	do {
		sleep 5
	} until (Test-NetConnection $IPv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )
}
# Get VHD path of tested server; file will be copied there
$vhd_path = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath

# Fix path format if it's broken
if ($vhd_path.Substring($vhd_path.Length - 1, 1) -ne "\"){
    $vhd_path = $vhd_path + "\"
}

$vhd_path_formatted = $vhd_path.Replace(':','$')

# Define the file-name to use with the current time-stamp
$testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file"

$filePath = $vhd_path + $testfile
$file_path_formatted = $vhd_path_formatted + $testfile

if ($gsi.OperationalStatus -ne "OK") {
   LogErr "Error: The Guest services are not working properly for VM '${vmName}'!" 
    $retVal = "FAILED"
}
else {
    # Create a sample file
    $createfile = fsutil file createnew \\$hvServer\$file_path_formatted $fileSize

    if ($createfile -notlike "File *testfile-*.file is created") {
       LogErr "Error: Could not create the sample test file in the working directory!" 
        $retVal = "FAILED"
    }
}

# Verifying if /tmp folder on guest exists; if not, it will be created
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "[ -d /tmp ]"
if (-not $?){
    LogMsg "Folder /tmp not present on guest. It will be created"
    .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "mkdir /tmp"
}

#
# The fcopy daemon must be running on the Linux guest VM
#
$sts = check_fcopy_daemon
if (-not $sts[-1]) {
    LogErr "ERROR: File copy daemon is not running inside the Linux guest VM!" 
    $retVal = "FAILED"
}

$sts = mount_disk
if (-not $sts[-1]) {
    LogErr "ERROR: Failed to mount the disk in the VM." 
    $retVal = "FAILED"
}

#
# Run the test
#
for($i=0; $i -ne 4; $i++){
    if ($retval) {
        $sts = copy_file_vm
        if (-not $sts) {
            LogErr "ERROR: File could not be copied!" 
            $retVal = "FAILED"
            break
        }
        LogMsg "Info: File has been successfully copied to guest VM '${vmName}'"

        $sts = check_file_vm
        if (-not $sts) {
            LogErr "ERROR: File check error on the guest VM '${vmName}'!" 
            $retVal = "FAILED"
            break
        }
        LogMsg "Info: The file copied matches the ${originalFileSize} size."

        $sts = remove_file_vm
        if (-not $sts) {
            LogErr "ERROR: Failed to remove file from VM $vmName." 
            $retVal = "FAILED"
            break
        }
        LogMsg "Info: File has been successfully removed from guest VM '${vmName}'"
    }
    else {
        break
    }
}

#
# Removing the temporary test file
#
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if (-not $?) {
    LogErr "ERROR: Cannot remove the test file '${testfile}'!" 
}

return $retVal
}

Main -vmName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Host.ServerName `
         -ipv4 $AllVMData.PublicIP -vmPort $AllVMData.SSHPort `
         -vmUserName $user -vmPassword $password -rootDir $WorkingDirectory `
         -testParams $testParams
