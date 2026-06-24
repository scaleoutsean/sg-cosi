# `sg-cosi` examples

Two recommended and tested scenarios include:
- Work with "static" existing bucket - this example uses Bash because we have to patch 
- Create and delete read-only snapshot bucket - this example is a YAML manifest

Assuming you've deployed `sg-cosi` as per the main README and got the details right, you can try either or both of these.

## Brownfield workflow with existing regular bucket 

Create a bucket and set the bucket name as the value of `existingBucketID`. Then run the script while making sure each step has worked. Use `CTRL+C` to stop if you do **not** see `true` next to `bucketReady`, `accessGranted` and similar status updates along the way.

```sh
vim ./examples/brownfield-existing-bucket.sh
bash ./examples/brownfield-existing-bucket.sh
```

As the bucket was pre-existing, no new bucket will be created. But you should see new credentials for it.

```sh
kubectl get secret -n sg-cosi-coke
```

Now edit this file to enter the correct bucket name and then apply.

```sh
vim ./examples/pod-s3-mount-example.yaml
kubectl apply -f ./examples/pod-s3-mount-example.yaml
sleep 15
kubectl logs s3-test-app -n sg-cosi-coke
```

Clean-up:
- if you're expected to empty the bucket you can do it from Kubernetes. Otherwise just release the bucket
- we don't need to delete the `Bucket` object because we haven't created it (this isn't a "greenfield" workflow). Any Tenant Admin may delete the bucket on StorageGRID after it's been Released by COSI

```sh
kubectl delete -f ./examples/pod-s3-mount-example.yaml
kubectl delete bucketAccess coke-analytics-access -n sg-cosi-coke
kubectl delete BucketClaim analytics-bucket-claim -n sg-cosi-coke
kubectl delete BucketAccessClass sg-cosi-coke-readonly
```

StorageGRID Tenant admin's credentials (`sg-tenant-credentials` - see with: `kubectl get secret -n sg-cosi-coke`) remain as they were created when installing COSI for this namespace.

### New regular bucket

`sg-cosi` doesn't enable COSI Greenfield workflow for new regular buckets. A way to run something that resembles it is:  `./examples/greenfield-dynamic-bucket.sh`. This creates a new Bucket but only on Kubernetes, and then you can create that bucket on StorageGRID and continue the same way this Brownfield workflow for existing buckets works. 

After the script finishes, edit `./examples/pod-s3-mount-example.yaml` for your read-only snapshot bucket. Change:
- `BUCKET=` (to use the random new regular bucket name)
- `secretName` (to use `dynamic-s3-credentials`)

Apply this pod to test access to that bucket. Aside from the random bucket name and a different secretName used, this is not different from COSI Browfield workflow.

## Greenfield workflow with new read-only snapshot bucket

Change `sourceBucket` (or create bucket `prod-ml-training-dataset` and put some junk in it) in the manifest file and apply it:

```sh
vim ./examples/greenfield-snapshot-bucket.yaml
kubectl apply -f ./examples/greenfield-snapshot-bucket.yaml
```

That should create a read-only snapshot bucket with S3 credentials. It may take some time for the bucket snapshot to complete and an additional 60-90 seconds for the credentials to be generated. Then you may view the snapshot bucket name and get credentials.

```sh
sleep 90
kubectl get secret my-snapshot-credentials -n sg-cosi-coke -o jsonpath='{.data.BucketInfo}' | base64 -d | jq
```

Edit `./examples/pod-s3-mount-example.yaml` for your read-only snapshot bucket. Change the two lines with:
- `BUCKET=`
- `secretName`

Apply it. Check the pod after 10-15 seconds.

```sh
kubectl apply -f ./examples/pod-s3-mount-example.yaml
sleep 15
kubectl logs s3-test-app -n sg-cosi-coke
```

Clean up:

```sh
kubectl delete -f ./examples/pod-s3-mount-example.yaml
kubectl delete -f ./examples/greenfield-snapshot-bucket.yaml 
# kubectl delete BucketAccess my-snapshot-access -n sg-cosi-coke
# kubectl delete BucketAccessClass sg-cosi-coke-readonly
# kubectl delete BucketClaim my-snapshot-access -n sg-cosi-coke
# kubectl delete BucketClass sg-cosi-coke-default
```

## Clean-up `sg-cosi`

If you want to clean up more than just the examples:

```sh
# Tenant Admin secret 
kubectl get secret -n sg-cosi-coke
# Secrets created by three examples
kubectl delete secret sg-tenant-credentials -n sg-cosi-coke
kubectl delete secret coke-s3-analytics-bucket-credentials  -n sg-cosi-coke
kubectl delete secret dynamic-s3-credentials -n sg-cosi-coke
# BucketAccessClass
kubectl delete BucketAccessClass sg-cosi-coke-readonly
# BucketClaim
kubectl delete BucketClaim analytics-bucket-claim -n sg-cosi-coke
kubectl delete BucketClaim my-greenfield-claim  -n sg-cosi-coke
kubectl delete BucketClaim my-snapshot-claim -n sg-cosi-coke
# BucketClass 
kubectl delete BucketClass sg-cosi-coke-default
kubectl delete BucketClass sg-regular-class
kubectl delete BucketClass sg-ro-snapshot-class 
# Helm uninstall 
helm uninstall sg-cosi-coke -n sg-cosi-coke
# Namespace 
kubectl delete ns sg-cosi-coke 
```