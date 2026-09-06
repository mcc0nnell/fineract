# U.S. Credit Union Proving Ground

This lab asks a bounded question:

> Can stock Apache Fineract model the core financial state of a small U.S. credit union, reconcile its member subledgers to the general ledger, and expose the gaps that would have to be closed before a real U.S. deployment?

This is a **synthetic test environment only**. It is not a production deployment guide, does not use member PII or real money, and does not imply regulatory approval or production readiness.

## Why this lab exists

Fineract already provides substantial banking primitives: savings and fixed-deposit products, lending, accounting mappings, logical business dates, COB processing, reliable external business events, and PostgreSQL support. The experiment is therefore not "can Fineract act like a financial system?" It is:

1. how much of a U.S. credit-union operating model maps directly to stock Fineract;
2. which gaps belong in Fineract extensions;
3. which gaps should remain external integrations; and
4. whether the resulting system can produce auditable reconciliation and NCUA-style reporting evidence.

## Baseline institution

Working name: **Rust Belt FCU**

Initial synthetic scale:

| Metric | Target |
| --- | ---: |
| Assets | $100,000,000 |
| Members | 10,000 |
| Shares and deposits | $85,000,000 |
| Loans | $65,000,000 |
| Net worth | $12,000,000 |
| Other assets/liabilities | Balance to GL |

These values are deliberately synthetic. Later phases may use public NCUA Call Report distributions to generate more realistic portfolios without copying real member-level data.

## Classification

Every requirement gets one of four statuses:

- **DIRECT** — stock Fineract appears to provide the needed primitive; prove it with an executable test.
- **EXTENSION** — likely belongs in a Fineract custom module or U.S.-specific service close to the core.
- **EXTERNAL** — should remain outside the core and integrate through APIs/events.
- **OPEN** — not enough evidence yet; inspect code/API behavior before deciding.

The table below is a starting hypothesis, not a claim of production suitability.

## Initial fit/gap matrix

| U.S. CU capability | Initial status | Fineract primitive / hypothesis | Proof required |
| --- | --- | --- | --- |
| Individual member/client record | DIRECT | Client domain | Create, update, deactivate, audit |
| Branch / office hierarchy | DIRECT | Office/branch domain | Multiple branches and member assignment |
| Regular share account | DIRECT | Savings product/account | Deposit, withdrawal, interest/dividend posting, GL |
| Minimum opening/member share | DIRECT / EXTENSION | Savings minimum opening balance exists; membership enforcement may need policy | Prove required-share lifecycle and account closure behavior |
| Savings dividends / interest | DIRECT | Savings interest posting and calculation | Daily balance, average daily balance, monthly/quarterly posting |
| Share overdraft | DIRECT | Savings overdraft controls | Limits, fees, accounting, reversal |
| Certificate / term share | DIRECT | Fixed deposit | Open, accrue, mature, early close, GL |
| Share draft / checking semantics | OPEN | Savings may supply ledger primitive; U.S. transaction semantics may be external/extension | Checks, holds, NSF, stop pay, clearing, statement behavior |
| Joint owners / POD beneficiaries | OPEN | Relationship model requires code/API review | Ownership rights, survivorship metadata, access control |
| Consumer auto loan | DIRECT | Loan product/account | Originate, approve, disburse, repay, reverse, delinquency |
| Unsecured personal loan | DIRECT | Loan product/account | Full lifecycle and accounting |
| Loan fees and penalties | DIRECT | Charge framework | Assessment, waiver, payment, GL |
| Delinquency processing | DIRECT | Loan delinquency + COB machinery | Aging, missed payments, catch-up COB |
| General ledger | DIRECT | Accounting module and product GL mappings | Balanced journal entries and control accounts |
| Reversals | DIRECT | Transaction reversal workflows | Reverse after posting and reconcile |
| Logical business date | DIRECT | Business Date | Advance independently of wall clock |
| Close of Business | DIRECT | COB module | Multi-day catch-up and failure recovery |
| Reliable business events | DIRECT | External event framework, Avro, idempotency key | Produce, fail delivery, retry, de-duplicate |
| ACH origination/receipt | EXTERNAL | Payment rail is downstream responsibility | Adapter + idempotent posting + returns/reversals |
| FedNow / RTP | EXTERNAL | Real-time rail is downstream responsibility | Adapter + 24x7 posting/reconciliation model |
| Debit/credit card processing | EXTERNAL | Processor integration | Authorizations/settlement mapped to ledger |
| BSA/AML / OFAC | EXTERNAL | Compliance service boundary | Event/API integration and case evidence |
| Member-facing digital banking | EXTERNAL | Fineract threat model treats direct self-service as out of core scope | BFF/IAM/API-gateway pattern |
| NCUA 5300 Call Report output | EXTENSION | NCUA publishes import schemas/account descriptions | GL-to-NCUA mapping, validation, XML generation |
| NCUA Profile / operational reporting | EXTENSION / EXTERNAL | Separate CUOnline/Profile data domain | Define ownership and export boundary |
| Legacy-core conversion | EXTERNAL | Migration factory around Fineract APIs/DB-approved interfaces | Extract, transform, validate, load, reconcile |
| Daily reconciliation | EXTENSION | Cross-cutting evidence layer | Subledgers = control accounts = GL = reporting taxonomy |
| Tamper-evident audit evidence | EXTERNAL / EXTENSION | Core audit exists; threat model disclaims tamper resistance | Append-only/cryptographic evidence layer |
| Rate limiting / edge protection | EXTERNAL | Explicit downstream responsibility | API gateway/WAF tests |
| Encryption at rest | EXTERNAL | Explicit downstream/storage responsibility | Storage/KMS controls and recovery tests |

