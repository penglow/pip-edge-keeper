[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

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

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceDirectory = Join-Path $repositoryRoot 'src\PipEdgeKeeper'
$temporaryDirectory = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('PipEdgeKeeper.Tests.' + [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    $testExecutable = Join-Path $temporaryDirectory 'PipEdgeKeeper.Tests.exe'
    $sources = @(
        (Join-Path $sourceDirectory 'AppSettings.cs'),
        (Join-Path $sourceDirectory 'Geometry.cs'),
        (Join-Path $sourceDirectory 'NativeMethods.cs'),
        (Join-Path $sourceDirectory 'EdgeKeeperEngine.cs'),
        (Join-Path $PSScriptRoot 'PipEdgeKeeper.Tests.cs')
    )

    $compilerArguments = @(
        '/nologo',
        '/target:exe',
        '/optimize+',
        '/warnaserror+',
        "/out:$testExecutable",
        '/reference:System.dll',
        '/reference:System.Core.dll',
        '/reference:System.Drawing.dll'
    ) + $sources

    & (Find-CSharpCompiler) $compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Test compilation failed with exit code $LASTEXITCODE."
    }

    & $testExecutable
    if ($LASTEXITCODE -ne 0) {
        throw "Tests failed with exit code $LASTEXITCODE."
    }
} finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
}
