$ErrorActionPreference = 'Stop'
$kind = Join-Path $PSScriptRoot '.tools\kind.exe'
if (-not (Test-Path $kind)) { throw "kind.exe is missing: $kind" }

$clusters = & $kind get clusters
if ($LASTEXITCODE -ne 0) { throw 'kind could not list clusters.' }
if ($clusters -contains 'mlops') {
    Write-Host 'Deleting the local mlops Kubernetes cluster...' -ForegroundColor Cyan
    & $kind delete cluster --name mlops
    if ($LASTEXITCODE -ne 0) { throw 'Deleting the mlops cluster failed.' }
} else {
    Write-Host 'The mlops cluster is already absent.'
}

Write-Host 'The project files and Docker image were kept.' -ForegroundColor Green
