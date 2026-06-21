#!/bin/bash

# BROWNFIELD EXAMPLE (Recommended)

# This script demonstrates how to use COSI to map an EXISTING StorageGRID bucket to Kubernetes, which is the only recommended
# approach for regular buckets on StorageGRID. 

# This example maps Kubernetes COSI to an EXISTING StorageGRID bucket (e.g., 'coke')
# It demonstrates how to create a global Bucket object, claim it in a namespace, and request access keys for the claimed bucket.
# It is based on README.md values for the Helm chart, and the example YAML files in this directory.

# 1. Cluster Administrator defines the global backend Bucket

cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: Bucket
metadata:
  name: sg-brownfield-coke-analytics-bucket # Must be unique across the cluster. This is the global identifier for the bucket in K8s.
spec:
  driverName: sg.cosi.dev                  # Check Helm output for the exact driver name deployed in this namespace
  bucketClassName: sg-cosi-coke-default    # Must match your driver's deployed BucketClass
  bucketClaim:
    name: analytics-bucket-claim      # Name of the BucketClaim that will be used to claim this bucket in a namespace
    namespace: sg-cosi-coke           # Check Helm output for the namespace where your driver is deployed
  existingBucketID: analytics         # Maps directly to the bucket name on StorageGRID. Create this bucket if it doesn't exist
  deletionPolicy: Retain              # Always use Retain for Brownfield/StorageGRID
  protocols:
    - s3
  parameters:
    bucketName: analytics             # Passed to the driver
EOF

# Show Bucket object status
kubectl get bucket sg-brownfield-coke-analytics-bucket -o yaml | grep -A 5 status

# IMPORTANT NOTE FOR BROWNFIELD BUCKETS (COSI v1alpha1):
# When manually creating a Bucket object, the Cluster Administrator MUST manually patch the Bucket 
# status to tell the COSI Controller that the unmanaged external Bucket is validated and ready! 
# Prompt to press ENTER when ready to patch bucket status

read -p "Press ENTER to patch the Bucket status to indicate readiness..."

# AFTER applying the Bucket YAML:
kubectl patch bucket sg-brownfield-coke-analytics-bucket --subresource status --type merge -p '{"status": {"bucketID": "analytics", "bucketReady": true}}'

sleep 1
echo "You can verify the bucket status is patched and ready before proceeding:"
kubectl get bucket sg-brownfield-coke-analytics-bucket -o yaml | grep -A 5 status

read -p "Press ENTER to create the BucketClaim..."

# 2. Developer claims the pre-existing bucket in their namespace
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClaim
metadata:
  name: analytics-bucket-claim
  namespace: sg-cosi-coke
spec:
  bucketClassName: sg-cosi-coke-default
  protocols:
    - s3
  existingBucketName: sg-brownfield-coke-analytics-bucket # Maps to the global K8s Bucket 'name' above
EOF

# Show bucket status and bucketClaim status and prompt to press ENTER when ready to request access keys
sleep 1
echo "You can verify the bucket and bucket claim status before proceeding:"
kubectl get bucket sg-brownfield-coke-analytics-bucket -o yaml | grep -A 5 status
kubectl get bucketclaim -n sg-cosi-coke -o yaml | grep -A 5 status

echo "Press ENTER to request access keys for the claimed bucket..."
read -p ""

# ---
# 3. Developer requests access keys for their claimed bucket
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccess
metadata:
  name: coke-analytics-access
  namespace: sg-cosi-coke
spec:
  bucketClaimName: analytics-bucket-claim
  bucketAccessClassName: sg-cosi-coke-readonly                # Determines tenant group ID based on Helm class parameters in your my-values.yaml
  credentialsSecretName: coke-s3-analytics-bucket-credentials # K8s will inject keys into this Secret
  protocol: s3
EOF

# Show bucket access status and prompt to press ENTER when ready to view credentials
sleep 1
echo "You can verify the bucket access status before proceeding:"
kubectl get bucketaccess -n sg-cosi-coke -o yaml | grep -A 5 status
echo "Press ENTER to view the credentials in the Secret..."
read -p ""
kubectl get secret coke-s3-analytics-bucket-credentials -n sg-cosi-coke -o yaml 

