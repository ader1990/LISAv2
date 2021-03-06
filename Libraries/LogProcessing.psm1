##############################################################################################
# LogProcessing.psm1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
	PS modules for LISAv2 test automation
	This module handles logging, test summary, and test reports.

.PARAMETER
	<Parameters>

.INPUTS


.NOTES
	Creation Date:
	Purpose/Change:

.EXAMPLE


#>
###############################################################################################

Function Write-Log()
{
	param
	(
		[ValidateSet('INFO','WARN','ERROR', IgnoreCase = $false)]
		[string]$logLevel,
		[string]$text
	)

	if ($password) {
		$text = $text.Replace($password,"******")
	}
	$now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss")
	$logType = $logLevel.PadRight(5, ' ')
	$finalMessage = "$now : [$logType] $text"
	$fgColor = "White"
	switch ($logLevel)
	{
		"INFO"	{$fgColor = "White"; continue}
		"WARN"	{$fgColor = "Yellow"; continue}
		"ERROR"	{$fgColor = "Red"; continue}
	}
	Write-Host $finalMessage -ForegroundColor $fgColor

	try
	{
		if ($LogDir) {
			if (!(Test-Path $LogDir)) {
				New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
			}
		} else {
			$LogDir = $env:TEMP
		}

		$LogFileFullPath = Join-Path $LogDir $LogFileName
		if (!(Test-Path $LogFileFullPath)) {
			New-Item -path $LogDir -name $LogFileName -type "file" | Out-Null
		}
		Add-Content -Value $finalMessage -Path $LogFileFullPath -Force
	}
	catch
	{
		Write-Output "[LOG FILE EXCEPTION] : $now : $text"
	}
}

Function Write-LogInfo($text)
{
	Write-Log "INFO" $text
}

Function Write-LogErr($text)
{
	Write-Log "ERROR" $text
}

Function Write-LogWarn($text)
{
	Write-Log "WARN" $text
}

Function New-ResultSummary($testResult, $checkValues, $testName, $metaData)
{
	if ( $metaData )
	{
		$resultString = "	$metaData : $testResult <br />"
	}
	else
	{
		$resultString = "	$testResult <br />"
	}
	return $resultString
}

Function Get-FinalResultHeader($resultArr){
	if(($resultArr -imatch "FAIL" ) -or ($resultArr -imatch "Aborted"))
	{
		$result = "FAIL"
		if($resultArr -imatch "Aborted")
		{
			$result = "Aborted"
		}
	}
	else
	{
		$result = "PASS"
	}
	return $result
}

<#
JUnit XML Report Schema:
	http://windyroad.com.au/dl/Open%20Source/JUnit.xsd
Example:
	$junitReport = [JUnitReportGenerator]::New($TestReportXml)
	$junitReport.StartLogTestSuite("LISAv2")

	$junitReport.StartLogTestCase("LISAv2", "BVT", "LISAv2.BVT")
	$junitReport.CompleteLogTestCase("LISAv2", "BVT", "PASS")

	$junitReport.StartLogTestCase("LISAv2", "NETWORK", "LISAv2.NETWORK")
	$junitReport.CompleteLogTestCase("LISAv2","NETWORK", "FAIL", "Stack trace: XXX")

	$junitReport.CompleteLogTestSuite("LISAv2")

	$junitReport.StartLogTestSuite("FCTesting")

	$junitReport.StartLogTestCase("FCTesting", "BVT", "FCTesting.BVT")
	$junitReport.CompleteLogTestCase("FCTesting", "BVT", "PASS")

	$junitReport.StartLogTestCase("FCTesting", "NEGATIVE", "FCTesting.NEGATIVE")
	$junitReport.CompleteLogTestCase("FCTesting", "NEGATIVE", "FAIL", "Stack trace: XXX")

	$junitReport.CompleteLogTestSuite("FCTesting")

	$junitReport.SaveLogReport()

