// Deterministic tests — `baml test` runs these offline, no API keys needed.
// The last case exercises parse_expense's *parsing* path against a captured
// model reply via the compiler-synthesized parse_expense$parse companion.

testset "check_policy" {
    test "small meal approved" {
        let d = check_policy(12.0, "USD", Category.Meals);
        assert.equal(d.status, "approved");
        assert.equal(d.over_by, 0.0);
    }

    test "needs receipt over 25" {
        let d = check_policy(42.0, "USD", Category.Meals);
        assert.equal(d.status, "needs_receipt");
        assert.equal(d.over_by, 0.0);
    }

    test "over category limit needs approval" {
        let d = check_policy(120.0, "USD", Category.Meals);
        assert.equal(d.status, "needs_approval");
        assert.equal(d.over_by, 45.0);
    }

    test "non usd needs approval" {
        let d = check_policy(10.0, "EUR", Category.Meals);
        assert.equal(d.status, "needs_approval");
    }

    test "rejects non positive amounts" {
        let d = check_policy(0.0, "USD", Category.Other);
        assert.equal(d.status, "rejected");
    }
}

testset "parse_expense_fixture" {
    test "decodes a captured reply" {
        let raw = #"{"merchant":"Uber","amount":23.5,"currency":"USD","category":"Travel","expense_date":"tue","notes":"ride to airport"}"#;
        let e = parse_expense$parse(raw);
        assert.equal(e.merchant, "Uber");
        assert.equal(e.category, Category.Travel);
        assert.equal(e.amount, 23.5);
    }
}
