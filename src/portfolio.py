def calculate_average_cost(
    total_cost: int | float,
    shares: int | float,
) -> float | None:
    """Calculate the average cost per share or unit.

    Args:
        total_cost: Total investment cost in the security's original currency.
        shares: Number of shares or units held.

    Returns:
        Average cost per share or unit.
        Returns None when shares are zero.
    """
    if shares == 0:
        return None

    return total_cost / shares


def calculate_market_value(
    shares: int | float,
    market_price: int | float,
) -> int | float:
    """Calculate the current market value of a holding.

    Args:
        shares: Number of shares or units held.
        market_price: Current price per share or unit in the original currency.

    Returns:
        Current market value in the security's original currency.
    """

    return shares * market_price


def calculate_capital_gain_loss(
    market_value: int | float,
    total_cost: int | float,
) -> int | float:
    """Calculate capital gain or loss before dividends.

    Args:
        market_value: Current market value in the original currency.
        total_cost: Total investment cost in the original currency.

    Returns:
        Capital gain or loss in the original currency.
    """

    return market_value - total_cost


def calculate_capital_return_rate(
    capital_gain_loss: int | float,
    total_cost: int | float,
) -> float | None:
    """Calculate the return rate from capital gain or loss.

    Args:
        capital_gain_loss: Capital gain or loss in the original currency.
        total_cost: Total investment cost in the original currency.

    Returns:
        Capital gain or loss divided by total cost.
        Returns None when total cost is zero.
    """
    if total_cost == 0:
        return None

    return capital_gain_loss / total_cost


def calculate_total_gain_loss(
    capital_gain_loss: int | float,
    dividend_total: int | float,
) -> int | float:
    """Calculate total gain or loss including dividends.

    Args:
        capital_gain_loss: Capital gain or loss in the original currency.
        dividend_total: Total dividends in the original currency.

    Returns:
        Total gain or loss in the original currency.
    """

    return capital_gain_loss + dividend_total


def calculate_total_return_rate(
    total_gain_loss: int | float,
    total_cost: int | float,
) -> float | None:
    """Calculate the total return rate including dividends.

    Args:
        total_gain_loss: Total gain or loss in the original currency.
        total_cost: Total investment cost in the original currency.

    Returns:
        Total gain or loss divided by total cost.
        Returns None when total cost is zero.
    """

    if total_cost == 0:
        return None

    return total_gain_loss / total_cost


def calculate_portfolio_weight(
    market_value: int | float,
    total_portfolio_value: int | float,
) -> float | None:
    """Calculate a holding's share of the total portfolio value.

    Args:
        market_value: Current holding value in the original currency.
        total_portfolio_value: Total portfolio value in the same currency.

    Returns:
        Holding market value divided by total portfolio value.
        Returns None when total portfolio value is zero.
    """
    if total_portfolio_value == 0:
        return None

    return market_value / total_portfolio_value


def calculate_holding_metrics(
    shares: int | float,
    total_cost: int | float,
    market_price: int | float,
    dividend_total: int | float = 0,
) -> dict[str, int | float | None]:
    """Calculate all metrics for one investment holding.

    Args:
        shares: Number of shares or units held.
        total_cost: Total investment cost in the original currency.
        market_price: Current price per share or unit.
        dividend_total: Total dividends in the original currency.

    Returns:
        A dictionary containing average cost, market value, capital gain or
        loss, capital return rate, total gain or loss, and total return rate.
    """
    average_cost = calculate_average_cost(total_cost, shares)
    market_value = calculate_market_value(shares, market_price)
    capital_gain_or_loss = calculate_capital_gain_loss(market_value, total_cost)
    capital_return_rate = calculate_capital_return_rate(
        capital_gain_or_loss,
        total_cost,
    )
    total_gain_or_loss = calculate_total_gain_loss(
        capital_gain_or_loss,
        dividend_total,
    )
    total_return_rate = calculate_total_return_rate(
        total_gain_or_loss,
        total_cost,
    )

    return {
        "average_cost": average_cost,
        "market_value": market_value,
        "capital_gain_or_loss": capital_gain_or_loss,
        "capital_return_rate": capital_return_rate,
        "total_gain_or_loss": total_gain_or_loss,
        "total_return_rate": total_return_rate,
    }
