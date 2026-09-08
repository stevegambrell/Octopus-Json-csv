<#
.SYNOPSIS
    Converts nested JSON settings into an Octopus variable-template CSV.

.DESCRIPTION
    Reads a JSON file (comments allowed) and writes one CSV row per leaf
    setting, matching the XML-to-CSV template layout:

        TemplateName, Label, HelpText, ControlType, Type, DefaultValue,
        Project, Variable, Exclude

    TemplateName is Prefix plus the dotted JSON path. Variable is the JSON
    path with colons. Project and Prefix are always supplied by the caller.

    Every field is comma-separated and wrapped in double quotes. Embedded
    quotes are escaped by doubling them.

.PARAMETER InputPath
    Source JSON file.

.PARAMETER OutputPath
    Destination CSV file path.

.PARAMETER Project
    Project display name written to the Project column.

.PARAMETER Prefix
    Prefix prepended to TemplateName (for example MyService).

.EXAMPLE
    .\Convert-OctopusJsonToCsv.ps1 '.\appsettings.json' '.\appsettings.csv' -Project 'My Service' -Prefix 'MyService'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$Project,

    [Parameter(Mandatory = $true, Position = 3)]
    [string]$Prefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CsvHeaders = @(
    'TemplateName'
    'Label'
    'HelpText'
    'ControlType'
    'Type'
    'DefaultValue'
    'Project'
    'Variable'
    'Exclude'
)

$script:CollapsedSections = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('PaymentMethods', 'CountryMappings', 'ISOSupportedLanguages') | ForEach-Object {
    [void]$script:CollapsedSections.Add($_)
}

$script:SkipLabelParents = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('Args', 'WriteTo', 'AppSettings', 'PaymentGateways', 'PaymentMethods', 'CountryMappings', 'ISOSupportedLanguages', 'Items', 'Properties', 'Links') | ForEach-Object {
    [void]$script:SkipLabelParents.Add($_)
}

$script:LabelAliases = @{
    path                     = 'File Location'
    retainedFileCountLimit   = 'Retained File Limit'
}

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

function Test-UsableComment {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $trimmed = $Text.Trim()
    if ($trimmed.Length -gt 80) {
        return $false
    }
    if ($trimmed -match '://') {
        return $false
    }
    if ($trimmed -match '^\d+\)') {
        return $false
    }
    if ($trimmed -match '^(Set |Note that|The |To allow|These steps|Click |Login |Testing |XML |JSON |IP |Production )') {
        return $false
    }

    return $true
}

