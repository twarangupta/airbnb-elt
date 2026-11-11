# AWS setup (S3 landing zone and IAM)

You do these steps yourself in the AWS console. Account sign-up, passwords and access keys are yours to enter; never paste them into code, chat or git.

What we create, and who uses it:

| Thing | Name (suggested) | Used by | Phase |
|---|---|---|---|
| S3 bucket | `airbnb-elt-raw-<your-initials>-<4 random digits>` | everything | 1 |
| IAM policy | `airbnb-elt-landing-write` (file: `iam_policy_landing_write.json`) | the landing script on your laptop | 1 |
| IAM user | `airbnb-elt-lander` (no console access, one access key) | the landing script on your laptop | 1 |
| IAM policy | `airbnb-elt-snowflake-read` (file: `iam_policy_snowflake_read.json`) | Snowflake | 2 |
| IAM role | `airbnb-elt-snowflake-role` (trust policy: `iam_trust_policy_snowflake.template.json`) | Snowflake, through the storage integration | 2 |

Two separate identities on purpose: the laptop can write but Snowflake can only read. Neither can delete. That is least privilege: each identity gets only what its job needs.

## Step 1. Pick one region and use it everywhere

Pick the AWS region first, then later create the Snowflake trial in the SAME cloud (AWS) and SAME region. If S3 and Snowflake are in different regions, every COPY INTO pulls data across regions and AWS charges data transfer. Suggested: `us-east-1` (N. Virginia), which has the widest Snowflake feature coverage. Any region is fine as long as both match. Write your choice into `.env` as `AWS_REGION`.

## Step 2. Cost guard before anything else

1. Billing and Cost Management, Budgets, Create budget, "Zero spend budget" (or a monthly cost budget of 1 USD) with an email alert.
2. Check the free tier terms shown for your account (AWS changed its free tier for new accounts in 2025; it is now credit based). Our data is a few hundred MB, so S3 storage costs cents at most.

## Step 3. Create the bucket

S3, Create bucket:

- Bucket name: `airbnb-elt-raw-<your-initials>-<4 random digits>` (bucket names are global across all AWS customers, so it must be unique). Put it in `.env` as `S3_BUCKET`.
- Region: the one from step 1.
- Object Ownership: ACLs disabled (default).
- Block all public access: ON (default). Nobody on the internet should read this bucket.
- Bucket Versioning: Enable. If a file is ever overwritten by mistake, the old version is still there.
- Default encryption: SSE-S3 (default).

Folder layout we will use from Phase 1 (folders are just key prefixes in S3):

```
s3://<bucket>/raw/<city>/snapshot_date=YYYY-MM-DD/listings.csv.gz
s3://<bucket>/raw/<city>/snapshot_date=YYYY-MM-DD/reviews.csv.gz
s3://<bucket>/raw/<city>/snapshot_date=YYYY-MM-DD/calendar.csv.gz
```

## Step 4. Landing policy and user (needed for Phase 1)

1. IAM, Policies, Create policy, JSON tab. Paste `iam_policy_landing_write.json`, replace both `BUCKET_NAME` with your bucket name. Name it `airbnb-elt-landing-write`.
2. IAM, Users, Create user `airbnb-elt-lander`. Do NOT tick console access. Attach only the policy above.
3. Open the user, Security credentials, Create access key, use case "Local code". Download the CSV once.
4. Store the key in your AWS credentials file, not in the repo. Either install AWS CLI v2 and run `aws configure --profile airbnb-elt-lander`, or create `%USERPROFILE%\.aws\credentials` by hand:

```
[airbnb-elt-lander]
aws_access_key_id = <yours>
aws_secret_access_key = <yours>
```

The landing script reads `AWS_PROFILE=airbnb-elt-lander` from `.env` and boto3 finds the key itself.

## Step 5. Snowflake read policy and role (do this in Phase 2, not now)

This needs two values that only exist after the Snowflake trial is active and the storage integration is created (`DESC INTEGRATION` shows them). Phase 2 walks through it:

1. Create policy `airbnb-elt-snowflake-read` from `iam_policy_snowflake_read.json` (replace `BUCKET_NAME`).
2. Create role `airbnb-elt-snowflake-role`, trusted entity "AWS account", attach that policy. Copy its ARN.
3. In Snowflake: `CREATE STORAGE INTEGRATION ... STORAGE_AWS_ROLE_ARN = '<that ARN>'`, then `DESC INTEGRATION`.
4. Back in AWS, edit the role's trust policy using `iam_trust_policy_snowflake.template.json`, filling in `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` from step 3.
