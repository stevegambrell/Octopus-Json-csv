<#
.SYNOPSIS
    Converts Octopus JSON (or any JSON object list) to a quoted CSV file.

.DESCRIPTION
    Reads a JSON file and writes a CSV to the supplied output path. Every field
    is comma-separated and wrapped in double quotes. Embedded quotes are escaped
    by doubling them.

    Record lists are taken from common Octopus shapes:
      - a JSON array of objects
      - an Octopus API collection with an Items array
      - reporting-style { "Deployments": { "Deployment": [ ... ] } }
      - a single object (one CSV row)

    Nested objects are flattened with dot-separated column names. Arrays of
    scalars are joined with "; ". Arrays of objects are stored as compact JSON.
    Octopus HAL "Links" properties are omitted.

    JSON with comments is accepted: // line comments, /* block comments */, and
    trailing commas are removed before parsing. Text inside strings is left
    unchanged, so URLs such as https://example.com stay intact.

.PARAMETER InputPath
    Source JSON file.

.PARAMETER OutputPath
    Destination CSV file path.

.EXAMPLE
    .\Convert-OctopusJsonToCsv.ps1 '.\deployments.json' 'D:\Octopus-Deployments.csv'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-QuotedCsvField {
    param($Value)

    if ($null -eq $Value -or [DBNull]::Value.Equals($Value)) {
        return '""'
    }

    $text = if ($Value -is [datetime]) {
        $Value.ToString('yyyy-MM-dd HH:mm:ss')
    }
    elseif ($Value -is [bool]) {
        if ($Value) { 'True' } else { 'False' }
    }
    else {
        [string]$Value
    }

    return '"' + ($text.Replace('"', '""')) + '"'
}

function Test-JsonMap {
    param($Value)

    return $null -ne $Value -and (
        $Value -is [System.Management.Automation.PSCustomObject] -or
        $Value -is [System.Collections.IDictionary]
    )
}

function Test-JsonList {
    param($Value)

    if ($null -eq $Value -or $Value -is [string] -or (Test-JsonMap $Value)) {
        return $false
    }

    return $Value -is [System.Collections.IEnumerable]
}

function Get-JsonPropertyNames {
    param($Object)

    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys)
    }

    return @($Object.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object { $_.Name })
}

function Get-JsonProperty {
    param(
        $Object,
        [string]$Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return , $Object[$Name]
        }
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return , $property.Value
}

function ConvertTo-StrictJson {
    param([string]$JsonText)

    $chars = $JsonText.ToCharArray()
    $length = $chars.Length
    $builder = New-Object System.Text.StringBuilder $length
    $inString = $false
    $escape = $false
    $i = 0

    while ($i -lt $length) {
        $c = $chars[$i]

        if ($inString) {
            [void]$builder.Append($c)
            if ($escape) {
                $escape = $false
            }
            elseif ($c -eq [char]0x5C) {
                $escape = $true
            }
            elseif ($c -eq [char]0x22) {
                $inString = $false
            }
            $i++
            continue
        }

        if ($c -eq [char]0x22) {
            $inString = $true
            [void]$builder.Append($c)
            $i++
            continue
        }

        $next = if (($i + 1) -lt $length) { $chars[$i + 1] } else { [char]0 }

        if ($c -eq [char]0x2F -and $next -eq [char]0x2F) {
            $i += 2
            while ($i -lt $length -and $chars[$i] -ne [char]0x0A -and $chars[$i] -ne [char]0x0D) {
                $i++
            }
            continue
        }

        if ($c -eq [char]0x2F -and $next -eq [char]0x2A) {
            $i += 2
            while ($i -lt $length) {
                if (($i + 1) -lt $length -and $chars[$i] -eq [char]0x2A -and $chars[$i + 1] -eq [char]0x2F) {
                    $i += 2
                    break
                }
                $i++
            }
            continue
        }

        if ($c -eq [char]0x2C) {
            $j = $i + 1
            $isTrailing = $false
            while ($j -lt $length) {
                $n = $chars[$j]
                $n2 = if (($j + 1) -lt $length) { $chars[$j + 1] } else { [char]0 }

                if ($n -eq [char]0x20 -or $n -eq [char]0x09 -or $n -eq [char]0x0A -or $n -eq [char]0x0D) {
                    $j++
                    continue
                }

                if ($n -eq [char]0x2F -and $n2 -eq [char]0x2F) {
                    $j += 2
                    while ($j -lt $length -and $chars[$j] -ne [char]0x0A -and $chars[$j] -ne [char]0x0D) {
                        $j++
                    }
                    continue
                }

                if ($n -eq [char]0x2F -and $n2 -eq [char]0x2A) {
                    $j += 2
                    while ($j -lt $length) {
                        if (($j + 1) -lt $length -and $chars[$j] -eq [char]0x2A -and $chars[$j + 1] -eq [char]0x2F) {
                            $j += 2
                            break
                        }
                        $j++
                    }
                    continue
                }

                if ($n -eq [char]0x7D -or $n -eq [char]0x5D) {
                    $isTrailing = $true
                }
                break
            }

            if ($isTrailing) {
                $i++
                continue
            }
        }

        [void]$builder.Append($c)
        $i++
    }

    return $builder.ToString()
}

