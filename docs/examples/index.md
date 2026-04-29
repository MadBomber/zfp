# Examples

The `examples/` directory contains runnable scripts demonstrating the gem's capabilities.

---

## Running the Examples

```bash
# Install dependencies first
bundle install

# Run the examples
bundle exec ruby examples/01_basic_usage.rb
bundle exec ruby examples/02_portfolio_performance.rb
```

Both scripts auto-load the gem from the local `lib/` directory, so no installation is needed.

---

## Available Examples

### [Basic Usage](basic-usage.md) — `examples/01_basic_usage.rb`

A comprehensive walkthrough of every feature:

1. `compress` / `decompress` — all four scalar types in 1-D
2. Multi-dimensional shapes — 1-D through 4-D
3. All four compression modes with side-by-side ratio and error output
4. `pack` / `unpack` — Ruby Array, integer arrays, Numo input, lossy pack
5. Numo::NArray — all four Numo types, multi-dimensional, `numo: true` on decompress
6. `Zfp::Codec` — batch compression, `pack` via codec, Numo round-trip

### [Portfolio Performance](portfolio-performance.md) — `examples/02_portfolio_performance.rb`

A realistic financial simulation:

- Generates 5 synthetic portfolios of 10–30 securities using Geometric Brownian Motion
- Compresses price matrices with both lossless (`:reversible`) and lossy (`:fixed_accuracy, tolerance: 0.001`)
- Reports compression ratios and max error per portfolio
- Verifies data integrity: lossless is bit-exact, lossy is within `$0.001`
- Computes portfolio returns from decompressed data and ranks by performance
