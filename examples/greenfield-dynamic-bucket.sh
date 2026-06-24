#!/bin/bash

# GREENFIELD EXAMPLE (Semi-automated / Manual)

# If a Developer submits a BucketClaim WITHOUT an 'existingBucketName', COSI attempts Greenfield provisioning.
# Regular buckets created this way will be left Pending until a Tenant Admin physically creates them on StorageGRID,
# (unless mocked for experimental purposes).
# To enable this, you might specify a BucketClass with parameters:
#   bucketType: "regular"

# 1. Cluster Administrator defines a generic BucketClass
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClass
metadata:
  name: sg-regular-class
driverName: coke.sg.cosi.dev
deletionPolicy: Retain
parameters:
  bucketType: "regular"
EOF

# Show BucketClass status
kubectl get bucketclass sg-regular-class -o yaml

echo "Press ENTER to dynamically request a BucketClaim. COSI will automatically generate a unique Bucket UUID for you..."
read -p ""

# 2. Developer dynamically requests a new bucket 
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClaim
metadata:
  name: my-greenfield-claim
  namespace: sg-cosi-coke     # change to namespace where COSI driver is used
spec:
  bucketClassName: sg-regular-class   # Must match your deployed BucketClass
  protocols:
    - s3
  # Note: missing existingBucketName triggers Greenfield mode
EOF

sleep 2
# Extract the generated bucket name from K8s
GENERATED_BUCKET_NAME=$(kubectl get bucketclaim my-greenfield-claim -n sg-cosi-coke -o jsonpath='{.status.bucketName}')

echo "--------------------------------------------------------------------------------------------------"
echo "Notice! The driver has mocked 'Success' back to Kubernetes, so K8s thinks the bucket is ready."
echo "However, you must physically create THIS exact bucket name on your StorageGRID Tenant Admin console now:"
echo "=======> TARGET BUCKET NAME: ${GENERATED_BUCKET_NAME}"
echo "--------------------------------------------------------------------------------------------------"
echo "Please create ${GENERATED_BUCKET_NAME} on StorageGRID now."
read -p "Press ENTER ONLY AFTER YOU HAVE CREATED THE BUCKET ON STORAGEGRID..."

# 3. Developer requests access keys for their dynamic bucket claim
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccess
metadata:
  name: my-greenfield-access
  namespace: sg-cosi-coke    # change to namespace where COSI driver is used
spec:
  bucketClaimName: my-greenfield-claim
  bucketAccessClassName: sg-cosi-coke-readonly 
  credentialsSecretName: dynamic-s3-credentials 
  protocol: s3
EOF

# Show bucket access status and prompt to press ENTER when ready to view credentials
sleep 1
echo "You can verify the bucket access status before proceeding:"
kubectl get bucketaccess -n sg-cosi-coke -o yaml | grep -A 5 status
echo "Press ENTER to view the credentials in the Secret..."
read -p ""
kubectl get secret dynamic-s3-credentials -n sg-cosi-coke -o yaml
