#!/usr/bin/env python3
"""
Automated training script for the Kubernetes architecture.
Uses the single S3 bucket for all data. Updates the K8s inference service
instead of Lambda when a new endpoint is deployed.
"""
import boto3
import sagemaker
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
import json
import os
import sys
import time
import subprocess


def get_terraform_output(key):
    """Get a Terraform output value."""
    result = subprocess.run(
        ["terraform", "output", "-raw", key],
        capture_output=True, text=True,
        cwd=os.path.join(os.path.dirname(__file__), "..", "terraform")
    )
    if result.returncode != 0:
        raise Exception(f"Failed to get terraform output '{key}': {result.stderr}")
    return result.stdout.strip()


def create_sample_data(bucket, s3_client):
    """Create sample training data if none exists."""
    print("📊 Creating sample training data...")
    np.random.seed(42)
    n_samples = 1000

    data = {
        'duration': np.random.exponential(1, n_samples),
        'protocol_type': np.random.choice([0, 1, 2], n_samples),
        'service': np.random.choice([0, 1, 2, 3, 4], n_samples),
        'flag': np.random.choice([0, 1, 2, 3], n_samples),
        'src_bytes': np.random.exponential(100, n_samples),
        'dst_bytes': np.random.exponential(1000, n_samples),
        'land': np.random.choice([0, 1], n_samples, p=[0.9, 0.1]),
        'wrong_fragment': np.random.poisson(0.1, n_samples),
        'urgent': np.random.poisson(0.05, n_samples),
        'hot': np.random.poisson(0.2, n_samples),
    }
    for i in range(31):
        data[f'feature_{i}'] = np.random.normal(0, 1, n_samples)
    data['label'] = np.random.choice([0, 1], n_samples, p=[0.7, 0.3])

    df = pd.DataFrame(data)
    # SageMaker XGBoost expects label as the first column
    cols = ['label'] + [c for c in df.columns if c != 'label']
    df = df[cols]
    train_df, val_df = train_test_split(df, test_size=0.2, random_state=42)

    s3_client.put_object(Bucket=bucket, Key='processed/train/train.csv',
                         Body=train_df.to_csv(index=False, header=False))
    s3_client.put_object(Bucket=bucket, Key='processed/validation/validation.csv',
                         Body=val_df.to_csv(index=False, header=False))
    print("✅ Sample data created and uploaded")


def main():
    try:
        print("🚀 Starting automated training (Kubernetes architecture)...")

        sess = sagemaker.Session()
        region = sess.boto_region_name
        s3_client = boto3.client('s3')
        sagemaker_client = boto3.client('sagemaker')

        role = get_terraform_output("sagemaker_role_arn")
        bucket = get_terraform_output("s3_data_bucket")

        print(f"📦 Using bucket: {bucket}")
        print(f"🔑 Using role: {role}")

        # Check for training data
        try:
            s3_client.head_object(Bucket=bucket, Key='processed/train/train.csv')
            print("✅ Training data found")
        except Exception:
            print("⚠️  No training data found, creating sample data...")
            create_sample_data(bucket, s3_client)

        train_path = f's3://{bucket}/processed/train/'
        validation_path = f's3://{bucket}/processed/validation/'
        output_path = f's3://{bucket}/model-output/'

        container = sagemaker.image_uris.retrieve('xgboost', region, version='1.5-1')

        from sagemaker.estimator import Estimator
        xgb_estimator = Estimator(
            image_uri=container,
            role=role,
            instance_count=1,
            instance_type='ml.m5.large',
            output_path=output_path,
            sagemaker_session=sess,
            hyperparameters={
                'objective': 'binary:logistic',
                'eval_metric': 'auc',
                'num_round': 50,
                'max_depth': 4,
                'eta': 0.1,
            }
        )

        print("🔄 Training model (this may take 5-10 minutes)...")
        from sagemaker.inputs import TrainingInput
        xgb_estimator.fit({
            'train': TrainingInput(train_path, content_type='text/csv'),
            'validation': TrainingInput(validation_path, content_type='text/csv'),
        }, wait=True)

        # Clean up existing endpoints
        endpoints = sagemaker_client.list_endpoints(
            NameContains='threat-detection-endpoint'
        )['Endpoints']
        for ep in endpoints:
            if ep['EndpointStatus'] == 'InService':
                print(f"🗑️  Deleting existing endpoint: {ep['EndpointName']}")
                sagemaker_client.delete_endpoint(EndpointName=ep['EndpointName'])
                time.sleep(5)

        endpoint_name = f'threat-detection-endpoint-{int(time.time())}'
        print(f"🚀 Deploying endpoint: {endpoint_name}")

        xgb_estimator.deploy(
            initial_instance_count=1,
            instance_type='ml.t2.medium',
            endpoint_name=endpoint_name,
            wait=True,
        )

        # Update K8s inference service with new endpoint name (if deployed)
        print("☸️  Updating K8s inference service...")
        result = subprocess.run([
            "kubectl", "set", "env",
            "deployment/inference-service",
            f"SAGEMAKER_ENDPOINT_NAME={endpoint_name}",
            "-n", "threat-detection"
        ], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"⚠️  K8s not deployed yet. Set the endpoint name when deploying:")
            print(f"   export SAGEMAKER_ENDPOINT_NAME={endpoint_name}")
            print(f"   task k8s:deploy")
        else:
            print("✅ K8s inference service updated")

        # Save endpoint info to S3
        s3_client.put_object(
            Bucket=bucket,
            Key='endpoint_info.json',
            Body=json.dumps({
                'endpoint_name': endpoint_name,
                'status': 'InService',
                'created_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            }, indent=2)
        )

        print("✅ Training and deployment completed successfully!")
        print(f"📍 Endpoint: {endpoint_name}")

    except KeyboardInterrupt:
        print("\n⚠️  Training interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
