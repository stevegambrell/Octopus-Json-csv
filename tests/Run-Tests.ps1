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
        [string]$Name,
        [string]$Project
    )

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("octopus-json-csv-" + [Guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $inputPath = Join-Path $temp "$Name.json"
        $outputPath = Join-Path $temp "$Name.csv"
        [System.IO.File]::WriteAllText($inputPath, $Json)
        if ($Project) {
            & $converter -InputPath $inputPath -OutputPath $outputPath -Project $Project | Out-Null
        }
        else {
            & $converter -InputPath $inputPath -OutputPath $outputPath | Out-Null
        }
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
        [object[]]$Rows,
        [string]$Project
    )

    $headers = @(
        'TemplateName', 'Label', 'HelpText', 'ControlType', 'Type',
        'DefaultValue', 'Project', 'Variable', 'Exclude'
    )
    $expectedLines = [System.Collections.Generic.List[string]]::new()
    [void]$expectedLines.Add((($headers | ForEach-Object { ConvertTo-QuotedCsvField $_ }) -join ','))
    foreach ($row in $Rows) {
        [void]$expectedLines.Add(((@($row) | ForEach-Object { ConvertTo-QuotedCsvField $_ }) -join ','))
    }
    $expected = ($expectedLines -join "`n") + "`n"
    $actual = (Invoke-Converter -Json $Json -Name $Name -Project $Project) -replace "`r`n", "`n"

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

Assert-CsvEqual -Name 'mno-serilog-template' -Json @'
{
  "MNOMediationService": {
    "AppSettings": {
      "Serilog": {
        "MinimumLevel": "Information",
        "WriteTo": {
          "Args": {
            // Serilog File Location
            // Location of Logfiles
            "path": "C:\\Digitalk\\Logs\\MNO Mediation Service\\logfile-.txt",
            "retainedFileCountLimit": 365
          }
        }
      }
    }
  }
}
'@ -Rows @(
    , @(
        'MNOMediationService.AppSettings.Serilog.MinimumLevel'
        'Serilog Minimum Level'
        ''
        'SingleLineText'
        'string'
        'Information'
        'MNO Mediation Service'
        'AppSettings:Serilog:MinimumLevel'
        'FALSE'
    )
    , @(
        'MNOMediationService.AppSettings.Serilog.WriteTo.Args.path'
        'Serilog File Location'
        'Location of Logfiles'
        'SingleLineText'
        'string'
        'C:\Digitalk\Logs\MNO Mediation Service\logfile-.txt'
        'MNO Mediation Service'
        'AppSettings:Serilog:WriteTo:Args:path'
        'FALSE'
    )
    , @(
        'MNOMediationService.AppSettings.Serilog.WriteTo.Args.retainedFileCountLimit'
        'Retained File Limit'
        ''
        'SingleLineText'
        'string'
        '365'
        'MNO Mediation Service'
        'AppSettings:Serilog:WriteTo:Args:retainedFileCountLimit'
        'FALSE'
    )
)

Assert-CsvEqual -Name 'project-parameter' -Json @'
{
  "AppSettings": {
    "Serilog": {
      "MinimumLevel": "Information"
    }
  }
}
'@ -Project 'MNO Mediation Service' -Rows @(
    , @(
        'MNOMediationService.AppSettings.Serilog.MinimumLevel'
        'Serilog Minimum Level'
        ''
        'SingleLineText'
        'string'
        'Information'
        'MNO Mediation Service'
        'AppSettings:Serilog:MinimumLevel'
        'FALSE'
    )
)

Assert-CsvEqual -Name 'jsonc-ignores-setup-comments' -Json @'
{
  "PaymentSettings": {
    "PaymentGateways": {
      // 1) In index.html uncomment the lightbox script
      // Set apiBaseUrl to https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp
      "Worldpay": {
        "Enabled": false,
        "ApiBaseUrl": "https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp"
      }
    }
  }
}
'@ -Rows @(
    , @(
        'PaymentSettings.PaymentGateways.Worldpay.Enabled'
        'Worldpay Enabled'
        ''
        'SingleLineText'
        'string'
        'False'
        'Payment Settings'
        'PaymentGateways:Worldpay:Enabled'
        'FALSE'
    )
    , @(
        'PaymentSettings.PaymentGateways.Worldpay.ApiBaseUrl'
        'Api Base Url'
        ''
        'SingleLineText'
        'string'
        'https://secure-test.worldpay.com/jsp/merchant/xml/paymentService.jsp'
        'Payment Settings'
        'PaymentGateways:Worldpay:ApiBaseUrl'
        'FALSE'
    )
)

$missingInput = Join-Path ([System.IO.Path]::GetTempPath()) 'missing-octopus.json'
$missingOutput = Join-Path ([System.IO.Path]::GetTempPath()) 'missing-octopus.csv'
Assert-Throws -Name 'missing-input' -Script {
    & $converter -InputPath $missingInput -OutputPath $missingOutput
}

$sample = Join-Path $root 'samples/mno-mediation-appsettings.json'
$sampleOut = Join-Path ([System.IO.Path]::GetTempPath()) ("octopus-sample-" + [Guid]::NewGuid().ToString('n') + '.csv')
try {
    & $converter -InputPath $sample -OutputPath $sampleOut | Out-Null
    $sampleCsv = [System.IO.File]::ReadAllText($sampleOut) -replace "`r`n", "`n"
    $lines = $sampleCsv.TrimEnd("`n").Split("`n")
    if (
        $lines.Count -eq 4 -and
        $lines[0].StartsWith('"TemplateName","Label","HelpText"') -and
        $lines[1].Contains('"Serilog Minimum Level"') -and
        $lines[2].Contains('"Serilog File Location"') -and
        $lines[2].Contains('"Location of Logfiles"') -and
        $lines[3].Contains('"Retained File Limit"')
    ) {
        Write-Host 'PASS sample-mno-file'
        $passed++
    }
    else {
        Write-Host 'FAIL sample-mno-file'
        Write-Host $sampleCsv
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
