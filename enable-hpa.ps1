$ErrorActionPreference = 'Stop'

$kubectl = Join-Path $PSScriptRoot '.tools\kubectl.exe'
if (-not (Test-Path $kubectl)) { throw "kubectl.exe is missing: $kubectl" }

Write-Host 'Installing metrics-server for this local kind cluster...' -ForegroundColor Cyan
& $kubectl --context kind-mlops apply -f 'https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml'
if ($LASTEXITCODE -ne 0) { throw 'Installing metrics-server failed.' }

$deploymentText = & $kubectl --context kind-mlops -n kube-system get deployment metrics-server -o json
if ($LASTEXITCODE -ne 0) { throw 'Could not read the metrics-server Deployment.' }
$deployment = $deploymentText | ConvertFrom-Json
$container = $deployment.spec.template.spec.containers | Where-Object { $_.name -eq 'metrics-server' } | Select-Object -First 1
if (-not $container) { throw 'The metrics-server container was not found in its Deployment.' }
$metricsArgs = @()
if ($container.args) { $metricsArgs = @($container.args) }
if ($metricsArgs -notcontains '--kubelet-insecure-tls') {
    Write-Host 'Adding the local kind kubelet certificate option required by metrics-server...' -ForegroundColor Cyan
    $metricsArgs += '--kubelet-insecure-tls'
    $patchObject = @{
        spec = @{
            template = @{
                spec = @{
                    containers = @(
                        @{
                            name = 'metrics-server'
                            args = $metricsArgs
                        }
                    )
                }
            }
        }
    }
    $patchJson = $patchObject | ConvertTo-Json -Depth 20 -Compress
    $patchFile = Join-Path ([System.IO.Path]::GetTempPath()) ("metrics-server-patch-{0}.json" -f [guid]::NewGuid())
    [System.IO.File]::WriteAllText($patchFile, $patchJson, [System.Text.UTF8Encoding]::new($false))
    try {
        & $kubectl --context kind-mlops -n kube-system patch deployment metrics-server --type=strategic --patch-file $patchFile
        $patchExitCode = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $patchFile -ErrorAction SilentlyContinue
    }
    if ($patchExitCode -ne 0) { throw 'Patching metrics-server failed.' }
}

& $kubectl --context kind-mlops -n kube-system rollout status deployment/metrics-server --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'metrics-server did not become ready.' }

Write-Host 'Waiting for the first CPU metrics...' -ForegroundColor Cyan
for ($attempt = 1; $attempt -le 8; $attempt++) {
    Start-Sleep -Seconds 10
    & $kubectl --context kind-mlops top nodes
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'CPU metrics are available. HPA can now make scaling decisions.' -ForegroundColor Green
        & $kubectl --context kind-mlops get hpa iris-api
        exit 0
    }
}
throw 'metrics-server is running, but CPU metrics are not available yet.'
