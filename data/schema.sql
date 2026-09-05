-- Personal Finance — initial SQLite schema
-- All timestamps are stored as ISO-8601 text and interpreted in Asia/Taipei.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS assets (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    asset_group TEXT NOT NULL CHECK (
        asset_group IN ('liquid_asset', 'liquid_investment', 'other_asset')
    ),
    category TEXT NOT NULL,
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    value NUMERIC NOT NULL DEFAULT 0 CHECK (value >= 0),
    notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS holdings (
    id INTEGER PRIMARY KEY,
    asset_id INTEGER NOT NULL UNIQUE,
    symbol TEXT NOT NULL,
    security_name TEXT NOT NULL,
    market TEXT NOT NULL CHECK (market IN ('TW', 'US')),
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    shares NUMERIC NOT NULL DEFAULT 0 CHECK (shares >= 0),
    total_cost NUMERIC NOT NULL DEFAULT 0 CHECK (total_cost >= 0),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS recurring_investments (
    id INTEGER PRIMARY KEY,
    holding_id INTEGER NOT NULL,
    planned_amount NUMERIC NOT NULL CHECK (planned_amount > 0),
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    frequency TEXT NOT NULL,
    execution_day INTEGER NOT NULL CHECK (execution_day BETWEEN 1 AND 31),
    start_date TEXT NOT NULL,
    end_date TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    notes TEXT,
    FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE,
    CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS recurring_investment_executions (
    id INTEGER PRIMARY KEY,
    recurring_investment_id INTEGER,
    holding_id INTEGER NOT NULL,
    execution_date TEXT NOT NULL,
    invested_amount NUMERIC NOT NULL CHECK (invested_amount > 0),
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    shares_purchased NUMERIC NOT NULL CHECK (shares_purchased > 0),
    purchase_price NUMERIC NOT NULL CHECK (purchase_price > 0),
    status TEXT NOT NULL DEFAULT 'confirmed' CHECK (
        status IN ('confirmed', 'reversed', 'cancelled')
    ),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    FOREIGN KEY (recurring_investment_id)
        REFERENCES recurring_investments(id) ON DELETE SET NULL,
    FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dividends (
    id INTEGER PRIMARY KEY,
    holding_id INTEGER NOT NULL,
    received_date TEXT NOT NULL,
    amount NUMERIC NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    notes TEXT,
    FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS liabilities (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    liability_group TEXT NOT NULL CHECK (
        liability_group IN ('short_term', 'long_term')
    ),
    category TEXT NOT NULL,
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    balance NUMERIC NOT NULL DEFAULT 0 CHECK (balance >= 0),
    interest_rate NUMERIC CHECK (interest_rate IS NULL OR interest_rate >= 0),
    due_date TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS market_prices (
    id INTEGER PRIMARY KEY,
    symbol TEXT NOT NULL,
    market TEXT NOT NULL,
    price NUMERIC NOT NULL CHECK (price >= 0),
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    observed_at TEXT NOT NULL,
    retrieved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS exchange_rates (
    id INTEGER PRIMARY KEY,
    base_currency TEXT NOT NULL CHECK (length(base_currency) = 3),
    quote_currency TEXT NOT NULL CHECK (length(quote_currency) = 3),
    rate NUMERIC NOT NULL CHECK (rate > 0),
    observed_at TEXT NOT NULL,
    retrieved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY,
    snapshot_date TEXT NOT NULL UNIQUE,
    total_assets_ntd NUMERIC NOT NULL CHECK (total_assets_ntd >= 0),
    total_liabilities_ntd NUMERIC NOT NULL CHECK (total_liabilities_ntd >= 0),
    net_worth_ntd NUMERIC NOT NULL,
    portfolio_value_ntd NUMERIC NOT NULL CHECK (portfolio_value_ntd >= 0),
    asset_allocation_json TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_assets_group ON assets(asset_group);
CREATE INDEX IF NOT EXISTS idx_holdings_symbol ON holdings(symbol, market);
CREATE INDEX IF NOT EXISTS idx_recurring_investments_holding
    ON recurring_investments(holding_id);
CREATE INDEX IF NOT EXISTS idx_executions_holding_date
    ON recurring_investment_executions(holding_id, execution_date);
CREATE INDEX IF NOT EXISTS idx_dividends_holding_date
    ON dividends(holding_id, received_date);
CREATE INDEX IF NOT EXISTS idx_prices_symbol_observed
    ON market_prices(symbol, market, observed_at);
CREATE INDEX IF NOT EXISTS idx_rates_currency_observed
    ON exchange_rates(base_currency, quote_currency, observed_at);

-- Derived portfolio values. The latest market price is selected by timestamp.
CREATE VIEW IF NOT EXISTS holding_valuations AS
SELECT
    h.id AS holding_id,
    h.asset_id,
    h.symbol,
    h.security_name,
    h.market,
    h.currency,
    h.shares,
    h.total_cost,
    CASE WHEN h.shares > 0 THEN h.total_cost / h.shares END AS average_cost,
    mp.price AS market_price,
    CASE WHEN mp.price IS NOT NULL THEN h.shares * mp.price END AS market_value,
    CASE WHEN mp.price IS NOT NULL THEN h.shares * mp.price - h.total_cost END
        AS capital_gain_loss,
    COALESCE((SELECT SUM(d.amount) FROM dividends d WHERE d.holding_id = h.id), 0)
        AS dividend_total
FROM holdings h
LEFT JOIN market_prices mp
    ON mp.id = (
        SELECT mp2.id
        FROM market_prices mp2
        WHERE mp2.symbol = h.symbol AND mp2.market = h.market
        ORDER BY mp2.observed_at DESC, mp2.id DESC
        LIMIT 1
    );