report.xml:
	<testsuites>
	  <testsuite name="LISAv2" timestamp="2014-07-11T06:37:24" tests="3" failures="1" errors="1" time="0.04">
		<testcase name="BVT" classname="LISAv2.BVT" time="0" />
		<testcase name="NETWORK" classname="LISAv2.NETWORK" time="0">
		  <failure message="NETWORK fail">Stack trace: XXX</failure>
		</testcase>
		<testcase name="VNET" classname="LISAv2.VNET" time="0">
		  <error message="VNET error">Stack trace: XXX</error>
		</testcase>
	  </testsuite>
	  <testsuite name="FCTesting" timestamp="2014-07-11T06:37:24" tests="2" failures="1" errors="0" time="0.03">
		<testcase name="BVT" classname="FCTesting.BVT" time="0" />
		<testcase name="NEGATIVE" classname="FCTesting.NEGATIVE" time="0">
		  <failure message="NEGATIVE fail">Stack trace: XXX</failure>
		</testcase>
	  </testsuite>
	</testsuites>
#>

Class ReportNode
{
	[System.Xml.XmlElement] $XmlNode
	[System.Diagnostics.Stopwatch] $Timer

	ReportNode([object] $XmlNode)
	{
		$this.XmlNode = $XmlNode
		$this.Timer = [System.Diagnostics.Stopwatch]::startNew()
	}

	[string] StopTimer()
	{
		if ($null -eq $this.Timer)
		{
			return ""
		}
		$this.Timer.Stop()
		return [System.Math]::Round($this.Timer.Elapsed.TotalSeconds, 2).ToString()
	}

	[string] GetTimerElapasedTime([string] $Format="mm")
	{
		$num = 0
		if ($Format -eq "ss")
		{
			$num=$this.Timer.Elapsed.TotalSeconds
		}
		elseif ($Format -eq "hh")
		{
			$num=$this.Timer.Elapsed.TotalHours
		}
		elseif ($Format -eq "mm")
		{
			$num=$this.Timer.Elapsed.TotalMinutes
		}
		else
		{
			Write-LogErr "Invalid format for Get-TimerElapasedTime: $Format"
		}
		return [System.Math]::Round($num, 2).ToString()
	}
}

