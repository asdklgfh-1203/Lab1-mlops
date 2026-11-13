# MLOps Foundations and Cloud Native AI — Lab 1

This project demonstrates a small end-to-end MLOps workflow. It trains an Iris classifier, tracks the training run with MLflow, serves predictions through FastAPI, packages the service as a Docker image, and deploys it to a local Kubernetes cluster with CPU-based autoscaling.

## Architecture

- **Training:** scikit-learn Random Forest classifier trained on the Iris dataset.
- **Experiment tracking:** MLflow records model parameters, accuracy, and model artifacts.
- **Inference API:** FastAPI exposes health-check and prediction endpoints.
- **Containerization:** Docker packages the API and trained model.
- **Orchestration:** kind runs the local Kubernetes cluster; Kubernetes Deployment and Service expose the API inside the cluster.
- **Autoscaling:** Horizontal Pod Autoscaler (HPA) adjusts the API replica count based on CPU utilization.

## Prerequisites

- Windows with Docker Desktop running in Linux-container mode.
- Python 3.12 for creating a new virtual environment.
- PowerShell.

The prepared workspace includes local `kind` and `kubectl` binaries in `.tools` and an installed Python environment in `.venv-lab`. These local tools and environments are excluded from Git.

Run the PowerShell commands below from the project root unless noted otherwise.

## 1. Train the model and track the run

From the project directory, run:

```powershell
& .\.venv-lab\Scripts\python.exe .\train.py
```

The script saves `model.pkl` and logs the training parameters, accuracy, and model artifact to the local `mlruns` directory. Both `model.pkl` and `mlruns` are generated locally and excluded from Git; rerun training to recreate them.

To open the MLflow UI in a separate PowerShell window:

```powershell
& .\.venv-lab\Scripts\python.exe -m mlflow ui --backend-store-uri .\mlruns --host 127.0.0.1 --port 5000
```

Open [http://127.0.0.1:5000](http://127.0.0.1:5000), select the `iris` experiment, and review the recorded run, parameters, and accuracy.

To create a new Python environment instead of using the prepared one:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python .\train.py
```

## 2. Create the local Kubernetes deployment

Start Docker Desktop, then run the deployment script:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\deploy-lab.ps1
```

The script checks Docker connectivity, creates the `mlops` kind cluster if needed, builds `iris-api:v1`, loads the image into kind, and applies the Kubernetes Deployment, Service, and HPA manifests.

## 3. Enable CPU metrics

The HPA requires CPU metrics from Metrics Server. Run:

```powershell
.\enable-hpa.ps1
```

The script deploys Metrics Server, applies the kubelet option required by this local kind cluster, and waits until `kubectl top nodes` can return metrics.

## 4. Verify the API

In a separate PowerShell window, start port forwarding and leave it running while sending requests:

```powershell
& .\.tools\kubectl.exe --context kind-mlops port-forward svc/iris-api 8080:80
```

From another PowerShell window, verify the health endpoint and submit a prediction request:

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8080/healthz

Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/predict `
  -ContentType 'application/json' `
  -Body '{"instances":[[5.1,3.5,1.4,0.2]]}'
```

The health endpoint should return `ok: true`; the prediction endpoint should return a `predictions` array.

## 5. Demonstrate HPA scaling

Open separate PowerShell windows to monitor HPA and Pods:

```powershell
& .\.tools\kubectl.exe --context kind-mlops get hpa iris-api --watch
```

```powershell
& .\.tools\kubectl.exe --context kind-mlops get pods -l app=iris-api --watch
```

Run the load generator from another PowerShell window:

```powershell
& .\.venv-lab\Scripts\python.exe .\load_test.py --seconds 60 --workers 10 --batch-size 100
```

This Iris model is computationally lightweight. For the local autoscaling demonstration, the Deployment sets `PREDICTION_REPEATS=20`, causing each API request to repeat the same inference while returning the same prediction. The application defaults to one inference when this environment variable is not set. The CPU request remains at `100m`, and the HPA target is 50% of the requested CPU.

HPA scale-up can take time and depends on measured CPU utilization. If CPU use falls below the target, Kubernetes may later scale the Deployment back down. A successful load-test run does not guarantee that every run will trigger scaling.

## Evidence

Screenshots are stored in `screenshots/`:

- `mlflow-run.png` — MLflow experiment run, parameters, and accuracy.
- `hpa-scaling.png` — HPA CPU utilization and replica-count change.
- `pods-scaled.png` — API Pod startup and readiness during scaling.
- `load-test.png` — load-test request and error totals.

## Project files

- `train.py` — trains and logs the Iris model.
- `app.py` — FastAPI inference service.
- `Dockerfile` — builds the API container image.
- `deployment.yaml` — Kubernetes Deployment, Service, and HPA.
- `load_test.py` — concurrent HTTP load generator.
- `deploy-lab.ps1` — builds and deploys the local application.
- `enable-hpa.ps1` — installs and configures Metrics Server for kind.
- `cleanup-lab.ps1` — removes the local kind cluster while preserving project files and the Docker image.

## Cleanup

After saving the evidence and submitting the project, stop port forwarding with `Ctrl+C`. To delete the local kind cluster, run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\cleanup-lab.ps1
```

The cleanup script removes the `mlops` kind cluster. It preserves the source files, screenshots, and Docker image.
