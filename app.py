"""Small FastAPI service that serves the trained Iris model."""

from pathlib import Path
import os

import joblib
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


MODEL_PATH = Path(__file__).with_name("model.pkl")
model = joblib.load(MODEL_PATH)
prediction_repeats = int(os.getenv("PREDICTION_REPEATS", "1"))
if prediction_repeats < 1:
    raise ValueError("PREDICTION_REPEATS must be at least 1")
app = FastAPI(title="Iris model API")


class PredictRequest(BaseModel):
    instances: list[list[float]]


@app.get("/healthz")
def healthz() -> dict[str, bool]:
    return {"ok": True}


@app.post("/predict")
def predict(request: PredictRequest) -> dict[str, list[int]]:
    if not request.instances or any(len(row) != 4 for row in request.instances):
        raise HTTPException(
            status_code=422,
            detail="Each instance must contain four Iris measurements.",
        )
    # A configurable repeat count lets the local HPA lab create CPU demand while
    # keeping the returned predictions identical. It defaults to one for normal use.
    predictions = None
    for _ in range(prediction_repeats):
        predictions = model.predict(request.instances)
    return {"predictions": predictions.astype(int).tolist()}
