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
    This script tests the file copy negative functionality test.

.Description
    The script will verify fail to copy a random generated 10MB file from Windows host to
	the Linux VM, when target folder is immutable, 'Guest Service Interface' disabled and
	hyperverfcopyd is disabled.

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

#######################################################################
#
#	Main body script
#
#######################################################################

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
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

# If host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0){
    return "FAILED"
}
elseif ($BuildNumber -lt 9600){
    LogMsg "Hyper-v host version $BuildNumber does not support fcopy, skipping test." 
    return "Skipped"
}

# If vm does not support systemd, skip test.
$sts = Check-Systemd
if ($sts[-1] -eq $false){
    LogMsg "Distro does not support systemd, skipping test."
    return "Skipped"
}

# Delete any previous summary.log file, then create a new one

LogMsg "This script covers test case: ${TC_COVERED}" 

# Delete any previous test files
echo y | \Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 exit
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "rm -rf /tmp/testfile-* 2>/dev/null"

#
# Setup: Create temporary test file in the host
#
# Get VHD path of tested server; file will be created there
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

# Create a 10MB sample file
$createfile = fsutil file createnew \\$hvServer\$file_path_formatted 10485760

if ($createfile -notlike "File *testfile-*.file is created") {
   LogErr "Error: Could not create the sample test file in the working directory!"
    return "FAILED"
}

Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer

if ( $? -ne $true) {
    LogErr "Error: The Guest services are not working properly for VM!"
    return "FAILED"
}

# The fcopy daemon must be running on the Linux guest VM
$sts = check_fcopy_daemon
if (-not $sts[-1]) {
    LogErr "ERROR: file copy daemon is not running inside the Linux guest VM!"
    return "FAILED"
}
#
# Step 1: verify the file cannot copy to vm when target folder is immutable
#
LogMsg "Info: Step 1: fcopy file to vm when target folder is immutable"

# Verifying if /tmp folder on guest exists; if not, it will be created
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "[ -d /test ] || mkdir /test ; chattr +i /test"

if (-not $?){
    LogErr "Error: Fail to change the permission for /test"
}

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/test" -FileSource host -ErrorAction SilentlyContinue

if ( $? -eq $true ) {
    LogErr  "Error: File has been copied to guest VM even  target folder immutable "
    return "FAILED"
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest*")) {
    LogMsg $Error[0].Exception.Message
    LogMsg  "Info: File could not be copied to VM as expected since target folder immutable"
}

#
# Step 2: verify the file cannot copy to vm when "Guest Service Interface" is disabled
#
LogMsg "Info: Step 2: fcopy file to vm when 'Guest Service Interface' is disabled"
Disable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
if ( $? -eq $false) {
    LogErr "Error: Fail to disable 'Guest Service Interface'" 
    return "FAILED"
}

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

if ( $? -eq $true ) {
   LogErr "Error: File has been copied to guest VM even 'Guest Service Interface' disabled"
    return "FAILED"
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*Failed to initiate copying files to the guest*")) {
    LogMsg $Error[0].Exception.Message
    LogMsg "Info: File could not be copied to VM as expected since 'Guest Service Interface' disabled"

#
# Step 3: verify the file cannot copy to vm when hypervfcopyd is stopped
#
LogMsg "Info: Step 3: fcopy file to vm when hypervfcopyd stopped"
Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
if ( $? -ne $true) {
    "Error: Fail to enable 'Guest Service Interface'" 
    return "FAILED"
}

# Stop fcopy daemon to do negative test
$sts = stop_fcopy_daemon
if (-not $sts[-1]) {
    LogErr "ERROR: Failed to stop hypervfcopyd inside the VM!"
    return "FAILED"
}

$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue

if ( $? -eq $true ) {
    LogErr "Error: file has been copied to guest VM even hypervfcopyd stopped"
    return "FAILED"
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest*")) {
    LogMsg $Error[0].Exception.Message
    LogMsg "Info: File could not be copied to VM as expected since hypervfcopyd stopped "
}

# Verify the file does not exist after hypervfcopyd start
$daemonName = .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "systemctl list-unit-files | grep fcopy"
$daemonName = $daemonName.Split(".")[0]
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "systemctl start $daemonName"
start-sleep -s 2
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "ls /tmp/testfile-*"
if ($? -eq $true) {
    Write-Output "Error: File has been copied to guest vm after restart hypervfcopyd"
    return "FAILED"
}
# Removing the temporary test file
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if ($? -ne "True") {
   LogErr "ERROR: cannot remove the test file '${testfile}'!" 
}

return "PASSED"
}

}

Main -vmName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Host.ServerName `
         -ipv4 $AllVMData.PublicIP -vmPort $AllVMData.SSHPort `
         -vmUserName $user -vmPassword $password -rootDir $WorkingDirectory `
         -testParams $testParams
