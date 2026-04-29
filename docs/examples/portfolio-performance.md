# Portfolio Performance Example

**File:** `examples/02_portfolio_performance.rb`

A realistic financial simulation that compresses and decompresses synthetic equity portfolio data, verifies data integrity, and computes portfolio returns from decompressed prices.

```bash
bundle exec ruby examples/02_portfolio_performance.rb
```

---

## What It Demonstrates

### Data Generation

Generates 5 portfolios with names:

- Aggressive Growth
- Blue Chip Value
- Tech Momentum
- Dividend Income
- Balanced Core

Each portfolio holds 10–30 randomly selected securities from a pool of 50 tickers (AAPL, MSFT, GOOGL, NVDA, and 46 others). Close prices are simulated using Geometric Brownian Motion over 252 trading days (~1 year) with per-security drift and volatility parameters.

The RNG is seeded at 42, so results are fully reproducible.

### Compression

Each portfolio's close-price matrix (`Numo::DFloat[n_securities, 252]`) is compressed twice using `Zfp.pack`:

```ruby
portfolio.packed_lossless = Zfp.pack(matrix, mode: :reversible)
portfolio.packed_lossy    = Zfp.pack(matrix, mode: :fixed_accuracy, tolerance: 0.001)
```

`Zfp.pack` auto-detects the Numo type and shape — no `type:` or `shape:` arguments needed.

### Compression Statistics

The script prints a table of raw size, lossless size, lossy size, and both ratios for each portfolio and a totals row.

Typical output (GBM data, seed=42):

| Portfolio | Securities | Raw | Lossless | Ratio | Lossy ±$0.001 | Ratio |
|---|---|---|---|---|---|---|
| Aggressive Growth | 17 | 33.5 KB | 31.6 KB | 1.1× | 10.1 KB | 3.3× |
| Blue Chip Value | 14 | 27.6 KB | 26.0 KB | 1.1× | 8.5 KB | 3.2× |
| Tech Momentum | 22 | 43.3 KB | 40.6 KB | 1.1× | 13.3 KB | 3.3× |
| Dividend Income | 13 | 25.6 KB | 24.2 KB | 1.1× | 7.7 KB | 3.3× |
| Balanced Core | 19 | 37.4 KB | 35.4 KB | 1.1× | 11.2 KB | 3.3× |

GBM output is high-entropy compared to real prices, so lossless ratios are modest (~1.1×). Real correlated market data typically compresses 2×–6× losslessly.

### Data Integrity Verification

```ruby
ll_restored = Zfp.unpack(portfolio.packed_lossless)
ls_restored = Zfp.unpack(portfolio.packed_lossy)

ll_delta = (matrix - ll_restored).abs.max   # => 0.0 (bit-exact)
ls_delta = (matrix - ls_restored).abs.max   # => < 0.001 (within tolerance)
```

The script prints per-portfolio verification results confirming:
- Lossless: `bit-exact`
- Lossy: `max_err < $0.001`

### Portfolio Performance

Returns are computed from decompressed lossless data:

```ruby
closes = Zfp.unpack(portfolio.packed_lossless)
start_value = portfolio_value(positions, closes, 0)
end_value   = portfolio_value(positions, closes, 251)
```

Portfolios are ranked by percentage return and printed in order.

The winner's per-security breakdown shows individual ticker returns, shares held, start value, and end value.

---

## Key Patterns to Note

- **`Zfp.pack` with Numo:** No `type:` or `shape:` arguments — both inferred from `Numo::DFloat` matrix
- **`Zfp.unpack` round-trip:** Returns `Numo::DFloat` with the original shape automatically
- **Tolerance verification:** The script confirms the lossy error is within `$0.001` per element
- **Codec-free:** The example uses module methods directly, demonstrating the simplest production pattern for one-shot compression
