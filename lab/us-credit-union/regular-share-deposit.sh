#!/usr/bin/env bash
set -euo pipefail

# Synthetic U.S. credit-union lab slice for Apache Fineract.
#
# Proves one bounded invariant:
#   member -> Regular Share -> $1,000 deposit -> balanced GL
#
# This script creates synthetic data only. It is intended for a disposable
# local Fineract development/test environment, never a production tenant.

for command in curl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: required command not found: $command" >&2
    exit 1
  fi
done

FINERACT_BASE_URL="${FINERACT_BASE_URL:-https://localhost:8443}"
FINERACT_API_URL="${FINERACT_API_URL:-${FINERACT_BASE_URL}/fineract-provider/api/v1}"
FINERACT_USERNAME="${FINERACT_USERNAME:-mifos}"
FINERACT_PASSWORD="${FINERACT_PASSWORD:-password}"
FINERACT_TENANT_ID="${FINERACT_TENANT_ID:-default}"
LAB_DATE="${LAB_DATE:-$(date '+%d %B %Y')}"
LAB_AMOUNT="1000"
RUN_ID="${RUN_ID:-$(date '+%s')}"
SHORT_SUFFIX="${RUN_ID: -3}"

api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local args=(
    --silent --show-error --insecure --fail-with-body
    --user "${FINERACT_USERNAME}:${FINERACT_PASSWORD}"
    --header "Fineract-Platform-TenantId: ${FINERACT_TENANT_ID}"
    --header "Content-Type: application/json"
    --request "$method"
  )

  if [[ -n "$body" ]]; then
    args+=(--data "$body")
  fi

  curl "${args[@]}" "${FINERACT_API_URL}/${path}"
}

resource_id() {
  jq -er '.resourceId'
}

create_gl_account() {
  local name="$1"
  local code="$2"
  local type="$3"

  api POST "glaccounts" "$(jq -nc \
    --arg name "$name" \
    --arg code "$code" \
    --argjson type "$type" \
    '{
      name: $name,
      glCode: $code,
      manualEntriesAllowed: false,
      type: $type,
      usage: 1,
      description: "Synthetic Rust Belt FCU proving-ground account"
    }')" | resource_id
}

assert_json() {
  local description="$1"
  local json="$2"
  local expression="$3"

  if ! jq -e "$expression" >/dev/null <<<"$json"; then
    echo "FAIL: $description" >&2
    jq . <<<"$json" >&2
    exit 1
  fi
  echo "PASS: $description"
}

echo "== Rust Belt FCU / Regular Share deposit slice =="
echo "Run ID:   $RUN_ID"
echo "Lab date: $LAB_DATE"
echo "API:      $FINERACT_API_URL"
echo

echo "Checking Fineract health..."
curl --silent --show-error --insecure --fail-with-body \
  "${FINERACT_BASE_URL}/fineract-provider/actuator/health" >/dev/null

echo "Creating synthetic chart of accounts..."
cash_id="$(create_gl_account "RBFCU Cash ${RUN_ID}" "1${RUN_ID}01" 1)"
share_control_id="$(create_gl_account "RBFCU Member Shares Control ${RUN_ID}" "2${RUN_ID}01" 2)"
transfer_suspense_id="$(create_gl_account "RBFCU Transfer Suspense ${RUN_ID}" "2${RUN_ID}02" 2)"
interest_expense_id="$(create_gl_account "RBFCU Share Dividend Expense ${RUN_ID}" "5${RUN_ID}01" 5)"
fee_income_id="$(create_gl_account "RBFCU Fee Income ${RUN_ID}" "4${RUN_ID}01" 4)"

echo "Creating Regular Share product..."
product_response="$(api POST "savingsproducts" "$(jq -nc \
  --arg run "$RUN_ID" \
  --arg short "R${SHORT_SUFFIX}" \
  --argjson cash "$cash_id" \
  --argjson control "$share_control_id" \
  --argjson suspense "$transfer_suspense_id" \
  --argjson interestExpense "$interest_expense_id" \
  --argjson feeIncome "$fee_income_id" \
  '{
    name: ("RBFCU Regular Share " + $run),
    shortName: $short,
    description: "Synthetic U.S. credit-union regular-share proving-ground product",
    currencyCode: "USD",
    digitsAfterDecimal: 2,
    inMultiplesOf: 0,
    nominalAnnualInterestRate: 0,
    interestCompoundingPeriodType: 1,
    interestPostingPeriodType: 4,
    interestCalculationType: 1,
    interestCalculationDaysInYearType: 365,
    minRequiredOpeningBalance: 0,
    withdrawalFeeForTransfers: false,
    allowOverdraft: false,
    accountingRule: 2,
    savingsReferenceAccountId: $cash,
    transfersInSuspenseAccountId: $suspense,
    savingsControlAccountId: $control,
    interestOnSavingsAccountId: $interestExpense,
    incomeFromFeeAccountId: $feeIncome,
    incomeFromPenaltyAccountId: $feeIncome
  }')")"
