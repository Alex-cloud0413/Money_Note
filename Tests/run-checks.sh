#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/moneynote-checks.XXXXXX)"
check_arch="$(uname -m)"
model_files=(Transaction.swift Category.swift AccountModel.swift BudgetModel.swift SubscriptionModel.swift)
legacy=(); current=()
for file in "${model_files[@]}"; do
  legacy+=("$project_dir/Tests/LegacyModels/$file")
  current+=("$project_dir/MoneyNote/$file")
done
swiftc -parse-as-library -module-name MoneyNote -target "${check_arch}-apple-macosx14.0" "${legacy[@]}" "$project_dir/Tests/LegacyStore.swift" -o "$check_dir/legacy"
swiftc -parse-as-library -module-name MoneyNote -target "${check_arch}-apple-macosx14.0" "${current[@]}" "$project_dir/MoneyNote/LedgerModel.swift" "$project_dir/MoneyNote/InstallmentPlan.swift" "$project_dir/MoneyNote/SubscriptionEngine.swift" "$project_dir/Tests/MigrationChecks.swift" -o "$check_dir/current"
"$check_dir/legacy" "$check_dir/default.store"
"$check_dir/current" "$check_dir/default.store"
"$check_dir/current" "$check_dir/default.store" --reopen
