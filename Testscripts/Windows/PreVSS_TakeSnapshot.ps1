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
    Creates a VM snapshot.

.Description
    This is useful if the default snapshot represents a clean state,
    then a temporary additional snapshot is needed before further changes.
    A typical test case definition for this test script would look
    similar to the following:
            <test>
            <testName>MainVM_Checkpoint</testName>
            <testScript>setupScripts\PreVSS_TakeSnapshot.ps1</testScript>
            <testParams>
                <param>TC_COVERED=snapshot</param>
                <param>snapshotName=ICABase</param>
                <param>snapshot_vm=main(dependency)</param>
            </testParams>
            <timeout>1500</timeout>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>
.Parameter vmName
    Name of the VM to perform the test with.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    A semicolon separated list of test parameters.
.Example
    setupScripts\PreVSS_TakeSnapshot.ps1 -vmName "myVm" -hvServer "localhost" -TestParams ""
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $false
$rootDir = $null
$ipv4 = $null
$sshKey = $null
$REMOTE_SERVER = $null
$snapshot_vm = ""

#
# Check input arguments
#
if (-not $vmName) {
    "Error: VM name is null."
    return $retVal
}

if (-not $hvServer) {
    "Error: hvServer is null."
    return $retVal
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and the logs folder as the test parameters."
    return $retVal
}

$vms = New-Object System.Collections.ArrayList
$vm = ""

#
# Checking the mandatory testParams
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
        switch -wildcard ($fields[0].Trim()) {
            "ipv4" { $ipv4 = $fields[1].Trim() }
            "rootdir" { $rootDir = $fields[1].Trim() }
            "VM[0-9]NAME" { $vm = $fields[1].Trim() }
            "snapshotName" { $snapshot = $fields[1].Trim() }
            "snapshotVm" { $snapshot_vm = $fields[1].Trim() }
    		"REMOTE_SERVER" { $remoteServer = $fields[1].Trim()}
            default  {}
        }
    if ($vm -ne "") {
        $vms.Add($vm)
        $vm = ""
    }
}

# if dependency VM runs on a different host, we need to map hvServer to it
if ( $snapshot_vm -eq "dependency" -and $remoteServer ) {
    $hvServer = $remoteServer
}

if ($snapshot_vm -ne "dependency") {
    $vms.Clear()
}

if ($snapshot_vm -eq "" -or $snapshot_vm -eq "main") {
    $vms.Add($vmName)
}

if (-not $rootDir) {
    "Error: Missing testParam rootDir value"
}

if (-not $ipv4) {
    "Error: Missing testParam ipv4 value"
    return $retVal
}

# Change the working directory for the log files
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $retVal
}
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

foreach ($vmName in $vms) {
    Write-Host "Waiting for VM $vmName to stop..."
    if ((Get-VM -ComputerName $hvServer -Name $vmName).State -ne "Off") {
        Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
    }

    #
    # Waiting until the VM is off
    #
    if (-not (WaitForVmToStop $vmName $hvServer 300)) {
        Write-Output "Error: Unable to stop VM"
        return $False
    }

    #
    # Take a snapshot then restore the VM to the snapshot
    #
    "Info: Taking snapshot of VM $vmName"

	try {
    Checkpoint-VM -Name $vmName -SnapshotName $snapshot -ComputerName $hvServer -ErrorAction Stop
	} catch {
        Write-Output "Error taking snapshot!" | Out-File -Append $summaryLog
		Write-Output $_
        return $False
    }

    #
    # Verify that the snapshot is present
    #
    $snapshot_check = Get-VMSnapshot $vmName -ComputerName $hvServer -Name $snapshot
    if ([string]::IsNullOrEmpty($snapshot_check)) {
        Write-Output "Error: Could not find a VM snapshot $snapshot" | Out-File -Append $summaryLog
        return $False
    }

    Write-Output "Snapshot has been created on $vmName." | Out-File -Append $summaryLog
    $retVal = $True
}
return $retVal