function Get-JsoncCommentMap {
    param([string]$JsonText)

    $map = @{}
    $chars = $JsonText.ToCharArray()
    $length = $chars.Length
    $inString = $false
    $escape = $false
    $i = 0
    $stack = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.List[string]
    $currentKey = $null
    $afterColon = $false

    function Add-PendingComment {
        param([string]$Raw)

        if (Test-UsableComment $Raw) {
            [void]$pending.Add($Raw.Trim())
        }
        else {
            $pending.Clear()
        }
    }

    function Save-PendingComments {
        param([string]$PathKey)

        if ($pending.Count -eq 0 -or [string]::IsNullOrWhiteSpace($PathKey)) {
            $pending.Clear()
            return
        }

        $label = $null
        $help = $null
        if ($pending.Count -ge 2) {
            $label = $pending[0]
            $help = $pending[1]
        }
        else {
            $help = $pending[0]
        }

        $map[$PathKey] = @{
            Label    = $label
            HelpText = $help
        }
        $pending.Clear()
    }

    while ($i -lt $length) {
        $c = $chars[$i]
        $next = if (($i + 1) -lt $length) { $chars[$i + 1] } else { [char]0 }

        if ($inString) {
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

        if ($c -eq [char]0x2F -and $next -eq [char]0x2F) {
            $i += 2
            $start = $i
            while ($i -lt $length -and $chars[$i] -ne [char]0x0A -and $chars[$i] -ne [char]0x0D) {
                $i++
            }
            Add-PendingComment -Raw ([string]::new($chars, $start, $i - $start))
            continue
        }

        if ($c -eq [char]0x2F -and $next -eq [char]0x2A) {
            $i += 2
            $start = $i
            while ($i -lt $length) {
                if (($i + 1) -lt $length -and $chars[$i] -eq [char]0x2A -and $chars[$i + 1] -eq [char]0x2F) {
                    Add-PendingComment -Raw ([string]::new($chars, $start, $i - $start))
                    $i += 2
                    break
                }
                $i++
            }
            continue
        }

        if ($c -eq [char]0x22) {
            $i++
            $start = $i
            $escape = $false
            while ($i -lt $length) {
                $sc = $chars[$i]
                if ($escape) {
                    $escape = $false
                }
                elseif ($sc -eq [char]0x5C) {
                    $escape = $true
                }
                elseif ($sc -eq [char]0x22) {
                    break
                }
                $i++
            }
            $stringValue = [string]::new($chars, $start, [Math]::Max(0, $i - $start))
            if ($i -lt $length -and $chars[$i] -eq [char]0x22) {
                $i++
            }

            $k = $i
            while ($k -lt $length -and ($chars[$k] -eq [char]0x20 -or $chars[$k] -eq [char]0x09 -or $chars[$k] -eq [char]0x0A -or $chars[$k] -eq [char]0x0D)) {
                $k++
            }

            if ($k -lt $length -and $chars[$k] -eq [char]0x3A) {
                $currentKey = $stringValue
                $pathParts = @($stack.ToArray() + $currentKey)
                Save-PendingComments -PathKey ($pathParts -join '.')
                $afterColon = $true
                $i = $k + 1
                continue
            }

            $afterColon = $false
            continue
        }

        if ($c -eq [char]0x7B) {
            if ($afterColon -and $currentKey) {
                $stack.Add($currentKey)
                $currentKey = $null
            }
            $afterColon = $false
            $i++
            continue
        }

        if ($c -eq [char]0x5B) {
            if ($afterColon -and $currentKey) {
                $stack.Add($currentKey)
                $currentKey = $null
            }
            $afterColon = $false
            $i++
            continue
        }

        if ($c -eq [char]0x7D -or $c -eq [char]0x5D) {
            if ($stack.Count -gt 0) {
                $stack.RemoveAt($stack.Count - 1)
            }
            $currentKey = $null
            $afterColon = $false
            $pending.Clear()
            $i++
            continue
        }

        if ($c -eq [char]0x2C) {
            $currentKey = $null
            $afterColon = $false
            $i++
            continue
        }

        $i++
    }

    return $map
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

function ConvertTo-HumanWords {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    $text = [regex]::Replace($Name, '([a-z0-9])([A-Z])', '$1 $2')
    $text = [regex]::Replace($text, '([A-Z]+)([A-Z][a-z])', '$1 $2')
    $text = $text.Replace('_', ' ').Replace('-', ' ')
    $parts = $text.Split(@(' '), [System.StringSplitOptions]::RemoveEmptyEntries)
    return ($parts | ForEach-Object {
            if ($_ -cmatch '^[A-Z]{2,}$') { $_ }
            else { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }
        }) -join ' '
}

function Get-GeneratedLabel {
    param([string[]]$PathParts)

    if ($null -eq $PathParts -or $PathParts.Count -eq 0) {
        return ''
    }

    $leaf = [string]$PathParts[$PathParts.Count - 1]
    $humanLeaf = $null
    if ($script:LabelAliases.ContainsKey($leaf)) {
        $humanLeaf = [string]$script:LabelAliases[$leaf]
    }
    if (-not $humanLeaf) {
        $humanLeaf = ConvertTo-HumanWords $leaf
    }

    $wordCount = @($humanLeaf.Split(@(' '), [System.StringSplitOptions]::RemoveEmptyEntries)).Count
    if ($wordCount -ge 3) {
        return $humanLeaf
    }

    for ($i = $PathParts.Count - 2; $i -ge 0; $i--) {
        $parent = [string]$PathParts[$i]
        if ($script:SkipLabelParents.Contains($parent)) {
            continue
        }
        return "$(ConvertTo-HumanWords $parent) $humanLeaf"
    }

    return $humanLeaf
}

function ConvertTo-DefaultValueText {
    param($Value)

    if ($null -eq $Value -or [DBNull]::Value.Equals($Value)) {
        return ''
    }

    if ($Value -is [bool]) {
        if ($Value) { return 'True' }
        return 'False'
    }

    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy-MM-dd HH:mm:ss')
    }

    return [string]$Value
}

function New-TemplateRow {
    param(
        [string[]]$PathParts,
        $Value,
        [string]$ProjectName,
        [string]$ProjectPrefix,
        $CommentMap
    )

    $jsonPath = $PathParts -join '.'
    $templateName = if ($jsonPath) { "$ProjectPrefix.$jsonPath" } else { $ProjectPrefix }

    $label = Get-GeneratedLabel -PathParts $PathParts
    $helpText = ''
    if ($CommentMap -and $jsonPath -and $CommentMap.ContainsKey($jsonPath)) {
        $comment = $CommentMap[$jsonPath]
        if ($comment.Label) {
            $label = [string]$comment.Label
        }
        if ($comment.HelpText) {
            $helpText = [string]$comment.HelpText
        }
    }

    return [ordered]@{
        TemplateName = $templateName
        Label        = $label
        HelpText     = $helpText
        ControlType  = if ($templateName -match 'password') { 'Sensitive' } else { 'SingleLineText' }
        Type         = 'string'
        DefaultValue = (ConvertTo-DefaultValueText $Value)
        Project      = $ProjectName
        Variable     = ($PathParts -join ':')
        Exclude      = 'FALSE'
    }
}

function Add-TemplateRows {
    param(
        $Value,
        [string[]]$PathParts,
        [System.Collections.Generic.List[object]]$Rows,
        [string]$ProjectName,
        [string]$ProjectPrefix,
        $CommentMap
    )

    $leafName = if ($PathParts.Count -gt 0) { [string]$PathParts[$PathParts.Count - 1] } else { '' }
    if ($leafName -and $script:CollapsedSections.Contains($leafName) -and ((Test-JsonMap $Value) -or (Test-JsonList $Value))) {
        $jsonValue = ConvertTo-Json -InputObject $Value -Compress -Depth 100
        [void]$Rows.Add((New-TemplateRow -PathParts $PathParts -Value $jsonValue -ProjectName $ProjectName -ProjectPrefix $ProjectPrefix -CommentMap $CommentMap))
        return
    }

    if (Test-JsonMap $Value) {
        foreach ($name in @(Get-JsonPropertyNames $Value)) {
            if ($name -eq 'Links') {
                continue
            }
            $childPath = @($PathParts + [string]$name)
            Add-TemplateRows -Value (Get-JsonProperty $Value $name) -PathParts $childPath -Rows $Rows -ProjectName $ProjectName -ProjectPrefix $ProjectPrefix -CommentMap $CommentMap
        }
        return
    }

    if (Test-JsonList $Value) {
        $items = @($Value)
        if ($items.Count -eq 0) {
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
            foreach ($item in $items) {
                Add-TemplateRows -Value $item -PathParts $PathParts -Rows $Rows -ProjectName $ProjectName -ProjectPrefix $ProjectPrefix -CommentMap $CommentMap
            }
            return
        }

        $joined = ($items | ForEach-Object { ConvertTo-DefaultValueText $_ }) -join '; '
        [void]$Rows.Add((New-TemplateRow -PathParts $PathParts -Value $joined -ProjectName $ProjectName -ProjectPrefix $ProjectPrefix -CommentMap $CommentMap))
        return
    }

    [void]$Rows.Add((New-TemplateRow -PathParts $PathParts -Value $Value -ProjectName $ProjectName -ProjectPrefix $ProjectPrefix -CommentMap $CommentMap))
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "JSON file not found: $InputPath"
}

$jsonText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $InputPath))
$commentMap = Get-JsoncCommentMap -JsonText $jsonText
$document = ConvertFrom-JsonDocument -JsonText $jsonText

if (-not (Test-JsonMap $document) -and -not (Test-JsonList $document)) {
    throw 'JSON root must be an object or an array.'
}

$rows = New-Object System.Collections.Generic.List[object]
Add-TemplateRows -Value $document -PathParts @() -Rows $rows -ProjectName $Project -ProjectPrefix $Prefix -CommentMap $commentMap

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$writer = New-Object System.IO.StreamWriter ($OutputPath, $false, $utf8NoBom)
try {
    $writer.WriteLine((($script:CsvHeaders | ForEach-Object { ConvertTo-QuotedCsvField $_ }) -join ','))
    foreach ($row in $rows) {
        $fields = foreach ($header in $script:CsvHeaders) {
            ConvertTo-QuotedCsvField $row[$header]
        }
        $writer.WriteLine(($fields -join ','))
    }
}
finally {
    $writer.Dispose()
}

Write-Host "Wrote $($rows.Count) row(s) to $OutputPath"
