[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$htmlPath = Join-Path $rootPath 'docs\technical-report.html'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $rootPath 'docs\SecureFinance_ERP_Documento_Tecnico.pdf'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

& node (Join-Path $PSScriptRoot 'build-technical-html.mjs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $htmlPath)) {
    throw 'No se pudo generar el documento HTML tecnico.'
}

$edgeCandidates = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
)
$edgePath = $edgeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edgePath) {
    throw 'Microsoft Edge no esta instalado; el HTML quedo disponible en docs\technical-report.html.'
}

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$profilePath = Join-Path $temporaryRoot ("securefinance-pdf-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $profilePath | Out-Null
try {
    $htmlUri = [System.Uri]::new($htmlPath).AbsoluteUri
    $temporaryPdfPath = Join-Path $profilePath 'technical-report.pdf'
    & $edgePath '--headless=new' '--disable-gpu' '--no-pdf-header-footer' "--user-data-dir=$profilePath" "--print-to-pdf=$temporaryPdfPath" $htmlUri
    $edgeExitCode = $LASTEXITCODE

    # Edge can delegate printing to a child process and return before the file
    # is completely flushed. Wait for a non-empty, stable temporary file before
    # replacing the requested output.
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $lastLength = -1L
    $stableSamples = 0
    while ([DateTime]::UtcNow -lt $deadline -and $stableSamples -lt 3) {
        if (Test-Path -LiteralPath $temporaryPdfPath) {
            $length = (Get-Item -LiteralPath $temporaryPdfPath).Length
            if ($length -gt 0 -and $length -eq $lastLength) {
                $stableSamples++
            }
            else {
                $stableSamples = 0
                $lastLength = $length
            }
        }
        Start-Sleep -Milliseconds 100
    }
    if ($edgeExitCode -ne 0 -or $stableSamples -lt 3) {
        throw 'Microsoft Edge no produjo el PDF esperado.'
    }
    [IO.File]::Copy($temporaryPdfPath, $OutputPath, $true)
    Write-Host "PDF tecnico generado: $OutputPath"
}
finally {
    $resolvedProfile = [System.IO.Path]::GetFullPath($profilePath)
    if ($resolvedProfile.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedProfile).StartsWith('securefinance-pdf-')) {
        Remove-Item -LiteralPath $resolvedProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}
