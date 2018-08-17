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
    This script tests the file copy functionality.

.Description
    The script will generate a 100MB file with non-ascii characters. Then
    it will copy the file to the Linux VM. Finally, the script will verify
    both checksums (on host and guest).

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

$retVal = $false

#######################################################################
# Delete temporary test file
#######################################################################
function RemoveTestFile()
{
    Remove-Item -Path $pathToFile -Force
    if ($? -ne "True") {
        LogErr "Error: cannot remove the test file '${testfile}'!" 
        return "FAILED"
    }
}

#######################################################################
#
# Main script body
#
#######################################################################
#
# Checking the input arguments
#
if (-not $vmName) {
    "Error: VM name is null!"
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $retVal
}

# Check input params
$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
        switch ($fields[0].Trim())
        {
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "rootdir" { $rootDir = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        default  {}
        }
}


if ($null -eq $ipv4)
{
  LogErr  "Error: Test parameter ipv4 was not specified"
    return "FAILED"
}

if ($null -eq $rootdir)
{
  LogErr  "Error: Test parameter rootdir was not specified"
    return "FAILED"
}

# Change the working directory to where we need to be
cd $rootDir



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

# Check to see if the fcopy daemon is running on the VM
$sts = RunRemoteScript "FCOPY_Check_Daemon.sh"
if (-not $sts[-1])
{
   LogErr "Error executing FCOPY_Check_Daemon.sh on VM. Exiting test case!" 
    return "FAILED"
}

Remove-Item -Path "FCOPY_Check_Daemon.sh.log" -Force
LogMsg "Info: fcopy daemon is running on VM '${vmName}'"

#
# Creating the test file for sending on VM
#
if ($gsi.OperationalStatus -ne "OK") {
   LogErr "Error: The Guest services are not working properly for VM '${vmName}'!" 
    $retVal = "FAILED"
}
else {
    # Define the file-name to use with the current time-stamp
    $CurrentDir= "$pwd\"
    $testfile = "testfile-$(get-date -uformat '%H-%M-%S-%Y-%m-%d').file"
    $pathToFile="$CurrentDir"+"$testfile"

    # Sample string with non-ascii chars
    $nonAsciiChars="¡¢£¤¥§¨©ª«¬®¡¢£¤¥§¨©ª«¬®¯±µ¶←↑ψχφυ¯±µ¶←↑ψ¶←↑ψχφυ¯±µ¶←↑ψχφυχφυ"

    # Create a ~2MB sample file with non-ascii characters
    $stream = [System.IO.StreamWriter] $pathToFile
    1..8000 | % {
        $stream.WriteLine($nonAsciiChars)
    }
    $stream.close()

    # Checking if sample file was successfully created
    if (-not $?){
        LogErr "Error: Unable to create the 2MB sample file" 
        return "FAILED"
    }
    else {
        LogMsg "Info: initial 2MB sample file $testfile successfully created"
    }

    # Multiply the contents of the sample file up to an 100MB auxiliary file
    New-Item $MyDir"auxFile" -type file | Out-Null
    2..130| % {
        $testfileContent = Get-Content $pathToFile
        Add-Content $MyDir"auxFile" $testfileContent
    }

    # Checking if auxiliary file was successfully created
    if (-not $?){
        LogErr "Error: Unable to create the extended auxiliary file!" 
        return "FAILED"
    }

    # Move the auxiliary file to testfile
    Move-Item -Path $MyDir"auxFile" -Destination $pathToFile -Force

    # Checking file size. It must be over 85MB
    $testfileSize = (Get-Item $pathToFile).Length
    if ($testfileSize -le 85mb) {
        LogErr "Error: File not big enough. File size: $testfileSize MB" g
        $testfileSize = $testfileSize / 1MB
        $testfileSize = [math]::round($testfileSize,2)
        LogErr "Error: File not big enough (over 85MB)! File size: $testfileSize MB" 
        RemoveTestFile
        return "FAILED"
    }
    else {
        $testfileSize = $testfileSize / 1MB
        $testfileSize = [math]::round($testfileSize,2)
		LogMsg "Info: $testfileSize MB auxiliary file successfully created"
    }

    # Getting MD5 checksum of the file
    $local_chksum = Get-FileHash .\$testfile -Algorithm MD5 | Select -ExpandProperty hash
    if (-not $?){
       LogErr "Error: Unable to get MD5 checksum!" 
        RemoveTestFile
        return "FAILED"
    }
    else {
        LogMsg "MD5 file checksum on the host-side: $local_chksum"
    }

    # Get vhd folder
    $vhd_path = Get-VMHost -ComputerName $hvServer | Select -ExpandProperty VirtualHardDiskPath

    # Fix path format if it's broken
    if ($vhd_path.Substring($vhd_path.Length - 1, 1) -ne "\"){
        $vhd_path = $vhd_path + "\"
    }

    $vhd_path_formatted = $vhd_path.Replace(':','$')

    $filePath = $vhd_path + $testfile
    $file_path_formatted = $vhd_path_formatted + $testfile

    # Copy file to vhd folder
    Copy-Item -Path .\$testfile -Destination \\$hvServer\$vhd_path_formatted
}

# Removing previous test files on the VM
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "rm -f /tmp/testfile-*"

#
# Sending the test file to VM
#
$Error.Clear()
Copy-VMFile -vmName $vmName -ComputerName $hvServer -SourcePath $filePath -DestinationPath "/tmp/" -FileSource host -ErrorAction SilentlyContinue
if ($Error.Count -eq 0) {
    LogMsg "File has been successfully copied to guest VM '${vmName}'" 
}
elseif (($Error.Count -gt 0) -and ($Error[0].Exception.Message -like "*failed to initiate copying files to the guest: The file exists. (0x80070050)*")) {
    LogErr "Test failed! File could not be copied as it already exists on guest VM '${vmName}'" 
    return "FAILED"
}
RemoveTestFile

#
# Verify if the file is present on the guest VM
#
.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "stat /tmp/testfile-* > /dev/null" 2> $null
if (-not $?) {
	LogErr "Error: Test file is not present on the guest VM!" 
	return "FAILED"
}

#
# Verify if the file is present on the guest VM
#
$remote_chksum=.\Tools\plink.exe -C -pw $vmPassword -P $vmPort $vmUserName@$ipv4 "openssl MD5 /tmp/testfile-* | cut -f2 -d' '"
if (-not $?) {
	LogErr "Error: Could not extract the MD5 checksum from the VM!" 
	return "FAILED"
}

LogMsg"MD5 file checksum on guest VM: $remote_chksum" 

#
# Check if checksums are matching
#
$MD5IsMatching = @(Compare-Object $local_chksum $remote_chksum -SyncWindow 0).Length -eq 0
if ( -not $MD5IsMatching) {
    LogErr "Error: MD5 checksum missmatch between host and VM test file!" 
    return "FAILED"
}

Write-Output "Info: MD5 checksums are matching between the host-side and guest VM file." 

# Removing the temporary test file
Remove-Item -Path \\$hvServer\$file_path_formatted -Force
if ($? -ne "True") {
    LogErr "Error: cannot remove the test file '${testfile}'!" 
	return "FAILED"
}

#
# If we made it here, everything worked
#
LogMsg "Test completed successfully"
return "PASSED"
}

Main -vmName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Host.ServerName `
         -ipv4 $AllVMData.PublicIP -vmPort $AllVMData.SSHPort `
         -vmUserName $user -vmPassword $password -rootDir $WorkingDirectory `
         -testParams $testParams