Class JUnitReportGenerator
{
	[string] $JunitReportPath
	[Xml] $JunitReport
	[System.Xml.XmlElement] $ReportRootNode
	[object] $TestSuiteLogTable
	[object] $TestSuiteCaseLogTable

	JUnitReportGenerator([string]$ReportPath)
	{
		$this.JunitReportPath = $ReportPath
		$this.JunitReport = New-Object System.Xml.XmlDocument
		$newElement = $this.JunitReport.CreateElement("testsuites")
		$this.ReportRootNode = $this.JunitReport.AppendChild($newElement)
		$this.TestSuiteLogTable = @{}
		$this.TestSuiteCaseLogTable = @{}
	}

	[void] SaveLogReport()
	{
		if ($null -ne $this.JunitReport) {
			$this.JunitReport.Save($this.JunitReportPath)
		}
	}

	[void] StartLogTestSuite([string]$testsuiteName)
	{
		if($null -eq $this.JunitReport -or $null -eq $testsuiteName -or $null -ne $this.TestSuiteLogTable[$testsuiteName])
		{
			return
		}

		$newElement = $this.JunitReport.CreateElement("testsuite")
		$newElement.SetAttribute("name", $testsuiteName)
		$newElement.SetAttribute("timestamp", [Datetime]::Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss"))
		$newElement.SetAttribute("tests", 0)
		$newElement.SetAttribute("failures", 0)
		$newElement.SetAttribute("errors", 0)
		$newElement.SetAttribute("time", 0)
		$testsuiteNode = $this.ReportRootNode.AppendChild($newElement)

		$testsuite = [ReportNode]::New($testsuiteNode)

		$this.TestSuiteLogTable[$testsuiteName] = $testsuite
	}

	[void] CompleteLogTestSuite([string]$testsuiteName)
	{
		if($null -eq $this.TestSuiteLogTable[$testsuiteName])
		{
			return
		}

		$this.TestSuiteLogTable[$testsuiteName].XmlNode.Attributes["time"].Value = $this.TestSuiteLogTable[$testsuiteName].StopTimer()
		$this.SaveLogReport()
		$this.TestSuiteLogTable[$testsuiteName] = $null
	}

	[void] StartLogTestCase([string]$testsuiteName, [string]$caseName, [string]$className)
	{
		if($null -eq $this.JunitReport -or $null -eq $testsuiteName -or $null -eq $this.TestSuiteLogTable[$testsuiteName] `
			-or $null -eq $caseName -or $null -ne $this.TestSuiteCaseLogTable["$testsuiteName$caseName"])
		{
			return
		}

		$newElement = $this.JunitReport.CreateElement("testcase")
		$newElement.SetAttribute("name", $caseName)
		$newElement.SetAttribute("classname", $classname)
		$newElement.SetAttribute("time", 0)

		$testcaseNode = $this.TestSuiteLogTable[$testsuiteName].XmlNode.AppendChild($newElement)

		$testcase = [ReportNode]::New($testcaseNode)
		$this.TestSuiteCaseLogTable["$testsuiteName$caseName"] = $testcase
	}

	[void] CompleteLogTestCase([string]$testsuiteName, [string]$caseName, [string]$result="PASS", [string]$detail="")
	{
		if($null -eq $this.JunitReport -or $null -eq $testsuiteName -or $null -eq $this.TestSuiteLogTable[$testsuiteName] `
			-or $null -eq $caseName -or $null -eq $this.TestSuiteCaseLogTable["$testsuiteName$caseName"])
		{
			return
		}
		$testCaseNode = $this.TestSuiteCaseLogTable["$testsuiteName$caseName"].XmlNode
		$testCaseNode.Attributes["time"].Value = $this.TestSuiteCaseLogTable["$testsuiteName$caseName"].StopTimer()

		$testSuiteNode = $this.TestSuiteLogTable[$testsuiteName].XmlNode
		[int]$testSuiteNode.Attributes["tests"].Value += 1
		if ($result -imatch "FAIL")
		{
			$newChildElement = $this.JunitReport.CreateElement("failure")
			$newChildElement.InnerText = $detail
			$newChildElement.SetAttribute("message", "$caseName failed.")
			$testCaseNode.AppendChild($newChildElement)

			[int]$testSuiteNode.Attributes["failures"].Value += 1
		}

		if ($result -imatch "ABORTED")
		{
			$newChildElement = $this.JunitReport.CreateElement("error")
			$newChildElement.InnerText = $detail
			$newChildElement.SetAttribute("message", "$caseName aborted.")
			$testCaseNode.AppendChild($newChildElement)

			[int]$testSuiteNode.Attributes["errors"].Value += 1
		}
		$this.SaveLogReport()
		$this.TestSuiteCaseLogTable["$testsuiteName$caseName"] = $null
	}

	[string] GetTestCaseElapsedTime([string]$TestSuiteName, [string]$CaseName, [string]$Format = "mm")
	{
		if($null -eq $this.JunitReport -or $null -eq $testsuiteName -or $null -eq $this.TestSuiteLogTable[$testsuiteName] `
			-or $null -eq $caseName -or $null -eq $this.TestSuiteCaseLogTable["$testsuiteName$caseName"])
		{
			Write-LogErr "Failed to get the elapsed time of test case $CaseName."
			return ""
		}
		return $this.TestSuiteCaseLogTable["$testsuiteName$caseName"].GetTimerElapasedTime($Format)
	}

	[string] GetTestSuiteElapsedTime([string]$TestSuiteName, [string]$Format = "mm")
	{
		if($null -eq $this.JunitReport -or $null -eq $testsuiteName -or $null -eq $this.TestSuiteLogTable[$testsuiteName])
		{
			Write-LogErr "Failed to get the elapsed time of test suite $TestSuiteName."
			return ""
		}
		return $this.TestSuiteLogTable[$testsuiteName].GetTimerElapasedTime($Format)
	}
}

Function Get-PlainTextSummary([object] $testCycle, [DateTime] $startTime, [System.TimeSpan] $testDuration, [string] $xmlFilename, $testSuiteResultDetails)
{
	$durationStr=$testDuration.Days.ToString() + ":" +  $testDuration.hours.ToString() + ":" + $testDuration.minutes.ToString()
	$str = "`r`n[LISAv2 Test Results Summary]`r`n"
	$str += "Test Run On           : " + $startTime
	if ( $BaseOsImage )
	{
		$str += "`r`nImage Under Test      : " + $BaseOsImage
	}
	if ( $BaseOSVHD )
	{
		$str += "`r`nVHD Under Test        : " + $BaseOSVHD
	}
	if ( $ARMImage )
	{
		$str += "`r`nARM Image Under Test  : " + "$($ARMImage.Publisher) : $($ARMImage.Offer) : $($ARMImage.Sku) : $($ARMImage.Version)"
	}
	$str += "`r`nTotal Test Cases      : " + $testSuiteResultDetails.totalTc + " (" + $testSuiteResultDetails.totalPassTc + " Pass, " + `
		$testSuiteResultDetails.totalFailTc + " Fail, " + $testSuiteResultDetails.totalAbortedTc + " Abort)"
	$str += "`r`nTotal Time (dd:hh:mm) : " + $durationStr
	$str += "`r`nXML File              : $xmlFilename`r`n`r`n"

	$str += $testCycle.textSummary.Replace("<br />", "`r`n")
	$str += "`r`n`r`nLogs can be found at $LogDir" + "`r`n`r`n"

	return $str
}

Function Get-HtmlTestSummary([object] $testCycle, [DateTime] $startTime, [System.TimeSpan] $testDuration, [string] $xmlFilename, $testSuiteResultDetails)
{
	$durationStr=$testDuration.Days.ToString() + ":" +  $testDuration.hours.ToString() + ":" + $testDuration.minutes.ToString()
	$strHtml =  "<STYLE>" +
		"BODY, TABLE, TD, TH, P {" +
		"  font-family:Verdana,Helvetica,sans serif;" +
		"  font-size:11px;" +
		"  color:black;" +
		"}" +
		"TD.bg1 { color:black; background-color:#99CCFF; font-size:180% }" +
		"TD.bg2 { color:black; font-size:130% }" +
		"TD.bg3 { color:black; font-size:110% }" +
		".TFtable{width:1024px; border-collapse:collapse; }" +
		".TFtable td{ padding:7px; border:#4e95f4 1px solid;}" +
		".TFtable tr{ background: #b8d1f3;}" +
		".TFtable tr:nth-child(odd){ background: #dbe1e9;}" +
		".TFtable tr:nth-child(even){background: #ffffff;}" +
		"</STYLE>" +
		"<table>" +
		"<TR><TD class=`"bg1`" colspan=`"2`"><B>Test Complete</B></TD></TR>" +
		"</table>" +
		"<BR/>"

	if ( $BaseOsImage ) {
		$strHtml += "<table>" +
		"<TR><TD class=`"bg2`" colspan=`"2`"><B>LISAv2 test run on - $startTime</B></TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">Build URL: <A href=`"${BUILD_URL}`">${BUILD_URL}</A></TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">Image under test - $BaseOsImage</TD></TR>" +
		"</table>" +
		"<BR/>"
	}
	if ( $BaseOSVHD ) {
		$tempDistro = $xmlConfig.config.$TestPlatform.Deployment.Data.Distro
		$rawVhd = $tempDistro.OsVHD.InnerText.Trim()
		$rawVhd = $rawVhd.split("?")[0]
		$strHtml += "<table>" +
		"<TR><TD class=`"bg2`" colspan=`"2`"><B>LISAv2  test run on - $startTime</B></TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">Build URL: <A href=`"`${BUILD_URL}`">`${BUILD_URL}</A></TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">VHD under test - $rawVhd</TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">Test category - $TestCategory</TD></TR>" +
		"</table>" +
		"<BR/>"
	}
	if ( $ARMImage ) {
		$strHtml += "<table>" +
		"<TR><TD class=`"bg2`" colspan=`"2`"><B>LISAv2  test run on - $startTime</B></TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">Build URL: <A href=`"`${BUILD_URL}`">`${BUILD_URL}</A></TD></TR>" +
		"<TR><TD class=`"bg3`" colspan=`"2`">ARM Image under test - $($ARMImage.Publisher) : $($ARMImage.Offer) : $($ARMImage.Sku) : $($ARMImage.Version)</TD></TR>" +
		"</table>" +
		"<BR/>"
	}

	$strHtml += "<table>"
	$strHtml += "<TR><TD class=`"bg3`" colspan=`"2`">Total Executed TestCases - $($testSuiteResultDetails.totalTc)</TD></TR>"
	$strHtml += "<TR><TD class=`"bg3`" colspan=`"2`">[&nbsp;<span><span style=`"color:#008000;`"><strong>$($testSuiteResultDetails.totalPassTc)</strong></span></span> - PASS, <span ><span style=`"color:#ff0000;`"><strong>$($testSuiteResultDetails.totalFailTc)</strong></span></span> - FAIL, <span><span style=`"color:#ff0000;`"><strong><span style=`"background-color:#ffff00;`">$($testSuiteResultDetails.totalAbortedTc)</span></strong></span></span> - ABORTED ]</TD></TR>"
	$strHtml += "<TR><TD class=`"bg3`" colspan=`"2`">Total Execution Time(dd:hh:mm) $durationStr</TD></TR>"
	$strHtml += "</table>"
	$strHtml += "<BR/>"

	# Add information about the host running ICA to the e-mail summary
	$strHtml += "<table border='0' class='TFtable'>"
	$strHtml += $testCycle.htmlSummary
	$strHtml += "</table></body></Html>"

	return $strHtml
}

Function Add-ReproVMDetailsToHtmlReport()
{
	$reproVMHtmlText += "<br><font size=`"2`"><em>Repro VMs: </em></font>"

	foreach ( $vm in $allVMData )
	{
		$reproVMHtmlText += "<br><font size=`"2`">ResourceGroup : $($vm.ResourceGroupName), IP : $($vm.PublicIP), SSH : $($vm.SSHPort)</font>"
	}
	return $reproVMHtmlText
}

Function Update-TestSummaryForCase ([string]$TestName, [int]$ExecutionCount, [string]$TestResult, [object]$TestCycle, [object]$ResultDetails, [string]$Duration, [string]$TestSummary, [bool]$AddHeader)
{
	if ( $AddHeader ) {
		$TestCycle.textSummary += "{0,5} {1,-50} {2,20} {3,20} `r`n" -f "ID", "TestCaseName", "TestResult", "TestDuration(in minutes)"
		$TestCycle.textSummary += "------------------------------------------------------------------------------------------------------`r`n"
	}
	$TestCycle.textSummary += "{0,5} {1,-50} {2,20} {3,20} `r`n" -f "$ExecutionCount", "$TestName", "$TestResult", "$Duration"
	if ( $TestSummary ) {
		$TestCycle.textSummary += "$TestSummary"
	}

	$ResultDetails.totalTc += 1
	if ( $TestResult -imatch "PASS" ) {
		$ResultDetails.totalPassTc += 1
		$testResultRow = "<span style='color:green;font-weight:bolder'>PASS</span>"
		$TestCycle.htmlSummary += "<tr><td>$ExecutionCount</td><td>$TestName</td><td>$Duration min</td><td>$testResultRow</td></tr>"
	}
	elseif ( $TestResult -imatch "FAIL" ) {
		$ResultDetails.totalFailTc += 1
		$testResultRow = "<span style='color:red;font-weight:bolder'>FAIL</span>"
		$TestCycle.htmlSummary += "<tr><td>$ExecutionCount</td><td>$TestName$(Add-ReproVMDetailsToHtmlReport)</td><td>$Duration min</td><td>$testResultRow</td></tr>"
	}
	elseif ( $TestResult -imatch "ABORTED" ) {
		$ResultDetails.totalAbortedTc += 1
		$testResultRow = "<span style='background-color:yellow;font-weight:bolder'>ABORT</span>"
		$TestCycle.htmlSummary += "<tr><td>$ExecutionCount</td><td>$TestName$(Add-ReproVMDetailsToHtmlReport)</td><td>$Duration min</td><td>$testResultRow</td></tr>"
	}
	else {
		Write-LogErr "Test Result is empty."
		$ResultDetails.totalAbortedTc += 1
		$testResultRow = "<span style='background-color:yellow;font-weight:bolder'>ABORT</span>"
		$TestCycle.htmlSummary += "<tr><td>$ExecutionCount</td><td>$TestName$(Add-ReproVMDetailsToHtmlReport)</td><td>$Duration min</td><td>$testResultRow</td></tr>"
	}

	Write-LogInfo "CURRENT - PASS    - $($ResultDetails.totalPassTc)"
	Write-LogInfo "CURRENT - FAIL    - $($ResultDetails.totalFailTc)"
	Write-LogInfo "CURRENT - ABORTED - $($ResultDetails.totalAbortedTc)"
}