#####################################################################
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

#####################################################################

<#
.Synopsis
 Configure Dynamic Memory for given Virtual Machines.

 Description:
   Configure Dynamic Memory parameters for a set of Virtual Machines.
   The testParams have the format of:

      vmName=Name of a VM, enableDM=[yes|no], minMem= (decimal) [MB|GB|%], maxMem=(decimal) [MB|GB|%],
      startupMem=(decimal) [MB|GB|%], memWeight=(0 < decimal < 100)

   vmName is the name of a existing Virtual Machines.

   enable specifies if Dynamic Memory should be enabled or not on the given Virtual Machines.
     accepted values are: yes | no

   minMem is the minimum amount of memory assigned to the specified virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host

   maxMem is the maximum memory amount assigned to the virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host

   startupMem is the amount of memory assigned at startup for the given VM
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host
   memWeight is the priority a given VM has when assigning Dynamic Memory
    the memory weight is a decimal between 0 and 100, 0 meaning lowest priority and 100 highest.
   The following is an example of a testParam for configuring Dynamic Memory
       "enableDM=yes;minMem=512MB;maxMem=50%;startupMem=1GB;memWeight=20"
   All setup and cleanup scripts must return a boolean ($true or $false)
   to indicate if the script completed successfully or not.

#>

param([String] $TestParams)

