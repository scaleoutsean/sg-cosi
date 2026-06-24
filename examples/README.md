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

Apply this pod to test access to that bucket. Aside from the random bucket name and a different secretName used, this is not different from COSI Brownfield workflow.

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

Edit `./examples/pod-s3-mount-example.yaml` for your read-only snapshot bucket. Change values in the two lines with:
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
```

## Refine access within a bucket

COSI doesn't create or modify bucket ACLs, it only uses `bucketAccessClass`es it's given to work with. See `values.yaml` in Helm chart.

You may create different user groups in the StorageGRID Tenant and specify a different `tenantGroupId` in `bucketAccessClass` that appears in these examples (there's a placeholder in read-only snapshot example) to make use of it.

## Clean-up `sg-cosi`

If you want to clean up more than just the examples, delete everything. Note that orderly deletion may be slow (as in: minutes).

```sh
# Delete Pods mounting the S3 keys
kubectl delete pod s3-test-app -n sg-cosi-coke
# Delete BucketAccess objects (This triggers the driver to successfully delete users off StorageGRID)
kubectl delete bucketaccessclass sg-cosi-coke-reporting 
kubectl delete bucketaccess coke-analytics-access -n sg-cosi-coke
kubectl delete bucketaccess my-greenfield-access -n sg-cosi-coke
kubectl delete bucketaccess my-snapshot-access -n sg-cosi-coke
# Delete BucketClaim objects
kubectl delete bucketclaim analytics-bucket-claim -n sg-cosi-coke
kubectl delete bucketclaim my-greenfield-claim -n sg-cosi-coke
kubectl delete bucketclaim my-snapshot-claim -n sg-cosi-coke
# Delete Bucket objects
kubectl delete bucketaccessclass sg-cosi-coke-default 
kubectl delete bucketaccessclass sg-regular-class
# Delete isolated BucketAccessClass / BucketClass objects (from examples, not "global" from the Helm chart)
kubectl delete BucketAccessClass sg-cosi-coke-snapshot-readonly
kubectl delete bucketclass sg-cosi-coke-default
kubectl delete bucketclass sg-regular-class
kubectl delete bucketclass sg-ro-snapshot-class
# Uninstall the Driver Chart (will also remove BucketAccessClass from Helm chart, sg-cosi-coke-readonly)
helm uninstall sg-cosi-coke -n sg-cosi-coke
# Uninstall the Tenant credentials 
kubectl delete secret sg-tenant-credentials -n sg-cosi-coke
# Remove the namespace 
kubectl delete ns sg-cosi-coke 
```