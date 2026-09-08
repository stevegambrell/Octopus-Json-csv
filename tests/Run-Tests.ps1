# Runs conversion fixtures against Convert-OctopusJsonToCsv.ps1.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$converter = Join-Path $root 'Convert-OctopusJsonToCsv.ps1'
$failed = 0
$passed = 0

function ConvertTo-QuotedCsvField {
    param($Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + ([string]$Value).Replace('"', '""') + '"'
}

function Invoke-Converter {
    param(
        [string]$Json,
        [string]$Name
    )

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("octopus-json-csv-" + [Guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $inputPath = Join-Path $temp "$Name.json"
        $outputPath = Join-Path $temp "$Name.csv"
        [System.IO.File]::WriteAllText($inputPath, $Json)
        & $converter -InputPath $inputPath -OutputPath $outputPath | Out-Null
        return [System.IO.File]::ReadAllText($outputPath)
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}

function Assert-CsvEqual {
    param(
        [string]$Name,
        [string]$Json,
        [string[]]$Headers,
        [object[]]$Rows
    )

    $expectedLines = [System.Collections.Generic.List[string]]::new()
    [void]$expectedLines.Add((($Headers | ForEach-Object { ConvertTo-QuotedCsvField $_ }) -join ','))
    foreach ($row in $Rows) {
        [void]$expectedLines.Add(((@($row) | ForEach-Object { ConvertTo-QuotedCsvField $_ }) -join ','))
    }
    $expected = ($expectedLines -join "`n") + "`n"
    $actual = (Invoke-Converter -Json $Json -Name $Name) -replace "`r`n", "`n"

    if ($actual -eq $expected) {
        Write-Host "PASS $Name"
        $script:passed++
        return
    }

    Write-Host "FAIL $Name"
    Write-Host "  expected:"
    Write-Host $expected
    Write-Host "  actual:"
    Write-Host $actual
    $script:failed++
}

function Assert-Throws {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    try {
        & $Script
        Write-Host "FAIL $Name (expected an error)"
        $script:failed++
    }
    catch {
        Write-Host "PASS $Name"
        $script:passed++
    }
}

Assert-CsvEqual -Name 'reporting-feed' -Json @'
{
  "Deployments": {
    "Deployment": [
      {
        "DeploymentId": "Deployments-1",
        "DeploymentName": "Deploy to Dev",
        "ProjectName": "Web App",
        "EnvironmentName": "Dev",
        "DurationSeconds": "24"
      },
      {
        "DeploymentId": "Deployments-2",
        "DeploymentName": "Deploy to Production",
        "ProjectName": "Web App",
        "EnvironmentName": "Production",
        "DurationSeconds": "18"
      }
    ]
  }
}
'@ -Headers @('DeploymentId', 'DeploymentName', 'ProjectName', 'EnvironmentName', 'DurationSeconds') -Rows @(
    , @('Deployments-1', 'Deploy to Dev', 'Web App', 'Dev', '24')
    , @('Deployments-2', 'Deploy to Production', 'Web App', 'Production', '18')
)

Assert-CsvEqual -Name 'single-deployment-object' -Json @'
{
  "Deployments": {
    "Deployment": {
      "DeploymentId": "Deployments-1",
      "ProjectName": "Web App"
    }
  }
}
'@ -Headers @('DeploymentId', 'ProjectName') -Rows @(
    , @('Deployments-1', 'Web App')
)

Assert-CsvEqual -Name 'api-items' -Json @'
{
  "ItemType": "Deployment",
  "Items": [
    {
      "Id": "Deployments-4992",
      "Name": "Deploy to Production",
      "ForcePackageDownload": false,
      "UseGuidedFailure": true,
      "Comments": null,
      "SpecificMachineIds": ["Machines-1", "Machines-2"],
      "SkipActions": [],
      "Links": {
        "Self": "/api/deployments/Deployments-4992"
      }
    }
  ]
}
'@ -Headers @('Id', 'Name', 'ForcePackageDownload', 'UseGuidedFailure', 'Comments', 'SpecificMachineIds', 'SkipActions') -Rows @(
    , @('Deployments-4992', 'Deploy to Production', 'False', 'True', '', 'Machines-1; Machines-2', '')
)

Assert-CsvEqual -Name 'nested-and-quotes' -Json @'
[
  {
    "Project": { "Name": "Web, App", "Group": { "Name": "Orchestration" } },
    "Note": "Said \"go\""
  }
]
'@ -Headers @('Project.Name', 'Project.Group.Name', 'Note') -Rows @(
    , @('Web, App', 'Orchestration', 'Said "go"')
)

