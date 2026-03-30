"""
API Service - Replaces Lambda + API Gateway.
Receives prediction requests from the frontend and forwards them to the Inference Service.
"""
import os
import json
import logging
import requests
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

INFERENCE_SERVICE_URL = os.environ.get(
    "INFERENCE_SERVICE_URL", "http://inference-service.threat-detection.svc.cluster.local:8080"
)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/predict", methods=["POST", "OPTIONS"])
def predict():
    if request.method == "OPTIONS":
        return jsonify({}), 200

    try:
        body = request.get_json()
        if not body or "features" not in body:
            return jsonify({"error": "Missing 'features' in request body"}), 400

        features = body["features"]
        logger.info(f"Received prediction request with {len(features)} features")

        # Forward to inference service
        resp = requests.post(
            f"{INFERENCE_SERVICE_URL}/invoke",
            json={"features": features},
            timeout=30,
        )
        resp.raise_for_status()
        result = resp.json()

        logger.info(f"Prediction result: {result.get('status', 'unknown')}")
        return jsonify(result), 200

    except requests.exceptions.RequestException as e:
        logger.error(f"Inference service error: {e}")
        return jsonify({"error": "Inference service unavailable", "message": str(e)}), 503
    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({"error": str(e), "message": "Error processing prediction request"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
