# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

param([String] $TestParams)

$SETUP_SCRIPT = ".\TestScripts\Windows\AddHardDisk.ps1"
$TEST_SCRIPT = "STOR-Lis-Disk.sh"

function Main {
    param (
        $VMname,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir,
        $TestParams
    )

    $testName = $currentTestData.testName
    $params = ConvertFrom-StringData -StringData $TestParams.replace(";", "`n")

    Run-SetupScript -Script $SETUP_SCRIPT -Parameters $params

    Run-LinuxCmd -Command "echo '${VMPassword}' | sudo -S -s eval `"export HOME=``pwd``;bash ${TEST_SCRIPT} > ${testName}_summary.log 2>&1`"" `
        -Username $VMUserName -password $VMPassword -ip $Ipv4 -Port $VMPort `

    $testResult = Collect-TestLogs -LogsDestination $LogDir -ScriptName "STOR-Lis-Disk" -TestType "sh" `
        -PublicIP $Ipv4 -SSHPort $VMPort -Username $VMUserName -password $VMPassword `
        -TestName $currentTestData.testName

    return $testResult
}

Main -VMname $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
    -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
    -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory `
    -TestParams $TestParams
