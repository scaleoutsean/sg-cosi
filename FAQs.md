- [FAQs](#faqs)
  - [Technical](#technical)
    - [How to clean up orphaned throw-away `ba-` accounts?](#how-to-clean-up-orphaned-throw-away-ba--accounts)
    - [I can't delete something](#i-cant-delete-something)
    - [Which COSI `bc-` maps to which `ba-` user on SG?](#which-cosi-bc--maps-to-which-ba--user-on-sg)
  - [Meta](#meta)
    - [Where's the source code?](#wheres-the-source-code)

# FAQs

## Technical

### How to clean up orphaned throw-away `ba-` accounts?

- `GET /api/v4/org/users?limit=10000` (Filter for users starting with `ba-`)
- `GET /api/v4/org/users/{id}/s3-access-keys`
- If `expires < time.Now()`, `DELETE /api/v4/org/users/{id}` (Which nukes the user and any expired junk keys attached to them)

### I can't delete something

There are scenarios where you'll have to do the usual - patch, force, remove finalizers, etc. One such example is two bucket access claims may point to the same secret, which means only one one them can be deleted. The other will hang. 

```sh
kubectl patch bucketaccess my-coke-access -n sg-cosi-coke --type json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```

### Which COSI `bc-` maps to which `ba-` user on SG?

Since StorageGRID 12.0 won't show you user IDs in the Web UI, you need to find it yourself (use the API, etc.). "Contact your NetApp representative."

This COSI Driver logs stuff when there's something going on.

```raw
I0618 11:42:15.123456       1 provisioner.go:138] "Successfully granted bucket access" 
k8sBucketId="bc-02d05065-5650-430e-a298-45474922448c" k8sAccessName="coke-analytics-access" 
sgUserId="3928b720-491c-445f-8f4d-ae2cc24b9aff" sgUniqueName="ba-cb5c3aa6"
```

## Meta

### Where's the source code?

It's not available. Why, see [the end of the blog post](https://scaleoutsean.github.io/2026/06/07/cosi-v1alpha1-is-garbage.html#conclusion) about `sg-cosi`. I'm not eager to maintain this driver outside of what I might need it for myself (occasional solutioning and solution development).