function Main {
    param (
        $VMName,
        $HvServer,
        $TestParams
    )

    $tpEnabled = $null
    [int64]$tPminMem = 0
    [int64]$tPmaxMem = 0
    [int64]$tPstartupMem = 0
    [int64]$tPmemWeight = -1
    $bootLargeMem = $false

    $vm2Name = $null
    $vm3Name = $null

    $params = ConvertFrom-StringData $TestParams.Replace(";", "`n")
    foreach ($p in $params) {
        $fields = $p.Split("=")
        switch ($fields[0].Trim()) {
            "VM2NAME" { $vm2Name = $fields[1].Trim() }
            "VM3NAME" { $vm3Name = $fields[1].Trim() }
            default {}
        }
    }

    #
    # Parse the testParams string, then process each parameter
    #
    $params = ConvertFrom-StringData $TestParams.Replace(";", "`n")
    #check vm number
    $VM_Number = 0
    foreach ($p in $params) {
        $temp = $p.Trim().Split('=')
        if ($temp.Length -ne 2) {
            # Ignore and move on to the next parameter
            continue
        }
        if ($temp[0].Trim() -eq "enableDM") {
            $VM_Number = $VM_Number + 1
            if ($temp[1].Trim() -ilike "yes") {
                $tpEnabled = $true
            }
            else {
                $tpEnabled = $false
            }
            LogMsg "dm enabled: $tpEnabled"
        }
        elseif ($temp[0].Trim() -eq "bootLargeMem") {
            if ($temp[1].Trim() -ilike "yes") {
                $bootLargeMem = $true
            }
            LogMsg  "BootLargeMemory: $bootLargeMem"
        }
        elseif ($temp[0].Trim() -eq "minMem") {
            $tPminMem = Convert-ToMemSize $temp[1].Trim() $HvServer

            if ($tPminMem -le 0) {
                LogErr  "Unable to convert minMem to int64."
                return $false
            }
            LogMsg "minMem: $tPminMem"
        }
        elseif ($temp[0].Trim() -eq "maxMem") {
            $maxMem_xmlValue = $temp[1].Trim()
            $tPmaxMem = Convert-ToMemSize $temp[1].Trim() $HvServer
            if ($tPmaxMem -le 0) {
                LogMsg "Unable to convert maxMem to int64."
                return $false
            }
            LogMsg "maxMem: $tPmaxMem"
        }
        elseif ($temp[0].Trim() -eq "startupMem") {
            $startupMem_xmlValue = $temp[1].Trim()
            $tPstartupMem = Convert-ToMemSize $temp[1].Trim() $HvServer
            if ($tPstartupMem -le 0) {
                LogErr " Unable to convert minMem to int64."
                return $false
            }
            LogMsg "startupMem: $tPstartupMem"
        }
        elseif ($temp[0].Trim() -eq "memWeight") {
            $tPmemWeight = [Convert]::ToInt32($temp[1].Trim())
            if ($tPmemWeight -lt 0 -or $tPmemWeight -gt 100) {
                LogErr "Memory weight needs to be between 0 and 100."
                return $false
            }
            LogMsg "memWeight: $tPmemWeight"
        }
        if ($VM_Number -eq 2) {
            $VMName = $vm2Name
        }
        elseif ($VM_Number -eq 3) {
            $VMName = $vm3Name
        }

        # check if we have all variables set
        if ( $VMName -and ($tpEnabled -eq $false -or $tpEnabled -eq $true) -and $tPstartupMem -and ([int64]$tPmemWeight -ge [int64]0) ) {
            # make sure VM is off
            if (Get-VM -Name $VMName -ComputerName $HvServer |  Where-Object { $_.State -like "Running" }) {
                LogMsg "Stopping VM $VMName"
                Stop-VM -Name $VMName -ComputerName $HvServer -force

                if (-not $?) {
                    LogErr "Unable to shut $VMName down (in order to set Memory parameters)"
                    return $false
                }
                # wait for VM to finish shutting down
                $timeout = 30
                while (Get-VM -Name $VMName -ComputerName $HvServer |  Where-Object { $_.State -notlike "Off" }) {
                    if ($timeout -le 0) {
                        "Error: Unable to shutdown $VMName"
                        return $false
                    }
                    Start-sleep -s 5
                    $timeout = $timeout - 5
                }
            }
            if ($bootLargeMem) {
                $osInfo = Get-WMIObject Win32_OperatingSystem -ComputerName $HvServer
                $freeMem = $OSInfo.FreePhysicalMemory * 1KB
                if ($tPstartupMem -le $freeMem) {
                    Set-VMMemory -vmName $VMName -ComputerName $HvServer -DynamicMemoryEnabled $false -StartupBytes $tPstartupMem
                }
                else {
                    LogErr "Error: Insufficient memory to run test. Skipping test."
                    return $false
                }
            }
            elseif ($tpEnabled) {
                if ($maxMem_xmlValue -eq $startupMem_xmlValue) {
                    $tPstartupMem = $tPmaxMem
                }
                Set-VMMemory -vmName $VMName -ComputerName $HvServer -DynamicMemoryEnabled $tpEnabled `
                    -MinimumBytes $tPminMem -MaximumBytes $tPmaxMem -StartupBytes $tPstartupMem `
                    -Priority $tPmemWeight
            }
            else {
                Set-VMMemory -vmName $VMName -ComputerName $HvServer -DynamicMemoryEnabled $tpEnabled `
                    -StartupBytes $tPstartupMem -Priority $tPmemWeight
            }
            if (-not $?) {
                "Error: Unable to set VM Memory for $VMName."
                "DM enabled: $tpEnabled"
                "min Mem: $tPminMem"
                "max Mem: $tPmaxMem"
                "startup Mem: $tPstartupMem"
                "weight Mem: $tPmemWeight"
                return $false
            }

            # check if mem is set correctly
            $vm_mem = (Get-VMMemory $VMName -ComputerName $HvServer).Startup
            if ( $vm_mem -eq $tPstartupMem ) {
                LogMsg "Set VM Startup Memory for $VMName to $tPstartupMem"
            }
            else {
                LogErr "Unable to set VM Startup Memory for $VMName to $tPstartupMem"
                return $false
            }

            # reset all variables
            $tpEnabled = $null
            [int64]$tPminMem = 0
            [int64]$tPmaxMem = 0
            [int64]$tPstartupMem = 0
            [int64]$tPmemWeight = -1
        }
    }
    return $true
}
Main -VMName $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Host.ServerName `
    -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
    -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory `
    -TestParams $TestParams