# Lab 1：在 Kubernetes 上部署第一個模型服務

本作業會訓練 Iris 分類模型，以 MLflow 記錄訓練結果，再用 FastAPI 提供預測 API，最後部署到本機 Kubernetes 並觀察 HPA 擴容。

## 1. 建立本機叢集

本指南使用 Docker Desktop + kind。在 Docker Desktop 顯示執行中後，於此資料夾開啟 PowerShell。`.tools` 內含本次準備的 kind 和 kubectl，不必全域安裝：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& .\.tools\kind.exe version
& .\.tools\kubectl.exe version --client
```

## 2. 建立 Python 環境並訓練模型

在這次準備好的工作區，可以直接使用已安裝好依賴的虛擬環境：

```powershell
.\.venv-lab\Scripts\python.exe train.py
```

若在另一台電腦重新建立環境，請先安裝 Python 3.12，再在此專案資料夾執行：

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python train.py
```

這會建立 `model.pkl`，並將參數、準確率和模型紀錄到本機 `mlruns` 資料夾。

另開一個 PowerShell 視窗並進入同一資料夾，查看 MLflow。這次工作區可執行：

```powershell
.\.venv-lab\Scripts\python.exe -m mlflow ui --backend-store-uri ./mlruns --host 127.0.0.1 --port 5000
```

若是重新建立的環境，則先啟用 `.venv`，再執行：

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
mlflow ui --backend-store-uri ./mlruns --host 127.0.0.1 --port 5000
```

瀏覽 `http://127.0.0.1:5000`，截下 `iris` experiment 的 run、參數和 accuracy，存成 `screenshots/mlflow-run.png`。

## 3. 建立叢集、映像並部署

執行部署腳本。它會依序確認 Docker、建立 `mlops` 叢集、建置容器映像、將映像載入 kind，並套用 Deployment、Service 和 HPA：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\deploy-lab.ps1
```

## 4. 啟用 CPU metrics 並呼叫預測 API

HPA 必須先讀得到 CPU 數據。執行 `enable-hpa.ps1` 會部署 metrics-server、設定 kind 所需的 kubelet 連線選項，並確認 `kubectl top nodes` 有資料。

```powershell
.\enable-hpa.ps1
```

接著另開 PowerShell 視窗，保持 port-forward 執行：

```powershell
& .\.tools\kubectl.exe --context kind-mlops port-forward svc/iris-api 8080:80
```

再開一個 PowerShell 視窗測試：

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8080/predict `
  -ContentType 'application/json' `
  -Body '{"instances":[[5.1,3.5,1.4,0.2]]}'
```

預期會收到包含 `predictions` 的 JSON。可用 `http://localhost:8080/healthz` 確認健康檢查。

## 5. 產生負載並確認自動擴容

確認 `kubectl top nodes` 能讀到 CPU 使用率後，開一個視窗持續觀察 HPA：

```powershell
& .\.tools\kubectl.exe --context kind-mlops get hpa iris-api -w
```

另開視窗以專案內的 Python load generator 產生 60 秒、50 個併發工作負載：

```powershell
& .\.venv-lab\Scripts\python.exe .\load_test.py --seconds 60 --workers 50
```

另開一個視窗查看 Pod 數量：

```powershell
& .\.tools\kubectl.exe --context kind-mlops get pods -w
```

此範例模型非常輕量，所以 Deployment 設定 `PREDICTION_REPEATS=20`，讓每個預測請求重複執行推論以產生足夠 CPU 負載；回傳結果不變。應用程式預設值仍是 1，只有這份本機 HPA 示範設定會提高工作量。

等待 HPA 更新後，截下 HPA 與 Pod 數量變化，存成 `screenshots/hpa-scaling.png`。擴容需要一段時間；如果 CPU 顯示 `<unknown>`，先處理 metrics-server。

## 交付前確認

- GitHub repo 包含 `train.py`、`app.py`、`Dockerfile`、`deployment.yaml`、`requirements.txt`、`requirements-api.txt` 和 README。
- `model.pkl` 可由 `python train.py` 重新產生，不必提交大型模型檔。
- repo 中有 MLflow run 與 HPA 擴容截圖。

## 清理本機叢集

保存程式與截圖後，停止 port-forward（按 `Ctrl+C`），再刪除 kind 叢集。此腳本保留專案檔案和 Docker 映像：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\cleanup-lab.ps1
```
