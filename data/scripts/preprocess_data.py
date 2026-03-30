import pandas as pd
import numpy as np
import boto3
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import io
import sys

def main():
    # S3 client
    s3 = boto3.client('s3')
    
    # Get bucket names from command line
    raw_bucket = sys.argv[1]
    processed_bucket = sys.argv[2]
    
    print("Starting data preprocessing...")
    
    # Column names for NSL-KDD dataset
    columns = [
        'duration', 'protocol_type', 'service', 'flag', 'src_bytes', 'dst_bytes',
        'land', 'wrong_fragment', 'urgent', 'hot', 'num_failed_logins', 'logged_in',
        'num_compromised', 'root_shell', 'su_attempted', 'num_root', 'num_file_creations',
        'num_shells', 'num_access_files', 'num_outbound_cmds', 'is_host_login',
        'is_guest_login', 'count', 'srv_count', 'serror_rate', 'srv_serror_rate',
        'rerror_rate', 'srv_rerror_rate', 'same_srv_rate', 'diff_srv_rate',
        'srv_diff_host_rate', 'dst_host_count', 'dst_host_srv_count',
        'dst_host_same_srv_rate', 'dst_host_diff_srv_rate', 'dst_host_same_src_port_rate',
        'dst_host_srv_diff_host_rate', 'dst_host_serror_rate', 'dst_host_srv_serror_rate',
        'dst_host_rerror_rate', 'dst_host_srv_rerror_rate', 'label', 'difficulty'
    ]
    
    # Download and load data from S3
    print("Loading training data...")
    train_obj = s3.get_object(Bucket=raw_bucket, Key='raw/KDDTrain+.txt')
    train_data = pd.read_csv(io.BytesIO(train_obj['Body'].read()), names=columns)
    
    print("Loading test data...")
    test_obj = s3.get_object(Bucket=raw_bucket, Key='raw/KDDTest+.txt')
    test_data = pd.read_csv(io.BytesIO(test_obj['Body'].read()), names=columns)
    
    print(f"Training data shape: {train_data.shape}")
    print(f"Test data shape: {test_data.shape}")
    
    # Preprocessing function
    def preprocess_data(df):
        df = df.copy()
        
        # Remove difficulty column
        if 'difficulty' in df.columns:
            df = df.drop('difficulty', axis=1)
        
        # Convert label to binary (0: normal, 1: attack)
        df['label'] = df['label'].apply(lambda x: 0 if x == 'normal' else 1)
        
        # Encode categorical features
        categorical_features = ['protocol_type', 'service', 'flag']
        
        for feature in categorical_features:
            le = LabelEncoder()
            df[feature] = le.fit_transform(df[feature])
        
        # Separate features and target
        X = df.drop('label', axis=1)
        y = df['label']
        
        # Normalize continuous features
        scaler = StandardScaler()
        X_scaled = pd.DataFrame(scaler.fit_transform(X), columns=X.columns)
        
        return X_scaled, y, scaler
    
    # Preprocess data
    print("Preprocessing training data...")
    X_train, y_train, scaler = preprocess_data(train_data)
    
    print("Preprocessing test data...")
    X_test, y_test, _ = preprocess_data(test_data)
    
    # Prepare data for XGBoost (target as first column)
    train_data_xgb = pd.concat([y_train, X_train], axis=1)
    test_data_xgb = pd.concat([y_test, X_test], axis=1)
    
    # Create validation split
    X_train_split, X_val, y_train_split, y_val = train_test_split(
        X_train, y_train, test_size=0.2, random_state=42, stratify=y_train
    )
    
    train_split_xgb = pd.concat([y_train_split, X_train_split], axis=1)
    val_data_xgb = pd.concat([y_val, X_val], axis=1)
    
    # Upload processed data to S3
    print("Uploading processed training data...")
    csv_buffer = io.StringIO()
    train_split_xgb.to_csv(csv_buffer, index=False, header=False)
    s3.put_object(Bucket=processed_bucket, Key='processed/train/train.csv', Body=csv_buffer.getvalue())
    
    print("Uploading processed validation data...")
    csv_buffer = io.StringIO()
    val_data_xgb.to_csv(csv_buffer, index=False, header=False)
    s3.put_object(Bucket=processed_bucket, Key='processed/validation/validation.csv', Body=csv_buffer.getvalue())
    
    print("Uploading processed test data...")
    csv_buffer = io.StringIO()
    test_data_xgb.to_csv(csv_buffer, index=False, header=False)
    s3.put_object(Bucket=processed_bucket, Key='processed/test/test.csv', Body=csv_buffer.getvalue())
    
    # Save feature information
    feature_info = {
        'feature_names': X_train.columns.tolist(),
        'num_features': len(X_train.columns)
    }
    
    import json
    s3.put_object(
        Bucket=processed_bucket, 
        Key='feature_info.json', 
        Body=json.dumps(feature_info)
    )
    
    print("Data preprocessing completed successfully!")
    print(f"Training data: s3://{processed_bucket}/processed/train/train.csv")
    print(f"Validation data: s3://{processed_bucket}/processed/validation/validation.csv")
    print(f"Test data: s3://{processed_bucket}/processed/test/test.csv")

if __name__ == "__main__":
    main()
