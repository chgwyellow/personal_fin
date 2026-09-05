from src.liabilities import (
    create_liability,
    get_liability,
    update_liability,
    delete_liability,
)

# 1. create a liability
liability_id = create_liability(
    name="test_liability",
    liability_group="short_term",
    category="loan",
    currency="NTD",
    balance=1000,
)

print("Created liabilities: ", liability_id)

# 2. Query liability
liability = get_liability(liability_id=liability_id)

print("Specific liability: ", liability)

# 3. Update liability
updated = update_liability(liability_id=liability_id, currency="NTD", balance=2000)

print("Updated balance: ", updated)

# 4. Delete liability
deleted = delete_liability(liability_id=liability_id)

print("Deleted liability: ", deleted)

# 5. Query again
liability = get_liability(liability_id=liability_id)

print("Specific liability: ", liability)

# 6. update and delete again
updated = update_liability(liability_id=liability_id, currency="NTD", balance=2000)

print("Updated balance: ", updated)

deleted = delete_liability(liability_id=liability_id)

print("Deleted liability: ", deleted)
