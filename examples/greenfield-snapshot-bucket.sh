#!/usr/bin/env bash 

# GREENFIELD SNAPSHOT EXAMPLE (recommended for analytics and reporting based on temporary bucket snapshots, i.e. "read-only clone-buckets")

# This example provisions an ephemeral, read-only clone (snapshot) of an existing
# StorageGRID bucket dynamically via Kubernetes COSI.
# Because the snapshot is read-only, it resists data modification and is safely 
# disposable upon deletion of the BucketClaim.

echo "If you change details, make sure you change them throughout the script rather than in just one place."
echo "Press CTRL+C to stop the script if you see a step did not work out. Fix the problem, delete the resources manually, then complete the rest manually."
sleep 2

# 1. Cluster Administrator defines a specialized BucketClass for Snapshots

cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClass
metadata:
  name: sg-ro-snapshot-class
driverName: sg.cosi.coke
deletionPolicy: Delete   # Thanks to read-only snapshot, Delete is fast and trivial workload-wise
parameters:
  bucketType: "snapshot"
  accessLevel: "readOnly"
  sourceBucket: "prod-ml-training-dataset" # The name of the existing StorageGRID bucket to clone
  # beforeTime: "2026-06-12T07:59:00.000Z" # Optional: Issue a Point-In-Time (PIT) clone at this exact ISO8601 UTC timestamp. Current-time if omitted.
EOF

# Show BucketClass status
kubectl get bucketclass sg-ro-snapshot-class -o yaml | grep -A 5 status
# Prompt to press ENTER when ready to create the snapshot BucketClaim
read -p "Press ENTER to create the snapshot BucketClaim..."

# 2. Developer dynamically requests a snapshot of the source bucket
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClaim
metadata:
  name: my-snapshot-claim
  namespace: sg-cosi-coke 
spec:
  bucketClassName: sg-ro-snapshot-class
  protocols:
    - s3
  # No existingBucketName is provided, triggering Greenfield mode.
EOF

# Show BucketClaim status
kubectl get bucketclaim my-snapshot-claim -n sg-cosi-coke -o yaml | grep -A 5 status
# Prompt to press ENTER when ready to create the BucketAccess
read -p "Press ENTER to create the BucketAccess..."

# 3. Cluster Administrator defines a strictly tailored BucketAccessClass to issue access keys
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccessClass
metadata:
  name: sg-cosi-readonly
driverName: sg.cosi.coke
authenticationType: Key
parameters:
  validDays: "1"
EOF

# Show BucketAccessClass status
kubectl get bucketaccessclass sg-cosi-readonly -o yaml | grep -A 5 status
# Prompt to press ENTER when ready to request access keys
read -p "Press ENTER to request access keys for the snapshot claim..."

# 4. Developer requests access keys for their snapshot partition
cat <<EOF | kubectl apply -f -
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccess
metadata:
  name: my-snapshot-access
  namespace: sg-cosi-coke # change to namespace where COSI driver is used
spec:
  bucketClaimName: my-snapshot-claim
  # Important: The Access class must match the ReadOnly expectations to enforce defense-in-depth
  bucketAccessClassName: sg-cosi-readonly 
  credentialsSecretName: my-snapshot-credentials
  protocol: s3
EOF

# Show bucket access status and prompt to press ENTER when ready to view credentials
sleep 1
echo "You can verify the bucket access status before proceeding:"
kubectl get bucketaccess -n sg-cosi-coke -o yaml | grep -A 5 status
echo "Press ENTER to view the credentials in the Secret..."
read -p ""
kubectl get secret my-snapshot-credentials -n sg-cosi-coke -o yaml
