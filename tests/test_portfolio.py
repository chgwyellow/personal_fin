from typing import cast

import pytest

from src.portfolio import (
    calculate_holding_metrics,
    calculate_portfolio_totals,
    get_portfolio_details,
    get_portfolio_summary,
)


def test_calculate_holding_metrics() -> None:
    """Test metrics calculation for one holding."""
    result = calculate_holding_metrics(
        shares=10,
        total_cost=1000,
        market_price=120,
    )

    assert result["average_cost"] == 100
    assert result["market_value"] == 1200
    assert result["capital_gain_or_loss"] == 200
    assert result["total_gain_or_loss"] == 200


def test_calculate_portfolio_totals() -> None:
    """Test totals calculation for multiple holdings."""
    holding_1 = calculate_holding_metrics(10, 1000, 120)
    holding_2 = calculate_holding_metrics(5, 2000, 450)

    result = calculate_portfolio_totals([holding_1, holding_2])

    assert result["total_cost"] == 3000
    assert result["total_market_value"] == 3450
    assert result["total_capital_gain_or_loss"] == 450
    assert result["total_gain_or_loss"] == 450


def test_get_portfolio_details(monkeypatch) -> None:
    """Test calculating metrics for holdings returned from the database."""
    stored_holdings = [
        (1, 1, "TEST1", "Test One", "TW", "NTD", 10, 1000),
        (2, 2, "TEST2", "Test Two", "TW", "NTD", 5, 2000),
    ]
    monkeypatch.setattr("src.portfolio.list_holdings", lambda: stored_holdings)

    result = get_portfolio_details({"TEST1": 120, "TEST2": 450})

    assert result[0]["symbol"] == "TEST1"
    assert result[0]["dividend_total"] == 0
    metrics_1 = cast(dict[str, int | float | None], result[0]["metrics"])
    metrics_2 = cast(dict[str, int | float | None], result[1]["metrics"])
    assert metrics_1["market_value"] == 1200
    assert result[1]["symbol"] == "TEST2"
    assert result[1]["dividend_total"] == 0
    assert metrics_2["market_value"] == 2250


def test_get_portfolio_summary(monkeypatch) -> None:
    """Test calculating totals from holdings returned from the database."""
    stored_holdings = [
        (1, 1, "TEST1", "Test One", "TW", "NTD", 10, 1000),
        (2, 2, "TEST2", "Test Two", "TW", "NTD", 5, 2000),
    ]
    monkeypatch.setattr("src.portfolio.list_holdings", lambda: stored_holdings)

    result = get_portfolio_summary({"TEST1": 120, "TEST2": 450})

    assert result == {
        "total_cost": 3000,
        "total_market_value": 3450,
        "total_capital_gain_or_loss": 450,
        "total_gain_or_loss": 450,
    }


def test_get_portfolio_details_with_dividends(monkeypatch) -> None:
    """Test that dividends are included in holding metrics."""
    stored_holdings = [
        (1, 1, "TEST1", "Test One", "TW", "NTD", 10, 1000),
    ]
    monkeypatch.setattr("src.portfolio.list_holdings", lambda: stored_holdings)
    monkeypatch.setattr(
        "src.portfolio.get_total_dividends_by_holding",
        lambda holding_id: 50,
    )

    result = get_portfolio_details({"TEST1": 120})
    metrics = cast(dict[str, int | float | None], result[0]["metrics"])

    assert result[0]["dividend_total"] == 50
    assert metrics["total_gain_or_loss"] == 250


def test_get_portfolio_details_with_missing_price(monkeypatch) -> None:
    """Test that a missing market price raises KeyError."""
    stored_holdings = [
        (1, 1, "TEST1", "Test One", "TW", "NTD", 10, 1000),
    ]
    monkeypatch.setattr("src.portfolio.list_holdings", lambda: stored_holdings)

    with pytest.raises(KeyError):
        get_portfolio_details({})
