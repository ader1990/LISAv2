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
    This script tests the file copy overwrite functionality.

.Description
    The script will copy a file from a Windows host to the Linux VM,
    and checks if the size is matching.
	Then it tries to copy the same file again, which must fail with an
	error message that the file already exists - error code 0x80070050.



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

$retVal = "FAILED"
$testfile = $null
$gsi = $null


#######################################################################
#
#	Main body script
#
#######################################################################
# Debug - display the test parameters so they are captured in the log file
LogMsg "TestParams : '${testParams}'"
# Checking the input arguments
if (-not $vmName) {
   LogErr "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    LogErr  "Error: hvServer is null!"
    return $retVal
}

if (-not $testParams) {
    LogErr "Error: No testParams provided!"
    LogErr  "This script requires the test case ID and VM details as the test parameters."
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

# if host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0)
{
    return "FAILED"
}
elseif ($BuildNumber -lt 9600)
{
    return "PASSED"
}

$retVal = "PASSED"


#
# Verify if the Guest services are enabled for this VM
#
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
     # Create a 10MB sample file
     $createfile = fsutil file createnew \\$hvServer\$file_path_formatted 10485760
 
     if ($createfile -notlike "File *testfile-*.file is created") {
     LogErr	"Error: Could not create the sample test file in the working directory!" 
         $retVal = "FAILED"
     }
 }

# Verifying if /tmp folder on guest exists; if not, it will be created
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "[ -d /tmp ]"
if (-not $?){
    LogMsg "Folder /tmp not present on guest. It will be created"
    .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "mkdir /tmp"
}

# The fcopy daemon must be running on the Linux guest VM
$sts = check_fcopy_daemon
if (-not $sts[-1]) {
    LogErr "ERROR: file copy daemon is not running inside the Linux guest VM!" 
    $retVal = "FAILED"
}

# Removing previous test files on the VM
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "rm -rf /tmp/testfile-*"

# If we got here then all checks have passed and we can copy the file to the Linux guest VM
# Initial file copy, which must be successful
$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue
if ($error.Count -eq 0) {
	# Checking if the file size is matching
	$sts = CheckFile "/tmp/$testfile" $True

	if (-not $sts[-1]) {
		LogErr "ERROR: File is not present on the guest VM '${vmName}'!"
		$retVal = "FAILED"
	}
	elseif ($sts[0] -eq 10485760) {
		LogMsg "Info: The file copied matches the 10MB size." 
	}
    else {
	    LogErr "ERROR: The file copied doesn't match the 10MB size!" 
	    $retVal = "FAILED"
    }
}
elseif ($Error.Count -gt 0) {
	LogErr "Test Failed. An error has occurred while copying the file to guest VM '${vmName}'!" 
	$error[0] 
	$retVal = "FAILED"
}

$Error.Clear()
# Second copy file attempt must fail with the below error code pattern
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

if ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest: The file exists. (0x80070050)*") {
	LogMsg "Test passed! File could not be copied as it already exists on guest VM '${vmName}'" 
}
elseif ($error.Count -eq 0) {
	LogErr "Error: File '${testfile}' has been copied twice to guest VM '${vmName}'!" 
	$retVal = "FAILED"
}

# Removing the temporary test file
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if ($? -ne "True") {
    LogErr "ERROR: cannot remove the test file '${testfile}'!" 
}

return $retVal
}
Main -vmName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Host.ServerName `
         -ipv4 $AllVMData.PublicIP -vmPort $AllVMData.SSHPort `
         -vmUserName $user -vmPassword $password -rootDir $WorkingDirectory `
         -testParams $testParams
