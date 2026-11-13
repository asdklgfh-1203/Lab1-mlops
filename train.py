"""Train an Iris classifier and record the run in MLflow."""

import joblib
import mlflow
import mlflow.sklearn
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split


def main() -> None:
    features, labels = load_iris(return_X_y=True)
    x_train, x_test, y_train, y_test = train_test_split(
        features,
        labels,
        test_size=0.2,
        random_state=42,
        stratify=labels,
    )

    estimator_count = 100
    model = RandomForestClassifier(n_estimators=estimator_count, random_state=42)
    model.fit(x_train, y_train)
    accuracy = accuracy_score(y_test, model.predict(x_test))

    mlflow.set_experiment("iris")
    with mlflow.start_run() as run:
        mlflow.log_param("n_estimators", estimator_count)
        mlflow.log_param("test_size", 0.2)
        mlflow.log_metric("accuracy", accuracy)
        mlflow.sklearn.log_model(model, "model")
        joblib.dump(model, "model.pkl")
        print(f"MLflow run: {run.info.run_id}")
        print(f"Accuracy: {accuracy:.3f}")
        print("Saved model to model.pkl")


if __name__ == "__main__":
    main()