function ConvertFrom-JsonDocument {
    param([string]$JsonText)

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw 'JSON file is empty.'
    }

    $strictJson = ConvertTo-StrictJson -JsonText $JsonText
    if ([string]::IsNullOrWhiteSpace($strictJson)) {
        throw 'JSON file is empty after removing comments.'
    }

    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            return , ($strictJson | ConvertFrom-Json -Depth 100 -NoEnumerate)
        }
        return , ($strictJson | ConvertFrom-Json)
    }
    catch {
        $parseError = $_
        try {
            Add-Type -AssemblyName System.Web.Extensions | Out-Null
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $serializer.MaxJsonLength = [int]::MaxValue
            $serializer.RecursionLimit = 100
            return , $serializer.DeserializeObject($strictJson)
        }
        catch {
            throw "Could not parse JSON. // and /* comments and trailing commas are stripped, but the file is still invalid. $($parseError.Exception.Message)"
        }
    }
}

function ConvertTo-RecordArray {
    param($Value)

    if ($null -eq $Value) {
        return , @()
    }

    if (Test-JsonList $Value) {
        return , @($Value)
    }

    return , @($Value)
}

function Get-JsonRecords {
    param($Document)

    if (Test-JsonList $Document) {
        return , (ConvertTo-RecordArray $Document)
    }

    if (-not (Test-JsonMap $Document)) {
        throw 'JSON root must be an object or an array.'
    }

    $items = Get-JsonProperty $Document 'Items'
    if ($null -ne $items -and ((Test-JsonList $items) -or (Test-JsonMap $items))) {
        return , (ConvertTo-RecordArray $items)
    }

    $deployments = Get-JsonProperty $Document 'Deployments'
    if ($null -ne $deployments) {
        if (Test-JsonMap $deployments) {
            $deploymentRows = Get-JsonProperty $deployments 'Deployment'
            if ($null -ne $deploymentRows) {
                return , (ConvertTo-RecordArray $deploymentRows)
            }
        }
        return , (ConvertTo-RecordArray $deployments)
    }

    foreach ($name in @('Results', 'data', 'value', 'records', 'Deployment')) {
        $candidate = Get-JsonProperty $Document $name
        if (Test-JsonList $candidate) {
            return , (ConvertTo-RecordArray $candidate)
        }
        if ((Test-JsonMap $candidate) -and $name -eq 'Deployment') {
            return , @($candidate)
        }
    }

    return , @($Document)
}

function ConvertTo-FlatRow {
    param($Record)

    $row = [ordered]@{}

    function Add-FlatValue {
        param(
            [string]$Key,
            $Value
        )

        if ($null -eq $Value -or [DBNull]::Value.Equals($Value)) {
            $row[$Key] = ''
            return
        }

        if (Test-JsonMap $Value) {
            $names = @(Get-JsonPropertyNames $Value)
            if ($names.Count -eq 0) {
                $row[$Key] = ''
                return
            }

            foreach ($name in $names) {
                if ($name -eq 'Links') {
                    continue
                }
                $childKey = if ($Key) { "$Key.$name" } else { [string]$name }
                Add-FlatValue -Key $childKey -Value (Get-JsonProperty $Value $name)
            }
            return
        }

        if (Test-JsonList $Value) {
            $items = @($Value)
            if ($items.Count -eq 0) {
                $row[$Key] = ''
                return
            }

            $containsMap = $false
            foreach ($item in $items) {
                if (Test-JsonMap $item) {
                    $containsMap = $true
                    break
                }
            }

            if ($containsMap) {
                $row[$Key] = (ConvertTo-Json -InputObject @($items) -Compress -Depth 100)
            }
            else {
                $row[$Key] = ($items | ForEach-Object {
                        if ($null -eq $_) { '' } else { [string]$_ }
                    }) -join '; '
            }
            return
        }

        if ($Value -is [datetime]) {
            $row[$Key] = $Value.ToString('yyyy-MM-dd HH:mm:ss')
            return
        }

        if ($Value -is [bool]) {
            $row[$Key] = if ($Value) { 'True' } else { 'False' }
            return
        }

        $row[$Key] = [string]$Value
    }

    if (Test-JsonMap $Record) {
        Add-FlatValue -Key '' -Value $Record
    }
    else {
        $row['Value'] = if ($null -eq $Record) { '' } else { [string]$Record }
    }

    return $row
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "JSON file not found: $InputPath"
}

$jsonText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $InputPath))
$document = ConvertFrom-JsonDocument -JsonText $jsonText
$records = Get-JsonRecords -Document $document
$rows = foreach ($record in @($records)) {
    ConvertTo-FlatRow -Record $record
}

$headers = [System.Collections.Generic.List[string]]::new()
$headerSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($row in $rows) {
    foreach ($key in $row.Keys) {
        if ($headerSet.Add($key)) {
            [void]$headers.Add($key)
        }
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$writer = New-Object System.IO.StreamWriter ($OutputPath, $false, $utf8NoBom)
try {
    if ($headers.Count -gt 0) {
        $writer.WriteLine((($headers | ForEach-Object { ConvertTo-QuotedCsvField $_ }) -join ','))
    }

    $rowCount = 0
    foreach ($row in $rows) {
        $fields = foreach ($header in $headers) {
            if ($row.Contains($header)) {
                ConvertTo-QuotedCsvField $row[$header]
            }
            else {
                ConvertTo-QuotedCsvField ''
            }
        }
        $writer.WriteLine(($fields -join ','))
        $rowCount++
    }
}
finally {
    $writer.Dispose()
}

Write-Host "Wrote $rowCount row(s) to $OutputPath"
