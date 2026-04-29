# Compression Modes

ZFP offers four compression modes. Choosing the right one determines whether you get a lossless round-trip, a guaranteed error bound, a fixed output size, or a specific number of significant bits.

---

## `:reversible` — Lossless, Bit-Exact

Use this when correctness is non-negotiable. Every bit survives the round-trip.

**Works with:** `:float`, `:double`, `:int32`, `:int64`

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n], mode: :reversible)
back  = Zfp.decompress(bytes, type: :double, shape: [n], mode: :reversible)

data == back  # => true — always
```

**When to use:**

- Audit trails, exact P&L storage
- Any data you will diff or checksum
- Integer data (`:int32`, `:int64` support only this mode)
- When you don't know the acceptable error for your downstream consumers

**Typical compression ratios:**

| Data type | Ratio |
|---|---|
| Smooth financial time series | 2×–6× |
| High-entropy noise | ≤ 1.1× (may grow) |
| Integer sequences | 2×–8× |

---

## `:fixed_accuracy` — Absolute Error Bound

The workhorse for financial and ML workloads. You specify a maximum per-element absolute error; ZFP uses as few bits as needed to honor it.

**Works with:** `:float`, `:double`

```ruby
bytes = Zfp.compress(prices, type: :double, shape: [n],
                             mode: :fixed_accuracy, tolerance: 0.001)
back  = Zfp.decompress(bytes, type: :double, shape: [n],
                              mode: :fixed_accuracy, tolerance: 0.001)

# Every element satisfies: (original - restored).abs <= tolerance
```

**Parameter:** `tolerance: Float` — maximum absolute error per element, must be > 0.

**Typical compression ratios:**

| Tolerance | Ratio (financial closes) | Max error |
|---|---|---|
| `0.001` | 3.0×–3.4× | < $0.001 |
| `0.01` | 3.4×–4.0× | < $0.01 |
| `1.0` | 5×–8× | < $1.00 |

**Financial data note:** ZFP shines brightest on correlated data. Real market prices (correlated sectors, macro moves, mean reversion) compress significantly better than synthetic GBM data. The ratios above are conservative baselines from synthetic data.

**ML embeddings note:** For 1536-dim float32 vectors with high spatial correlation, expect 4×–10× with a tolerance tuned to preserve cosine similarity.

**Choosing a tolerance:**

```ruby
# Run a sample before committing to a tolerance
sample = recent_prices.first(1000)
[0.0001, 0.001, 0.01, 0.1].each do |tol|
  bytes = Zfp.compress(sample, type: :double, shape: [1000],
                               mode: :fixed_accuracy, tolerance: tol)
  back  = Zfp.decompress(bytes, type: :double, shape: [1000],
                                mode: :fixed_accuracy, tolerance: tol)
  max_err = sample.zip(back).map { |a, b| (a - b).abs }.max
  ratio   = (1000 * 8.0) / bytes.bytesize
  puts "tol=#{tol}  ratio=#{ratio.round(1)}x  max_err=#{max_err}"
end
```

---

## `:fixed_precision` — Significant Bits

Useful when you want to preserve a specific number of significant bits rather than an absolute error bound. Handy for scientific data where relative precision matters more than absolute.

**Works with:** `:float`, `:double`

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n],
                           mode: :fixed_precision, precision: 20)
back  = Zfp.decompress(bytes, type: :double, shape: [n],
                              mode: :fixed_precision, precision: 20)
```

**Parameter:** `precision: Integer` — number of uncompressed bits per value to preserve, must be > 0. A double has 52 mantissa bits; a float has 23.

**Guidance:**

| Precision | Relative accuracy | Notes |
|---|---|---|
| 52 (double) | Full precision | Equivalent to lossless for most inputs |
| 32 | ~10 decimal digits | Indistinguishable from double for most science |
| 20 | ~6 decimal digits | Good for physics simulations |
| 10 | ~3 decimal digits | Heavy lossy; use with care |

---

## `:fixed_rate` — Guaranteed Bytes Per Value

Use when you need fixed-size storage slots — for example, each block in a columnar store must be exactly the same size. The `rate` is bits per scalar value.

**Works with:** `:float`, `:double`

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n],
                           mode: :fixed_rate, rate: 16.0)
back  = Zfp.decompress(bytes, type: :double, shape: [n],
                              mode: :fixed_rate, rate: 16.0)
```

**Parameter:** `rate: Float` — bits per scalar value, must be > 0. A raw double is 64 bits; a raw float is 32 bits.

**Compression ratios by rate (double):**

| Rate (bits) | Compression ratio | Notes |
|---|---|---|
| 32 | 2× | Near-lossless for smooth data |
| 16 | 4× | Noticeable error on high-dynamic-range data |
| 8 | 8× | Significant lossy compression |
| 4 | 16× | Very aggressive — validate error bounds first |

!!! warning "Validate before committing to a rate"
    Aggressive rates (< 8 bits/value) can produce large errors on high-dynamic-range data. Always measure `max_err` on representative data before using a rate in production.

```ruby
bytes   = Zfp.compress(data, type: :double, shape: [n],
                             mode: :fixed_rate, rate: 8.0)
back    = Zfp.decompress(bytes, type: :double, shape: [n],
                               mode: :fixed_rate, rate: 8.0)
max_err = data.zip(back).map { |a, b| (a - b).abs }.max
puts "max_err=#{max_err}"  # verify this is within your tolerance
```

---

## Mode Comparison

Benchmarked on 256 doubles drawn from a sinusoidal dataset:

| Mode / Params | Raw | Compressed | Ratio | Max Error |
|---|---|---|---|---|
| `:reversible` | 2.0 KB | ~800 B | ~2.5× | 0 (exact) |
| `:fixed_rate, rate: 8.0` | 2.0 KB | 256 B | 8× | data-dependent |
| `:fixed_rate, rate: 4.0` | 2.0 KB | 128 B | 16× | data-dependent |
| `:fixed_precision, precision: 24` | 2.0 KB | ~384 B | ~5× | relative |
| `:fixed_accuracy, tolerance: 0.001` | 2.0 KB | ~280 B | ~7× | ≤ 0.001 |
| `:fixed_accuracy, tolerance: 0.1` | 2.0 KB | ~192 B | ~10× | ≤ 0.1 |

---

## Mode Limitations by Type

| Type | `:reversible` | `:fixed_rate` | `:fixed_precision` | `:fixed_accuracy` |
|---|:---:|:---:|:---:|:---:|
| `:float` | ✓ | ✓ | ✓ | ✓ |
| `:double` | ✓ | ✓ | ✓ | ✓ |
| `:int32` | ✓ | ✗ | ✗ | ✗ |
| `:int64` | ✓ | ✗ | ✗ | ✗ |

Integer types support `:reversible` only — they are already lossless by nature, and lossy integer compression rarely makes sense.
