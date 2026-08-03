[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'dist'
}

function Find-CSharpCompiler {
    $frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET'
    $candidates = @(
        (Join-Path $frameworkRoot 'Framework64\v4.0.30319\csc.exe'),
        (Join-Path $frameworkRoot 'Framework\v4.0.30319\csc.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'The .NET Framework C# compiler was not found.'
}

$sourceDirectory = Join-Path $PSScriptRoot 'src\PipEdgeKeeper'
$manifest = Join-Path $sourceDirectory 'app.manifest'
$sources = Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.cs' |
    Sort-Object Name |
    Select-Object -ExpandProperty FullName

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$executable = Join-Path $OutputDirectory 'PipEdgeKeeper.exe'
$compiler = Find-CSharpCompiler

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/warnaserror+',
    '/platform:anycpu',
    "/win32manifest:$manifest",
    "/out:$executable",
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll'
) + $sources

& $compiler $compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "C# compilation failed with exit code $LASTEXITCODE."
}

Write-Host "Built $executable"