## First acceptance test

The first milestone is intentionally narrow:

> **A synthetic $100M credit union closes a business day with balanced books.**

Minimum scenario:

1. Create one head office and synthetic members.
2. Create a chart of accounts sufficient for cash, member shares, loan portfolio, accrued interest, income, expenses, and net worth.
3. Create a regular-share product and an auto-loan product with accounting mappings.
4. Open share accounts and post deposits.
5. Originate, approve, and disburse loans.
6. Post repayments and at least one reversal.
7. Advance Business Date.
8. Run COB.
9. Reconcile:
   - total member share balances to the savings control GL;
   - total loan principal to the loan portfolio GL;
   - journal debits to journal credits;
   - assets to liabilities + net worth.
10. Emit a machine-readable reconciliation result.

The test passes only if the evidence is reproducible from a clean environment.

## NCUA reporting target

NCUA's CUOnline supports importing Call Report data from external sources using the cycle-specific XML schema and publishes Account Descriptions for software vendors. That gives the lab an authoritative reporting target without pretending Fineract itself should become CUOnline.

Initial pipeline hypothesis:

```text
Fineract subledgers
        |
        v
Fineract GL
        |
        v
U.S. CU reporting taxonomy
        |
        v
NCUA account-code mapper
        |
        v
schema validation
        |
        v
synthetic 5300 XML
```

We should start against the current NCUA schema for the active cycle, but keep mappings versioned by reporting cycle because account descriptions and schemas can change.

## Security boundary

The repository threat model is authoritative for Fineract itself. This lab must not report expected downstream responsibilities as Fineract vulnerabilities.

In particular, the current threat model explicitly places the following outside core guarantees or as downstream responsibilities:

- direct internet exposure without a reverse proxy/WAF;
- rate limiting and DDoS protection;
- encryption at rest;
- direct member self-service;
- external real-time payment rails;
- tamper-resistant audit storage.

The lab should test these boundaries as **deployment controls**, not misclassify them as core security findings.

## Failure cases to add after the first green close

- duplicate deposit/payment request;
- duplicate external event delivery;
- transaction reversal after reconciliation;
- Fineract restart during COB;
- PostgreSQL interruption during a posting workflow;
- skipped business dates followed by COB catch-up;
- malformed migration record;
- mismatched control-account balance;
- stale or duplicate payment-rail message;
- restore from backup followed by reconciliation.

## Deliverables

1. Fit/gap matrix with executable evidence links.
2. Synthetic institution seed data.
3. Reconciliation command/test suite.
4. Versioned NCUA reporting mapper prototype.
5. Failure-injection scenarios and results.
6. Security/assurance baseline aligned to `SECURITY.md`.
7. Candidate upstream issues/PRs where findings are genuinely Fineract-core concerns.

## Sources

- Apache Fineract 1.15 documentation: https://fineract.apache.org/docs/stable/
- Apache Fineract threat model: ../../SECURITY.md
- NCUA CUOnline / software-vendor schema information: https://ncua.gov/regulation-supervision/regulatory-reporting/cuonline
- NCUA Call Report data and account descriptions: https://ncua.gov/analysis/credit-union-corporate-call-report-data

## Next build slice

Implement the smallest executable scenario that proves this chain:

```text
member
  -> regular share account
  -> $1,000 deposit
  -> savings-control GL entry
  -> balanced journal
  -> reconciliation assertion
```

Then add the first loan and repeat the assertion through disbursement and repayment.
