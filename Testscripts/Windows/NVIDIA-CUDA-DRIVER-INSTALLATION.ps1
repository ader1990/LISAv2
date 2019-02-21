# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Synopsis
    Install the nVidia CUDA drivers and validates GPU presence.

.Description
    This script performs the following operations:
    1. Istall CUDA drivers
    2. Reboot VM
    3. Check if the nVidia driver is loaded
    4. Compare number of expected GPU adapters with the actual count.
    5. The following tools are used for validation: lsvmbus, lspci, lshw and nvidia-smi

#>

param([object] $AllVmData,
      [object] $CurrentTestData,
      [object] $TestProvider
    )

function Main {
    param (
        [object] $AllVmData,
        [object] $CurrentTestData,
        [object] $TestProvider
    )
    # Create test result
    $currentTestResult = Create-TestResultObject
    $resultArr = @()
    $failureCount = 0
    $superuser="root"
    $testScript = "install_CUDA_drivers.sh"
    $driverLoaded = $null

    try {
        Provision-VMsForLisa -allVMData $allVMData -installPackagesOnRoleNames "none"
        Copy-RemoteFiles -uploadTo $allVMData.PublicIP -port $allVMData.SSHPort `
            -files $currentTestData.files -username $superuser -password $password -upload | Out-Null

        $linuxRelease = Detect-LinuxDistro -VIP $AllVMData.PublicIP -SSHport $AllVMData.SSHPort `
            -testVMUser $user -testVMPassword $password
        # For CentOS and RedHat the requirement is to install LIS RPMs
        if ($linuxRelease -eq "CENTOS" -or $linuxRelease -eq "REDHAT") {
            Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort -username $superuser `
                -password $password -command "wget -q https://aka.ms/lis -O - | tar -xz" -ignoreLinuxExitCode | Out-Null
            Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort -username $superuser `
                -password $password -command "cd LISISO && ./install.sh" | Out-Null
            if (-not $?) {
                Write-LogErr "Unable to install the LIS RPMs!"
                $resultArr += "ABORTED"
                break;
            }
        }

        # Restart VM to load the new LIS drivers
        if (-not $TestProvider.RestartAllDeployments($allVMData)) {
            Write-LogErr "Unable to connect to VM after restart!"
            $resultArr += "ABORTED"
            break;
        }

        # Start the test script
        Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort -username $superuser `
            -password $password -command "/$superuser/${testScript}" -runMaxAllowedTime 1800 | Out-Null
        if (-not $?) {
            Write-LogErr "Unable to install the CUDA drivers!"
            $resultArr += "ABORTED"
            break;
        }

        # Restart VM to load the driver and run validation
        if (-not $TestProvider.RestartAllDeployments($allVMData)) {
            Write-LogErr "Unable to connect to VM after restart!"
            $resultArr += "ABORTED"
            break;
        }

        # Mandatory to have the nvidia driver loaded after restart
        $driverLoaded = Run-LinuxCmd -username $user -password $password -ip $allVMData.PublicIP `
            -port $allVMData.SSHPort -command "lsmod | grep nvidia" -ignoreLinuxExitCode
        if ($null -eq $driverLoaded) {
            Write-LogErr "nVidia CUDA driver is not loaded after VM restart!"
            $resultArr += "FAIL"
            break;
        }

        # The expected ratio is 1 GPU adapter for every 6 CPU cores
        $vmCPUCount = Run-LinuxCmd -username $user -password $password -ip $allVMData.PublicIP `
            -port $allVMData.SSHPort -command "nproc" -ignoreLinuxExitCode
        [int]$expectedGPUCount = $($vmCPUCount/6)

        Write-LogInfo "Azure VM Size: $($allVMData.InstanceSize), expected GPU Adapters total: $expectedGPUCount"

        # region PCI Express pass-through in lsvmbus
        $PCIExpress = Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort `
            -username $superuser -password $password "lsvmbus" -ignoreLinuxExitCode
        Set-Content -Value $PCIExpress -Path $LogDir\PCI-Express-passthrough.txt -Force
        $pciExpressCount = (Select-String -Path $LogDir\PCI-Express-passthrough.txt -Pattern "PCI Express pass-through").Matches.Count
        if ($pciExpressCount -eq $expectedGPUCount) {
            $currentResult = "PASS"
        } else {
            $currentResult = "FAIL"
            $failureCount += 1
        }
        $metaData = "lsvmbus: Expected `"PCI Express pass-through`" count: $expectedGPUCount, count inside the VM: $pciExpressCount"
        $resultArr += $currentResult
        $CurrentTestResult.TestSummary += New-ResultSummary -testResult $currentResult -metaData $metaData `
            -checkValues "PASS,FAIL,ABORTED" -testName $CurrentTestData.testName
        #endregion

        #region lspci
        $lspci = Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort `
            -username $superuser -password $password "lspci" -ignoreLinuxExitCode
        Set-Content -Value $lspci -Path $LogDir\lspci.txt -Force
        $lspciCount = (Select-String -Path $LogDir\lspci.txt -Pattern "NVIDIA Corporation").Matches.Count
        if ($lspciCount -eq $expectedGPUCount) {
            $currentResult = "PASS"
        } else {
            $currentResult = "FAIL"
            $failureCount += 1
        }
        $metaData = "lspci: Expected `"3D controller: NVIDIA Corporation`" count: $expectedGPUCount, found inside the VM: $lspciCount"
        $resultArr += $currentResult
        $CurrentTestResult.TestSummary += New-ResultSummary -testResult $currentResult -metaData $metaData `
            -checkValues "PASS,FAIL,ABORTED" -testName $CurrentTestData.testName
        #endregion

        #region lshw -c video
        $lshw = Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort `
            -username $superuser -password $password "lshw -c video" -ignoreLinuxExitCode
        Set-Content -Value $lshw -Path $LogDir\lshw-c-video.txt -Force
        $lshwCount = (Select-String -Path $LogDir\lshw-c-video.txt -Pattern "vendor: NVIDIA Corporation").Matches.Count
        if ($lshwCount -eq $expectedGPUCount) {
            $currentResult = "PASS"
        } else {
            $currentResult = "FAIL"
            $failureCount += 1
        }
        $metaData = "lshw: Expected Display adapters: $expectedGPUCount, total adapters found in VM: $lshwCount"
        $resultArr += $currentResult
        $CurrentTestResult.TestSummary += New-ResultSummary -testResult $currentResult -metaData $metaData `
            -checkValues "PASS,FAIL,ABORTED" -testName $CurrentTestData.testName
        #endregion

        #region nvidia-smi
        $nvidiasmi = Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort `
            -username $superuser -password $password "nvidia-smi" -ignoreLinuxExitCode
        Set-Content -Value $nvidiasmi -Path $LogDir\nvidia-smi.txt -Force
        $nvidiasmiCount = (Select-String -Path $LogDir\nvidia-smi.txt -Pattern "Tesla").Matches.Count
        if ($nvidiasmiCount -eq $expectedGPUCount) {
            $currentResult = "PASS"
        } else {
            $currentResult = "FAIL"
            $failureCount += 1
        }
        $metaData = "nvidia-smi: Expected GPU count: $expectedGPUCount, found inside the VM: $nvidiasmiCount"
        $resultArr += $currentResult
        $CurrentTestResult.TestSummary += New-ResultSummary -testResult $currentResult -metaData $metaData `
            -checkValues "PASS,FAIL,ABORTED" -testName $CurrentTestData.testName
        #endregion

        # Get logs. An extra check for the previous $state is needed
        # The test could actually hang. If state.txt is showing
        # 'TestRunning' then abort the test
        #####
        # We first need to move copy from root folder to user folder for
        # Collect-TestLogs function to work
        Run-LinuxCmd -ip $allVMData.PublicIP -port $allVMData.SSHPort -username $superuser `
            -password $password -command "cp * /home/$user" -ignoreLinuxExitCode:$true
        $testResult = Collect-TestLogs -LogsDestination $LogDir -ScriptName `
            $currentTestData.files.Split('\')[3].Split('.')[0] -TestType "sh" -PublicIP `
            $allVMData.PublicIP -SSHPort $allVMData.SSHPort -Username $user `
            -password $password -TestName $currentTestData.testName

        if ($failureCount -eq 0) {
            $testResult = "PASS"
        } else {
            $testResult = "FAIL"
        }
        Write-LogInfo "Test Completed."
        Write-LogInfo "Test Result: $testResult"
    } catch {
        $ErrorMessage = $_.Exception.Message
        $ErrorLine = $_.InvocationInfo.ScriptLineNumber
        Write-LogInfo "EXCEPTION: $ErrorMessage at line: $ErrorLine"
    } finally {
        if (!$testResult) {
            $testResult = "ABORTED"
        }
        $resultArr += $testResult
    }

    $currentTestResult.TestResult = Get-FinalResultHeader -resultarr $resultArr
    return $currentTestResult
}

Main -AllVmData $AllVmData -CurrentTestData $CurrentTestData -TestProvider $TestProvider