# U.S. Credit Union Lab Runbook

This runbook executes the first proving-ground slice against a disposable local Apache Fineract environment.

## Prerequisites

- Java 21
- Docker with Compose
- `curl`
- `jq`

The repository's container configuration is for development/testing only. Do not use this lab configuration for production or real member data.

## 1. Build the local Fineract image

From the repository root:

```bash
./gradlew :fineract-provider:jibDockerBuild -x test
```

## 2. Start the documented development stack

```bash
docker compose -f docker-compose-development.yml up -d
```

Wait until this returns a healthy response:

```bash
curl -k https://localhost:8443/fineract-provider/actuator/health
```

Expected shape:

```json
{"status":"UP"}
```

## 3. Run the first banking invariant

```bash
bash lab/us-credit-union/regular-share-deposit.sh
```

The script uses the same default E2E credentials as the repository test configuration:

```text
username: mifos
password: password
tenant:   default
```

Override them if needed:

```bash
FINERACT_USERNAME=... \
FINERACT_PASSWORD=... \
FINERACT_TENANT_ID=... \
bash lab/us-credit-union/regular-share-deposit.sh
```

You can also override the base URL or transaction date:

```bash
FINERACT_BASE_URL=https://localhost:8443 \
LAB_DATE="05 September 2026" \
bash lab/us-credit-union/regular-share-deposit.sh
```

## What the script creates

Every run uses unique synthetic names/codes and creates:

1. a cash/reference asset GL account;
2. a member-shares control liability GL account;
3. a transfer-suspense liability GL account;
4. a share-dividend expense GL account;
5. a fee-income GL account;
6. a cash-accounted Regular Share savings product;
7. one active synthetic member;
8. one approved and active savings account;
9. one $1,000 deposit.

No cleanup is attempted because a transaction-bearing banking account should be treated as evidence, not silently deleted.

## Pass criteria

The script exits non-zero unless all four assertions hold:

```text
member subledger balance       = $1,000
system-generated GL debits     = $1,000
system-generated GL credits    = $1,000
cash/reference GL              has $1,000 debit
member-shares control GL       has $1,000 credit
```

The final JSON block includes the created IDs and journal entries so the run can be inspected independently.

## Accounting expectation

A member deposit increases the credit union's cash and increases its liability to the member:

```text
Dr Cash / Savings Reference       $1,000
    Cr Member Shares Control      $1,000
```

That is the first U.S.-credit-union invariant this lab proves.

## Resetting the lab

For a truly clean rerun, destroy the disposable development environment and its volumes, then recreate it using the repository's documented Docker workflow. Do not use a reset procedure against any environment containing data you need to retain.

## Next slice

Once the deposit test is green:

```text
member
  -> auto-loan product
  -> application
  -> approval
  -> disbursement
  -> repayment
  -> reversal
  -> loan-control GL reconciliation
```

After both deposit and loan subledgers reconcile, add Business Date and COB.
