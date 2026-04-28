# zfp — ZFP Floating-Point Compression for Ruby

> _Because your floats deserve better than Base64._

[![Gem Version](https://img.shields.io/gem/v/zfp)](https://rubygems.org/gems/zfp)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**`zfp`** brings [LLNL's battle-hardened ZFP compression library](https://computing.llnl.gov/projects/zfp) to Ruby. ZFP was built by national-lab scientists to compress petabytes of floating-point simulation data without losing the ability to do science on it. Now it's in a Ruby gem. You're welcome, science.

Whether you're cramming ten years of OHLCV market data into Redis, shipping a million embedding vectors over the wire, or just deeply offended by how wasteful `Array#pack("E*")` is, this gem is for you.

---

## What ZFP Actually Does

ZFP compresses *n*-dimensional arrays of floats, doubles, int32s, and int64s — up to 4 dimensions — using a floating-point-aware transform that exploits spatial correlation across array elements. Unlike general-purpose compressors, it understands the structure of numeric data.

It offers four compression modes:

| Mode | What it does | Good for |
|---|---|---|
| `:reversible` | Bit-exact lossless | Audit trails, exact P&L, storing anything you'll diff |
| `:fixed_rate` | Guaranteed bits-per-value | Streaming, fixed-size storage slots |
| `:fixed_precision` | Guaranteed significant bits | Scientific reproducibility |
| `:fixed_accuracy` | Guaranteed absolute error bound | Financial data, ML embeddings, anything with a tolerance |

---

## Installation

You need `libzfp` installed first. Install it with [upkg](https://github.com/seuros/upkg):

```bash
upkg install zfp
```

Then add the gem:

```bash
bundle add zfp
```

Or install directly:

```bash
gem install zfp
```

No native compilation. No waiting. The binding uses [ruby-ffi](https://github.com/ffi/ffi), so `gem install` is instant and the library loads at runtime.

---

## Five-Minute Quickstart

```ruby
require "zfp"

prices = [174.21, 174.85, 173.40, 175.10, 176.33]  # ... 10,000 more of these

# Lossless round-trip — bit-exact, no questions asked
compressed = Zfp.compress(prices, type: :double, shape: [prices.size], mode: :reversible)
restored   = Zfp.decompress(compressed, type: :double, shape: [prices.size], mode: :reversible)

prices == restored  # => true

# Self-describing pack — no metadata bookkeeping required
packed   = Zfp.pack(prices, type: :double, shape: [prices.size], mode: :reversible)
restored = Zfp.unpack(packed)  # type, shape, mode all embedded — no args needed

prices == restored  # => true
```

That's it. The rest is just choosing how hard you want to squeeze.

---

## API Reference

There are three ways to use the gem. Pick whichever fits your architecture.

### Module methods — the easy path

**Raw bytes** (`compress` / `decompress`)

The caller manages metadata (type, shape, mode). Returns a plain `String` of compressed bytes.

```ruby
bytes = Zfp.compress(data, type: :double, shape: [1000], mode: :reversible)
data  = Zfp.decompress(bytes, type: :double, shape: [1000], mode: :reversible)

# Lossy — absolute error bounded to $0.001 per element
bytes = Zfp.compress(prices, type: :double, shape: [1000], mode: :fixed_accuracy, tolerance: 0.001)
data  = Zfp.decompress(bytes, type: :double, shape: [1000], mode: :fixed_accuracy, tolerance: 0.001)
```

**Self-describing bytes** (`pack` / `unpack`)

Metadata is embedded in a 32-byte header. Pass bytes anywhere — Redis, S3, a message queue — and unpack without needing a schema.

```ruby
# Pack: type/shape/mode/params stored in the bytes themselves
packed   = Zfp.pack(data, type: :double, shape: [1000], mode: :fixed_accuracy, tolerance: 0.001)

# Unpack: zero arguments needed
restored = Zfp.unpack(packed)
```

### `Zfp::Codec` — when you compress many arrays with the same config

Build a codec once. Compress forever.

```ruby
codec = Zfp::Codec.new(type: :double, shape: [252], mode: :fixed_accuracy, tolerance: 0.001)

# Same codec compresses each security's yearly price history
securities.each do |ticker|
  store[ticker] = codec.compress(daily_closes[ticker])
end

# Retrieve and decompress
prices = codec.decompress(store["AAPL"])

# Or pack (self-describing) via codec
packed = codec.pack(daily_closes["AAPL"])
```

---

## Multi-Dimensional Arrays

ZFP natively understands 1-D through 4-D structure. Providing the actual shape (not just total element count) lets it exploit correlation across all axes simultaneously — the more structure you describe, the better it compresses.

```ruby
# 1-D time series
Zfp.compress(prices, type: :double, shape: [252], mode: :reversible)

# 2-D matrix — e.g. 50 securities × 252 days
matrix = securities.flat_map { |s| daily_closes[s] }
Zfp.compress(matrix, type: :double, shape: [50, 252], mode: :fixed_accuracy, tolerance: 0.001)

# 3-D tensor — e.g. 10 portfolios × 30 securities × 252 days
Zfp.compress(tensor, type: :double, shape: [10, 30, 252], mode: :reversible)

# 4-D — ZFP supports up to 4 dimensions
Zfp.compress(data4d, type: :double, shape: [4, 8, 16, 16], mode: :reversible)
```

---

## All Four Scalar Types

```ruby
# Floating-point — all modes available
Zfp.compress(floats,   type: :float,  shape: [n], mode: :reversible)
Zfp.compress(doubles,  type: :double, shape: [n], mode: :fixed_accuracy, tolerance: 1e-6)

# Integer — reversible mode only (already lossless by nature)
Zfp.compress(counts,   type: :int32,  shape: [n], mode: :reversible)
Zfp.compress(ids,      type: :int64,  shape: [n], mode: :reversible)
```

---

## Numo::NArray Support

If [numo-narray](https://github.com/ruby-numo/numo-narray) is loaded, the gem auto-detects type and shape from Numo arrays. No `type:` or `shape:` arguments needed on compress or pack.

```ruby
require "numo/narray"

# Input: Numo::DFloat — type (:double) and shape inferred automatically
closes = Numo::DFloat.cast(daily_prices).reshape(50, 252)
bytes  = Zfp.compress(closes, mode: :fixed_accuracy, tolerance: 0.001)
packed = Zfp.pack(closes,     mode: :reversible)

# Output: get a Numo array back with numo: true
result = Zfp.decompress(bytes, type: :double, shape: [50, 252], mode: :fixed_accuracy,
                               tolerance: 0.001, numo: true)
# => Numo::DFloat[50, 252]

# pack/unpack preserves Numo in → Numo out automatically
result = Zfp.unpack(packed)
# => Numo::DFloat[50, 252]

# All four Numo types supported:
#   Numo::SFloat  → :float
#   Numo::DFloat  → :double
#   Numo::Int32   → :int32
#   Numo::Int64   → :int64
```

---

## Compression Mode Guide

### `:reversible` — lossless, bit-exact

Use this when correctness is non-negotiable. Compression ratios depend on data entropy:
sequential integers and smooth time series compress well; high-entropy noise barely shrinks.

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n], mode: :reversible)
# Typical ratios: 2x–6x on financial/scientific data
```

### `:fixed_accuracy` — absolute error bound

The workhorse for financial and ML workloads. You set a maximum per-element error;
ZFP uses as few bits as needed to honor it.

```ruby
# Error on any element guaranteed ≤ tolerance
bytes = Zfp.compress(prices, type: :double, shape: [n], mode: :fixed_accuracy, tolerance: 0.001)
# $0.001 per price point — indistinguishable for P&L calculations
# Typical ratios: 3x–8x
```

### `:fixed_precision` — significant bits

Useful when you want to preserve a specific number of significant bits rather than
an absolute error bound. Handy for scientific data where relative precision matters more than absolute.

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n], mode: :fixed_precision, precision: 20)
# 20 significant bits preserved (of 52 available in a double)
```

### `:fixed_rate` — guaranteed bytes per value

Use when you need fixed-size storage slots — e.g., each block in a columnar store
must be exactly the same size. The `rate` is bits per scalar value.

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n], mode: :fixed_rate, rate: 16.0)
# 16 bits per value → 4x smaller than raw double
# WARNING: aggressive rates (< 8) can produce large errors on high-dynamic-range data.
#          Always validate max_err against your tolerance before committing to a rate.
```

---

## Real-World Performance

Benchmarked on a portfolio of 5 × ~20 securities × 252 trading days of close prices
(synthetic GBM data, see `examples/portfolio_performance.rb`):

| Mode | Ratio | Max Error |
|---|---|---|
| `:reversible` | 1.1×–1.2× | 0 (exact) |
| `:fixed_accuracy, tolerance: 0.001` | 3.0×–3.4× | < $0.001 |
| `:fixed_accuracy, tolerance: 0.01` | 3.4× | < $0.01 |

ZFP shines brightest on correlated data — real market prices (correlated sectors, macro
moves, mean reversion) compress significantly better than the GBM baseline above.

For ML embedding vectors (1536-dim float32, high spatial correlation):
expect 4×–10× with `:fixed_accuracy` and a tolerance tuned to preserve cosine similarity.

---

## Error Handling

```ruby
Zfp::LibraryNotFound     # libzfp not installed or not found
Zfp::InvalidType         # unrecognized :type symbol
Zfp::InvalidMode         # unrecognized :mode symbol
Zfp::InvalidShape        # empty shape, > 4 dimensions, or non-positive dimension
Zfp::InvalidParams       # missing or invalid mode-specific param (rate/precision/tolerance)
Zfp::CompressionFailed   # libzfp returned an error during compress
Zfp::DecompressionFailed # libzfp returned an error during decompress
Zfp::PackerError         # corrupt or truncated pack header
```

All inherit from `Zfp::Error < StandardError`.

---

## When to Use This Gem

- **In-memory caches of numerical time series** — compress to a byte string, store in Redis,
  decompress on demand. Transparent to the rest of your code.
- **Columnar financial data** — years of OHLCV for thousands of tickers at a fraction of raw size.
- **ML embedding storage** — vectors stay geometrically faithful under `:fixed_accuracy` at
  tolerances that preserve cosine similarity.
- **Message queues** — pack/unpack means the consumer needs no schema; bytes are self-describing.
- **Checkpointing numerical computation** — save intermediate Numo arrays between steps.

## When Not to Use This Gem

- **Random or already-compressed data** — ZFP assumes spatial correlation. Noise, encrypted data,
  and random floats will barely shrink and may grow.
- **Text, blobs, or non-numeric data** — use MessagePack, zstd, or zlib.
- **Tiny arrays (< ~50 elements)** — the 32-byte pack header plus ZFP block overhead dominates.
- **Integer data needing lossy compression** — integer types support `:reversible` only.

---

## Examples

```bash
bundle exec ruby examples/01_basic_usage.rb
bundle exec ruby examples/portfolio_performance.rb
```

---

## Requirements

- Ruby ≥ 3.0
- libzfp 1.0+ — install with [upkg](https://github.com/seuros/upkg): `upkg install zfp`
- [ffi](https://github.com/ffi/ffi) ~> 1.0 (installed automatically)
- [numo-narray](https://github.com/ruby-numo/numo-narray) _(optional — loaded automatically if present)_

---

## Development

```bash
git clone https://github.com/madbomber/zfp
cd zfp
bundle install
bundle exec rake test
```

Tests that require libzfp are automatically skipped if the library isn't found,
so the suite is safe to run anywhere.

---

## Contributing

Bug reports and pull requests are welcome at https://github.com/madbomber/zfp.
Please include a failing test for bugs and a passing test for features.

---

## References

- [ZFP — Compressed Floating-Point and Integer Arrays](https://computing.llnl.gov/projects/zfp) — official project page at Lawrence Livermore National Laboratory
- [ZFP on GitHub](https://github.com/LLNL/zfp) — source, documentation, and compression algorithm details

---

## License

MIT. Go nuts.
