# Compression Modes

ZFP offers four compression modes. Choosing the right one determines whether you get a lossless round-trip, a guaranteed error bound, a fixed output size, or a specific number of significant bits.

All ratios on this page were measured with this gem on the data described. Your data will differ; the [tolerance sweep](#choosing-a-tolerance) below shows how to measure your own.

---

## `:reversible` — Lossless, Bit-Exact

Use this when correctness is non-negotiable. Every bit survives the round-trip, including NaN, ±Infinity, and −0.0.

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

**Measured compression ratios:**

| Data | Ratio |
|---|---|
| Simulated (GBM) daily closes, 14–29 securities × 252 days, double | 1.0×–1.1× |
| Sinusoid, 256 doubles | 1.1× |
| Sequential integers `1..128`, int32 | 2.7× |
| `i * 1.5` for `i` in `1..128`, double | 5.8× |
| 100 × 120 grid where every row is the ramp `0..119`, float | 15.3× |
| High-entropy noise | ≤ 1.0× (may grow slightly) |

Lossless ratios are driven entirely by how predictable neighboring values are. Real market prices (correlated sectors, autocorrelated returns) should fall between the GBM and sinusoid rows, but measure before you plan around a number.

---

## `:fixed_accuracy` — Absolute Error Bound

The workhorse for financial and ML workloads. You specify a maximum per-element absolute error; ZFP uses as few bits as needed to honor it.

**Works with:** `:float`, `:double`

```ruby
bytes = Zfp.compress(prices, type: :double, shape: [n],
                             mode: :fixed_accuracy, tolerance: 0.001)
back  = Zfp.decompress(bytes, type: :double, shape: [n],
                              mode: :fixed_accuracy, tolerance: 0.001)

# Every finite element satisfies: (original - restored).abs <= tolerance
```

**Parameter:** `tolerance: Float` — maximum absolute error per element, must be > 0.

!!! warning "NaN and Infinity are not preserved in lossy modes"
    ZFP's lossy modes operate on finite values only. A NaN or ±Infinity in the input comes back as a finite value (typically 0.0) and can disturb the other values in its 4-element block. Use `:reversible` for data that may contain non-finite values, or sanitize first.

**Measured compression ratios:**

| Data | Tolerance | Ratio | Max error observed |
|---|---|---|---|
| Simulated daily closes (double, 2-D) | `0.001` | 2.7×–3.0× | $0.00035 |
| Sinusoid × 1000, 256 doubles | `0.001` | 2.8× | 5.0e-4 |
| Sinusoid × 1000, 256 doubles | `0.1` | 3.7× | 2.8e-2 |
| Sinusoid × 1000, 256 doubles | `1.0` | 4.8× | 4.4e-1 |
| Uniform random × 1000, 10,000 doubles | `0.001` | 2.5× | 5.8e-4 |
| Uniform random × 1000, 10,000 doubles | `1.0` | 4.1× | 6.0e-1 |

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

Useful when relative precision matters more than an absolute error bound: large values keep more absolute precision than small ones.

**Works with:** `:float`, `:double`

```ruby
bytes = Zfp.compress(data, type: :double, shape: [n],
                           mode: :fixed_precision, precision: 20)
back  = Zfp.decompress(bytes, type: :double, shape: [n],
                              mode: :fixed_precision, precision: 20)
```

**Parameter:** `precision: Integer` — the number of bits ZFP keeps for each transform coefficient, must be > 0. The useful range is 1–64 for `:double` and 1–32 for `:float`. This is *not* a mantissa-bit count: ZFP applies a block transform before quantizing, so `precision` controls the bit budget of the transformed values. Error is relative to the largest magnitude in each 4-element block.

**Measured on a sinusoid × 1000 (256 doubles):**

| Precision | Ratio | Max error |
|---|---|---|
| 24 | 2.7× | 5.0e-4 |
| 12 | 5.4× | 1.6 |

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

**Output size:** `rate × element_count / 8` bytes, rounded up to the next 8-byte stream word, for shapes whose dimensions are multiples of 4. Other shapes are padded to whole 4-element blocks first.

!!! note "libzfp enforces a minimum rate"
    Each block needs a few bits of overhead, so libzfp rounds very low rates up. For 1-D doubles the floor is about 3 bits per value: `rate: 1.0` and `rate: 2.0` both produce the same output as `rate: 3.0`. The floor is lower in higher dimensions (16 values per 2-D block instead of 4). The gem sizes its buffers from the rate libzfp actually applied, and `Zfp::Stream#actual_rate` exposes it.

**Measured on a sinusoid × 1000 (256 doubles):**

| Rate (bits) | Compressed | Ratio | Max error |
|---|---|---|---|
| 16 | 512 B | 4× | small |
| 8 | 256 B | 8× | 22.8 |
| 4 | 128 B | 16× | 612 |
| 2 (applied as 3) | 96 B | 21× | 1000 (useless) |

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

Because the size of a fixed-rate stream is known exactly, `decompress` raises `Zfp::DecompressionFailed` when it is handed a shorter (truncated) one. The other three modes have no fixed size, so truncation there cannot be detected — see [Errors](api/errors.md#zfpdecompressionfailed).

---

## Mode Comparison

Measured on the same 256 doubles, `Math.sin(i * 0.05) * 1000` for `i` in `1..256`, 1-D (`examples/01_basic_usage.rb`, section 3):

| Mode / Params | Raw | Compressed | Ratio | Max Error |
|---|---|---|---|---|
| `:reversible` | 2.0 KB | 1.8 KB | 1.1× | 0 (exact) |
| `:fixed_rate, rate: 8.0` | 2.0 KB | 256 B | 8× | 22.8 |
| `:fixed_rate, rate: 4.0` | 2.0 KB | 128 B | 16× | 612 |
| `:fixed_precision, precision: 24` | 2.0 KB | 760 B | 2.7× | 5.0e-4 |
| `:fixed_precision, precision: 12` | 2.0 KB | 376 B | 5.4× | 1.6 |
| `:fixed_accuracy, tolerance: 0.001` | 2.0 KB | 744 B | 2.8× | 5.0e-4 |
| `:fixed_accuracy, tolerance: 0.1` | 2.0 KB | 552 B | 3.7× | 2.8e-2 |
| `:fixed_accuracy, tolerance: 1.0` | 2.0 KB | 424 B | 4.8× | 4.4e-1 |

A 256-element 1-D array is a small, hard case for ZFP. Larger and higher-dimensional data with real spatial correlation compresses far better; see [Multi-Dimensional Arrays](multi-dimensional.md).

---

## Mode Limitations by Type

| Type | `:reversible` | `:fixed_rate` | `:fixed_precision` | `:fixed_accuracy` |
|---|:---:|:---:|:---:|:---:|
| `:float` | ✓ | ✓ | ✓ | ✓ |
| `:double` | ✓ | ✓ | ✓ | ✓ |
| `:int32` | ✓ | ✗ | ✗ | ✗ |
| `:int64` | ✓ | ✗ | ✗ | ✗ |

Integer types support `:reversible` only; combining them with another mode raises `Zfp::InvalidMode`. Integer data must consist of Ruby `Integer`s within the 32-bit or 64-bit signed range, or `Zfp::InvalidType` is raised — nothing is silently truncated or wrapped.
