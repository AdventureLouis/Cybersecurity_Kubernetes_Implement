"""
Inference Service - Calls the SageMaker endpoint.
This is the same logic that was in Lambda predict.py, now running as a K8s service.
"""
import os
import json
import logging
import boto3
from flask import Flask, request, jsonify

app = Flask(__name__)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

ENDPOINT_NAME = os.environ.get("SAGEMAKER_ENDPOINT_NAME", "threat-detection-endpoint")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

sagemaker_runtime = boto3.client("sagemaker-runtime", region_name=AWS_REGION)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/invoke", methods=["POST"])
def invoke():
    try:
        body = request.get_json()
        features = body["features"]

        # Convert to CSV format for XGBoost (same as original Lambda)
        csv_input = ",".join(map(str, features))

        logger.info(f"Invoking SageMaker endpoint: {ENDPOINT_NAME}")

        response = sagemaker_runtime.invoke_endpoint(
            EndpointName=ENDPOINT_NAME,
            ContentType="text/csv",
            Body=csv_input,
        )

        result = response["Body"].read().decode().strip()

        # Handle different response formats
        if result.startswith("[") and result.endswith("]"):
            prediction = float(result.strip("[]"))
        else:
            prediction = float(result)

        # Binary classification (0: normal, 1: attack)
        threat_detected = 1 if prediction > 0.5 else 0
        confidence = prediction if threat_detected else 1 - prediction

        return jsonify({
            "prediction": threat_detected,
            "confidence": round(confidence, 4),
            "status": "Attack Detected" if threat_detected else "Normal Traffic",
            "raw_score": round(prediction, 4),
        }), 200

    except Exception as e:
        logger.error(f"Inference error: {e}")
        return jsonify({"error": str(e), "message": "Error processing inference request"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
