# Octopus JSON to CSV

Converts nested JSON settings (for example `appsettings.json`) into a quoted CSV of Octopus variable templates. The layout matches the XML-to-CSV export: one row per leaf setting.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+

## Usage

```powershell
.\Convert-OctopusJsonToCsv.ps1 '.\appsettings.json' '.\appsettings.csv'
```

Or pass the same two paths to `Convert-OctopusJsonToCsv.bat`:

```bat
Convert-OctopusJsonToCsv.bat appsettings.json appsettings.csv
```

Optional project name, used when the JSON is not wrapped in a project key:

```powershell
.\Convert-OctopusJsonToCsv.ps1 '.\appsettings.json' '.\appsettings.csv' -Project 'MNO Mediation Service'
```

### Parameters

| Parameter | Purpose |
| --- | --- |
| `-InputPath` (required) | Source JSON file |
| `-OutputPath` (required) | Destination CSV file |
| `-Project` | Optional project display name |

## Output columns

| Column | Source |
| --- | --- |
| TemplateName | Dotted JSON path, including the project key |
| Label | Humanised setting name, or a short `//` comment above the property |
| HelpText | Second short `//` comment above the property, if present |
| ControlType | `SingleLineText` |
| Type | `string` |
| DefaultValue | Leaf JSON value |
| Project | Humanised root key (`MNOMediationService` → `MNO Mediation Service`) |
| Variable | Colon path without the project prefix (`AppSettings:Serilog:MinimumLevel`) |
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
