$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$kind = Join-Path $projectRoot '.tools\kind.exe'
$kubectl = Join-Path $projectRoot '.tools\kubectl.exe'

if (-not (Test-Path $kind)) { throw "kind.exe is missing: $kind" }
if (-not (Test-Path $kubectl)) { throw "kubectl.exe is missing: $kubectl" }

$dockerCommand = Get-Command docker.exe -ErrorAction SilentlyContinue
$docker = $null
if ($dockerCommand) { $docker = $dockerCommand.Source }
if (-not $dockerCommand) {
    $dockerCandidate = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'
    if (Test-Path $dockerCandidate) { $docker = $dockerCandidate }
}
if (-not $docker) { throw 'Docker CLI not found. Start Docker Desktop and check that docker info works.' }

Write-Host 'Step 1/5: checking Docker Desktop...' -ForegroundColor Cyan
& $docker info --format 'Docker {{.ServerVersion}} / {{.OperatingSystem}} / {{.NCPU}} CPUs'
if ($LASTEXITCODE -ne 0) { throw 'Docker Engine is not reachable. Start Docker Desktop and retry.' }

Write-Host 'Step 2/5: creating the local Kubernetes cluster if needed...' -ForegroundColor Cyan
$clusters = & $kind get clusters
if ($LASTEXITCODE -ne 0) { throw 'kind could not list clusters.' }
if ($clusters -notcontains 'mlops') {
    & $kind create cluster --name mlops --wait 5m
    if ($LASTEXITCODE -ne 0) { throw 'kind cluster creation failed.' }
} else {
    Write-Host 'The mlops cluster already exists; reusing it.'
}

Write-Host 'Step 3/5: building the FastAPI container image...' -ForegroundColor Cyan
& $docker build -t iris-api:v1 $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'Docker image build failed.' }

Write-Host 'Step 4/5: loading the image into kind...' -ForegroundColor Cyan
& $kind load docker-image iris-api:v1 --name mlops
if ($LASTEXITCODE -ne 0) { throw 'Loading the image into kind failed.' }

Write-Host 'Step 5/5: deploying the API, Service, and HPA...' -ForegroundColor Cyan
& $kubectl --context kind-mlops apply -f (Join-Path $projectRoot 'deployment.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Applying deployment.yaml failed.' }
& $kubectl --context kind-mlops rollout status deployment/iris-api --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'The iris-api Deployment did not become ready.' }

Write-Host 'Deployment is ready. Current Kubernetes resources:' -ForegroundColor Green
& $kubectl --context kind-mlops get pods,svc,hpa
