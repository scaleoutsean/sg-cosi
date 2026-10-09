- [FAQs](#faqs)
  - [Technical](#technical)
    - [How to clean up orphaned throw-away `ba-` accounts?](#how-to-clean-up-orphaned-throw-away-ba--accounts)
    - [I can't delete something](#i-cant-delete-something)
    - [Which COSI `bc-` maps to which `ba-` user on SG?](#which-cosi-bc--maps-to-which-ba--user-on-sg)
  - [SGII (StorageGRID Incremental Inventory)](#sgii-storagegrid-incremental-inventory)
    - [What are the use cases for SGII?](#what-are-the-use-cases-for-sgii)
  - [Meta](#meta)
    - [Is this the official NetApp COSI driver?](#is-this-the-official-netapp-cosi-driver)
    - [Where's the source code for `sg-cosi`?](#wheres-the-source-code-for-sg-cosi)

# FAQs

## Technical

### How to clean up orphaned throw-away `ba-` accounts?

- `GET /api/v4/org/users?limit=10000` (Filter for users starting with `ba-`)
- `GET /api/v4/org/users/{id}/s3-access-keys`
- If `expires < time.Now()`, `DELETE /api/v4/org/users/{id}` (which nukes the user and any expired junk keys attached to them)

### I can't delete something

There are scenarios where you'll have to do the usual - patch, force, remove finalizers, etc. One such example is two bucket access claims may point to the same secret, which means only one one them can be deleted. The other will hang. 

```sh
kubectl patch bucketaccess my-coke-access -n sg-cosi-coke --type json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```

### Which COSI `bc-` maps to which `ba-` user on SG?

Since StorageGRID 12.0 won't show you user IDs in the Web UI (you may be able see it in URLs while you use Tenant Web UI), you need to find it yourself (use the API, etc.).

This COSI Driver logs stuff when there's something going on, so collect those logs if you want to get this information from the driver.

```raw
I0618 11:42:15.123456       1 provisioner.go:138] "Successfully granted bucket access" 
k8sBucketId="bc-02d05065-5650-430e-a298-45474922448c" k8sAccessName="coke-analytics-access" 
sgUserId="3928b720-491c-445f-8f4d-ae2cc24b9aff" sgUniqueName="ba-cb5c3aa6"
```

## SGII (StorageGRID Incremental Inventory)

### What are the use cases for SGII?

Where you want to do something with Snapshot Leases, but don't use Kubernetes at all. The first use case for Snapshot Leases was "bucket backup" since a snapshot helps you create a bucket frozen in time. 

SGII uses the same code base to create general stand-alone bucket snapshots and includes tools for common steps related to using Snapshot Leases: SGII can compare one snapshot with its immediate ancestor, for example. 

It's useful for bucket backup the same way Snapshot Leases are, but can be used for more, such as incremental replication and data reconciliation (which is when you're not sure if Elasticsearch has more or less objects than the bucket that it indexes, for example). [See this post](https://scaleoutsean.github.io/2026/10/08/kompromise-storagegrid-instaclustr-opensearch.html) for more.

## Meta

### Is this the official NetApp COSI driver?

No. This is a personal Github account.

As of September 2026, NetApp does not seem to have one, but check their Web site or "contact your NetApp representative".

### Where's the source code for `sg-cosi`?

It's not available.

Why, see [the end of the blog post](https://scaleoutsean.github.io/2026/06/07/cosi-v1alpha1-is-garbage.html#conclusion) about `sg-cosi`: I'm not eager to maintain this driver outside of solutioning and solution development, for which which it works well enough without the hassle of maintaining a public source code repository and getting anything in return. 
