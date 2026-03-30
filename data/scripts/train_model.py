import boto3
import sagemaker
from sagemaker.xgboost.estimator import XGBoost
from sagemaker.inputs import TrainingInput
import sys

def main():
    processed_bucket = sys.argv[1]
    
    print("Starting model training...")
    
    # Initialize SageMaker session
    sess = sagemaker.Session()
    role = sagemaker.get_execution_role()
    region = boto3.Session().region_name
    
    # Define S3 paths
    train_path = f's3://{processed_bucket}/train/'
    validation_path = f's3://{processed_bucket}/validation/'
    output_path = f's3://{processed_bucket}/model-output/'
    
    print(f"Training data: {train_path}")
    print(f"Validation data: {validation_path}")
    print(f"Model output: {output_path}")
    
    # Get XGBoost container
    container = sagemaker.image_uris.retrieve('xgboost', region, version='1.5-1')
    
    # Create XGBoost estimator
    xgb_estimator = XGBoost(
        image_uri=container,
        role=role,
        instance_count=1,
        instance_type='ml.m5.xlarge',
        output_path=output_path,
        sagemaker_session=sess,
        hyperparameters={
            'objective': 'binary:logistic',
            'eval_metric': 'auc',
            'num_round': 100,
            'max_depth': 6,
            'eta': 0.1,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'min_child_weight': 3,
            'gamma': 0.1,
            'reg_alpha': 0.1,
            'reg_lambda': 1,
            'scale_pos_weight': 1,
            'early_stopping_rounds': 10,
            'verbosity': 1
        }
    )
    
    # Define training inputs
    train_input = TrainingInput(train_path, content_type='text/csv')
    validation_input = TrainingInput(validation_path, content_type='text/csv')
    
    # Start training
    print("Starting model training job...")
    xgb_estimator.fit({
        'train': train_input,
        'validation': validation_input
    })
    
    # Deploy model
    print("Deploying model to endpoint...")
    predictor = xgb_estimator.deploy(
        initial_instance_count=1,
        instance_type='ml.t2.medium',
        endpoint_name='threat-detection-endpoint'
    )
    
    print(f"Model deployed to endpoint: {predictor.endpoint_name}")
    print("Training and deployment completed successfully!")

if __name__ == "__main__":
    main()
