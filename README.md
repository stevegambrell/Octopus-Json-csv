# Octopus JSON to CSV

Converts nested JSON settings (for example `appsettings.json`) into a quoted CSV of Octopus variable templates. The layout matches the XML-to-CSV export: one row per leaf setting.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+

## Usage

Project name and template prefix are required:

```powershell
.\Convert-OctopusJsonToCsv.ps1 '.\appsettings.json' '.\appsettings.csv' -Project 'My Service' -Prefix 'MyService'
```

Or pass the same four arguments to `Convert-OctopusJsonToCsv.bat`:

```bat
Convert-OctopusJsonToCsv.bat appsettings.json appsettings.csv "My Service" MyService
```

### Parameters

| Parameter | Purpose |
| --- | --- |
| `-InputPath` (required) | Source JSON file |
| `-OutputPath` (required) | Destination CSV file |
| `-Project` (required) | Value written to the Project column |
| `-Prefix` (required) | Prefix prepended to TemplateName |

## Output columns

| Column | Source |
| --- | --- |
| TemplateName | `Prefix` plus the dotted JSON path |
| Label | Humanised setting name, or a short `//` comment above the property |
| HelpText | Second short `//` comment above the property, if present |
| ControlType | `SingleLineText` |
| Type | `Sensitive` when TemplateName contains `password`, otherwise `string` |
| DefaultValue | Leaf JSON value |
| Project | The `-Project` argument |
| Variable | Colon path of the JSON keys (`AppSettings:Serilog:MinimumLevel`) |
| Exclude | `FALSE` |

JSON with comments is accepted (`//`, `/* */`, and trailing commas). URLs inside strings are left unchanged.

## Output format

- Comma-separated
- Every field, including headers, wrapped in double quotes
- Quotes inside a value escaped by doubling them (`"` becomes `""`)
- UTF-8 without a BOM

## Tests

```powershell
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```
