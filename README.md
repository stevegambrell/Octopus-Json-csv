# Octopus JSON to CSV

Converts Octopus Deploy JSON into a quoted CSV file.

Use this when you already have JSON from the Octopus REST API (or a JSON export of the reporting feed) and need a spreadsheet-ready CSV. The CSV format matches the earlier XML-to-CSV export: comma-separated, every field wrapped in double quotes, and embedded quotes escaped as `""`.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+

## Usage

```powershell
.\Convert-OctopusJsonToCsv.ps1 '.\deployments.json' 'D:\Octopus-Deployments.csv'
```

Or pass the same two paths to `Convert-OctopusJsonToCsv.bat`:

```bat
Convert-OctopusJsonToCsv.bat deployments.json D:\Octopus-Deployments.csv
```

### Parameters

| Parameter | Purpose |
| --- | --- |
| `-InputPath` (required) | Source JSON file |
| `-OutputPath` (required) | Destination CSV file |

## JSON shapes

The converter turns each record into one CSV row. It recognises:

- A JSON array of objects
- An Octopus API collection with an `Items` array
- Reporting-style JSON such as `{ "Deployments": { "Deployment": [ ... ] } }`
- A single object (one row)

Nested objects become columns named with dots (`Project.Name`). Arrays of scalars are joined with `"; "`. Arrays of objects are stored as compact JSON. Octopus HAL `Links` properties are skipped.

JSON with comments is accepted (`//` line comments, `/* block comments */`, and trailing commas). Text inside strings is left unchanged, so URLs such as `https://example.com` are not treated as comments.

## Output format

- Comma-separated
- Every field, including headers, wrapped in double quotes
- Quotes inside a value escaped by doubling them (`"` becomes `""`)
- UTF-8 without a BOM

## Tests

From PowerShell 7 (or Windows PowerShell):

```powershell
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```