Assert-CsvEqual -Name 'union-headers' -Json @'
[
  { "Id": "1", "Name": "A" },
  { "Id": "2", "Environment": "Prod" }
]
'@ -Headers @('Id', 'Name', 'Environment') -Rows @(
    , @('1', 'A', '')
    , @('2', '', 'Prod')
)

Assert-CsvEqual -Name 'jsonc-comments-and-urls' -Json @'
{
  "PaymentSettings": {
    "PaymentGateways": {
      // sandbox URL https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp
      "Worldpay": {
        "Enabled": false,
        "ApiBaseUrl": "https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp",
        //"ApiBaseUrl": "https://localhost:56581/api/WorldpayPayment/TestInitiateTransaction",
        "PaymentMethods": {
          /* The CardType must match the type column */
          "VIS": {
            "CardType": "Visa",
            "IsPaymentMethod": true,
          }
        }
      }
    }
  }
}
'@ -Headers @(
    'PaymentSettings.PaymentGateways.Worldpay.Enabled'
    'PaymentSettings.PaymentGateways.Worldpay.ApiBaseUrl'
    'PaymentSettings.PaymentGateways.Worldpay.PaymentMethods.VIS.CardType'
    'PaymentSettings.PaymentGateways.Worldpay.PaymentMethods.VIS.IsPaymentMethod'
) -Rows @(
    , @('False', 'https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp', 'Visa', 'True')
)

Assert-CsvEqual -Name 'object-array-cell' -Json @'
[
  {
    "Id": "1",
    "Packages": [
      { "Name": "Acme.Web", "Version": "1.0.0" }
    ]
  }
]
'@ -Headers @('Id', 'Packages') -Rows @(
    , @('1', '[{"Name":"Acme.Web","Version":"1.0.0"}]')
)

$missingInput = Join-Path ([System.IO.Path]::GetTempPath()) 'missing-octopus.json'
$missingOutput = Join-Path ([System.IO.Path]::GetTempPath()) 'missing-octopus.csv'
Assert-Throws -Name 'missing-input' -Script {
    & $converter -InputPath $missingInput -OutputPath $missingOutput
}

$sampleReporting = Join-Path $root 'samples/octopus-reporting-deployments.json'
$sampleApi = Join-Path $root 'samples/octopus-api-deployments.json'
$sampleOut = Join-Path ([System.IO.Path]::GetTempPath()) ("octopus-sample-" + [Guid]::NewGuid().ToString('n') + '.csv')
try {
    & $converter -InputPath $sampleReporting -OutputPath $sampleOut | Out-Null
    $sampleCsv = [System.IO.File]::ReadAllText($sampleOut) -replace "`r`n", "`n"
    $sampleLines = $sampleCsv.TrimEnd("`n").Split("`n")
    if (
        $sampleLines.Count -eq 3 -and
        $sampleLines[0].StartsWith('"DeploymentId","DeploymentName","ProjectId"') -and
        $sampleLines[2].Contains('"Acme, ""West"""')
    ) {
        Write-Host 'PASS sample-reporting-file'
        $passed++
    }
    else {
        Write-Host 'FAIL sample-reporting-file'
        Write-Host $sampleCsv
        $failed++
    }

    & $converter -InputPath $sampleApi -OutputPath $sampleOut | Out-Null
    $apiCsv = [System.IO.File]::ReadAllText($sampleOut) -replace "`r`n", "`n"
    if (
        $apiCsv.Contains('"Id","Name"') -and
        -not $apiCsv.Contains('Links') -and
        $apiCsv.Contains('Machines-1; Machines-2') -and
        -not $apiCsv.Contains('"ItemType"')
    ) {
        Write-Host 'PASS sample-api-file'
        $passed++
    }
    else {
        Write-Host 'FAIL sample-api-file'
        Write-Host $apiCsv
        $failed++
    }

    $sampleJsonc = Join-Path $root 'samples/paymentsettings-comments.json'
    & $converter -InputPath $sampleJsonc -OutputPath $sampleOut | Out-Null
    $jsoncCsv = [System.IO.File]::ReadAllText($sampleOut) -replace "`r`n", "`n"
    if (
        $jsoncCsv.Contains('PaymentSettings.PaymentGateways.Worldpay.ApiBaseUrl') -and
        $jsoncCsv.Contains('https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp') -and
        -not $jsoncCsv.Contains('localhost:56581')
    ) {
        Write-Host 'PASS sample-jsonc-file'
        $passed++
    }
    else {
        Write-Host 'FAIL sample-jsonc-file'
        Write-Host $jsoncCsv
        $failed++
    }
}
finally {
    if (Test-Path -LiteralPath $sampleOut) {
        Remove-Item -LiteralPath $sampleOut -Force
    }
}

Write-Host ""
Write-Host "Passed: $passed  Failed: $failed"
if ($failed -gt 0) {
    exit 1
}
