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
    This script tests the file copy from host to guest overwrite functionality.

.Description
    The script will copy a text file from a Windows host to the Linux VM,
    and checks if the size and content are correct.
	Then it modifies the content of the file to a smaller size on host,
    and then copy it to the VM again, with parameter -Force, to overwrite
    the file, and then check if the size and content are correct.


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
#	Checks if the file copy daemon is running on the Linux guest
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
#	Check if the test file is present, and get the size and content
#
#######################################################################
function check_file([String] $testfile)
{
    .\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "wc -c < /tmp/$testfile"
    if (-not $?) {
        LogErr "ERROR: Unable to read file /tmp/$testfile."
        return "FAILED"
    }

    $sts = SendCommandToVM $ipv4 $sshKey "dos2unix /tmp/$testfile"
    if (-not $sts) {
        Write-Output "ERROR: Failed to convert file /tmp/$testfile to unix format." -ErrorAction SilentlyContinue
        return "FAILED"
    }

	.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "cat /tmp/$testfile"
    if (-not $?) {
        Write-Output "ERROR: Unable to read file /tmp/$testfile." -ErrorAction SilentlyContinue
        return "FAILED"
    }
    return "PASSED"
}

#######################################################################
#
#	Generate random string
#
#######################################################################
function generate_random_string([Int] $length)
{
    $set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
    $result = ""
    for ($x = 0; $x -lt $length; $x++)
    {
        $result += $set | Get-Random
    }
    return $result
}

#######################################################################
#
#	Write, copy and check file
#
#######################################################################
function copy_and_check_file([String] $testfile, [Boolean] $overwrite, [Int] $contentlength, [String]$filePath, [String]$vhd_path_formatted)
{
    # Write the file
    $filecontent = generate_random_string $contentlength

    $filecontent | Out-File $testfile
    if (-not $?) {
       LogErr "ERROR: Cannot create file $testfile'." 
        return "FAILED"
    }

    $filesize = (Get-Item $testfile).Length
    if (-not $filesize){
        LogErr "ERROR: Cannot get the size of file $testfile'." 
        return "FAILED"
    }

    # Copy file to vhd folder
    Copy-Item -Path .\$testfile -Destination \\$hvServer\$vhd_path_formatted

    # Copy the file and check copied file
    $Error.Clear()
    if ($overwrite) {
        Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue -Force
    }
    else {
        Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue
    }
    if ($Error.Count -eq 0) {
        $sts = check_file $testfile
        if (-not $sts[-1]) {
            LogErr "ERROR: File is not present on the guest VM '${vmName}'!" 
            return "FAILED"
        }
        elseif ($sts[0] -ne $filesize) {
            LogErr "ERROR: The copied file doesn't match the $filesize size." g
            return "FAILED"
        }
        elseif ($sts[1] -ne $filecontent) {
            LogErr "ERROR: The copied file doesn't match the content '$filecontent'." 
            return "FAILED"
        }
        else {
            LogMsg "Info: The copied file matches the $filesize size and content '$filecontent'." 
        }
    }
    else {
        LogErr "ERROR: An error has occurred while copying the file to guest VM '${vmName}'." 
	    $error[0] 
	    return "FAILED"
    }
    return "PASSED"
}


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
	if ($fields[0].Trim() -eq "ipv4") {
		$IPv4 = $fields[1].Trim()
    }
	if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
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


# if host build number lower than 9600, skip test
$BuildNumber = GetHostBuildNumber $hvServer
if ($BuildNumber -eq 0)
{
    return $false
}
elseif ($BuildNumber -lt 9600)
{
    return $Skipped
}

# Delete any previous summary.log file, then create a new one

LogMSG "This script covers test case: ${TC_COVERED}" 

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
   LogErr "ERROR: file copy daemon is not running inside the Linux guest VM!" 
    $retVal = "FAILED"
}

# Define the file-name to use with the current time-stamp
$testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file"

# Removing previous test files on the VM
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "rm -f /tmp/testfile-*"

#
# Initial file copy, which must be successful. Create a text file with 20 characters, and then copy it.
#
$vhd_path = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath

# Fix path format if it's broken
if ($vhd_path.Substring($vhd_path.Length - 1, 1) -ne "\"){
    $vhd_path = $vhd_path + "\"
}

$vhd_path_formatted = $vhd_path.Replace(':','$')

$filePath = $vhd_path + $testfile
$file_path_formatted = $vhd_path_formatted + $testfile

$sts = copy_and_check_file $testfile $False 20 $filePath $vhd_path_formatted
if (-not $sts[-1]) {
    LogErr "ERROR: Failed to initially copy the file '${testfile}' to the VM." 
    $retVal = "FAILED"
}
else {
    LogMsg "Info: The file has been initially copied to the VM '${vmName}'." 
}

#
# Second copy file overwrites the initial file. Re-write the text file with 15 characters, and then copy it with -Force parameter.
#
$sts = copy_and_check_file $testfile $True 15 $filePath $vhd_path_formatted
if (-not $sts[-1]) {
    LogErr "ERROR: Failed to overwrite the file '${testfile}' to the VM." 
    $retVal = "FAILED"
}
else {
    LogMsg "Info: The file has been overwritten to the VM '${vmName}'." 
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