product_id="$(resource_id <<<"$product_response")"

echo "Creating synthetic member..."
client_response="$(api POST "clients" "$(jq -nc \
  --arg run "$RUN_ID" \
  --arg date "$LAB_DATE" \
  '{
    officeId: 1,
    firstname: "Synthetic",
    lastname: ("Member-" + $run),
    dateFormat: "dd MMMM yyyy",
    locale: "en",
    active: true,
    activationDate: $date,
    submittedOnDate: $date
  }')")"
client_id="$(resource_id <<<"$client_response")"

echo "Opening Regular Share account..."
savings_response="$(api POST "savingsaccounts" "$(jq -nc \
  --argjson client "$client_id" \
  --argjson product "$product_id" \
  --arg date "$LAB_DATE" \
  '{
    clientId: $client,
    productId: $product,
    locale: "en",
    dateFormat: "dd MMMM yyyy",
    submittedOnDate: $date
  }')")"
savings_id="$(resource_id <<<"$savings_response")"

api POST "savingsaccounts/${savings_id}?command=approve" "$(jq -nc \
  --arg date "$LAB_DATE" \
  '{locale:"en", dateFormat:"dd MMMM yyyy", approvedOnDate:$date}')" >/dev/null

api POST "savingsaccounts/${savings_id}?command=activate" "$(jq -nc \
  --arg date "$LAB_DATE" \
  '{locale:"en", dateFormat:"dd MMMM yyyy", activatedOnDate:$date}')" >/dev/null

echo "Posting \$${LAB_AMOUNT} deposit..."
deposit_response="$(api POST "savingsaccounts/${savings_id}/transactions?command=deposit" "$(jq -nc \
  --arg date "$LAB_DATE" \
  --argjson amount "$LAB_AMOUNT" \
  '{
    locale: "en",
    dateFormat: "dd MMMM yyyy",
    transactionDate: $date,
    transactionAmount: $amount
  }')")"
deposit_transaction_id="$(resource_id <<<"$deposit_response")"

echo "Reading member subledger and GL evidence..."
savings_account="$(api GET "savingsaccounts/${savings_id}?associations=transactions")"
journal_response="$(api GET "journalentries?savingsId=${savings_id}&limit=-1")"

assert_json \
  "member share balance is exactly \$${LAB_AMOUNT}" \
  "$savings_account" \
  ".summary.accountBalance == ${LAB_AMOUNT}"

assert_json \
  "portfolio journal is balanced at \$${LAB_AMOUNT}" \
  "$journal_response" \
  "([.pageItems[] | select(.reversed == false and .entryType.id == 2) | .amount] | add // 0) == ${LAB_AMOUNT} and ([.pageItems[] | select(.reversed == false and .entryType.id == 1) | .amount] | add // 0) == ${LAB_AMOUNT}"

assert_json \
  "cash/reference GL receives the \$${LAB_AMOUNT} debit" \
  "$journal_response" \
  "any(.pageItems[]; .reversed == false and .glAccountId == ${cash_id} and .entryType.id == 2 and .amount == ${LAB_AMOUNT})"

assert_json \
  "member-shares control GL receives the \$${LAB_AMOUNT} credit" \
  "$journal_response" \
  "any(.pageItems[]; .reversed == false and .glAccountId == ${share_control_id} and .entryType.id == 1 and .amount == ${LAB_AMOUNT})"

result="$(jq -nc \
  --arg runId "$RUN_ID" \
  --arg date "$LAB_DATE" \
  --argjson clientId "$client_id" \
  --argjson productId "$product_id" \
  --argjson savingsId "$savings_id" \
  --argjson depositTransactionId "$deposit_transaction_id" \
  --argjson cashGlAccountId "$cash_id" \
  --argjson shareControlGlAccountId "$share_control_id" \
  --argjson amount "$LAB_AMOUNT" \
  --argjson journals "$(jq '.pageItems' <<<"$journal_response")" \
  '{
    status: "PASS",
    scenario: "regular-share-deposit",
    runId: $runId,
    labDate: $date,
    clientId: $clientId,
    savingsProductId: $productId,
    savingsId: $savingsId,
    depositTransactionId: $depositTransactionId,
    amount: $amount,
    expectedAccounting: {
      debit: {glAccountId: $cashGlAccountId, amount: $amount},
      credit: {glAccountId: $shareControlGlAccountId, amount: $amount}
    },
    journalEntries: $journals
  }')"

echo
echo "== Reconciliation evidence =="
jq . <<<"$result"
echo
echo "PASS: Regular Share deposit reconciles member subledger to balanced GL."
