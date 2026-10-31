# Multi-Dimensional Arrays

ZFP natively understands 1-D through 4-D array structure. Providing the actual shape — not just the total element count — lets it exploit spatial correlation across all axes simultaneously. The more structure you describe, the better it compresses.

---

## How Shape Works

The `shape:` parameter is a Ruby Array of 1–4 positive integers. The product of all dimensions must equal the number of elements in your data; a mismatch raises `Zfp::InvalidShape`.

```ruby
# These all contain 256 elements — but ZFP treats them differently
Zfp.compress(data, type: :double, shape: [256],      mode: :reversible)  # 1-D
Zfp.compress(data, type: :double, shape: [16, 16],   mode: :reversible)  # 2-D
Zfp.compress(data, type: :double, shape: [4, 8, 8],  mode: :reversible)  # 3-D
Zfp.compress(data, type: :double, shape: [4, 4, 4, 4], mode: :reversible) # 4-D
```

For spatially-correlated data (neighboring elements are numerically related), higher-dimensional shapes produce better compression because ZFP's transform operates on 4×4 (×4 ×4) blocks in each dimension.

---

## Data Layout

`shape:` is **row-major**: the order you get from a nested Ruby Array flattened with `Array#flatten`, and the order `Numo::NArray#shape` reports. The **last** dimension varies fastest in memory.

```ruby
matrix = [[1.0, 2.0, 3.0],   # row 0
          [4.0, 5.0, 6.0]]   # row 1
flat   = matrix.flatten      # => [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
shape  = [2, 3]              # 2 rows × 3 columns
```

libzfp numbers its dimensions the other way around: its `nx` is the *fastest*-varying axis (see [zfp FAQ #0](https://zfp.readthedocs.io/en/latest/faq.html#q-layout)). The gem performs that conversion internally, so you never reverse a shape yourself. Getting this wrong matters a great deal: on a 100 × 120 grid of smooth rows, the correct order compresses 15×, the transposed order only 6×.

!!! note "Upgrading from 0.1.0"
    Versions before 0.2.0 passed the shape to libzfp untransposed, so multi-dimensional data was compressed with the wrong layout. Round-trips were exact, but ratios and lossy accuracy suffered. Bytes packed by 0.1.0 with two or more dimensions use header magic `ZFP\x01` and are rejected by `Zfp.unpack` with a message explaining why; 1-D 0.1.0 bytes still unpack. See [Issue #2](https://github.com/MadBomber/zfp/issues/2).

---

## 1-D — Time Series

```ruby
# 252 daily closes for one security
prices = daily_closes["AAPL"]  # Array of 252 doubles

bytes = Zfp.compress(prices, type: :double, shape: [252], mode: :reversible)
back  = Zfp.decompress(bytes, type: :double, shape: [252], mode: :reversible)
```

---

## 2-D — Matrices

Ideal for price matrices (securities × days), covariance matrices, or any 2-D numeric grid.

```ruby
# 50 securities × 252 trading days of close prices.
# Row-major (security, day): each security's 252 days are contiguous.
matrix = securities.flat_map { |s| daily_closes[s] }  # 50 × 252 = 12,600 elements

bytes = Zfp.compress(matrix, type: :double, shape: [50, 252],
                             mode: :fixed_accuracy, tolerance: 0.001)
back  = Zfp.decompress(bytes, type: :double, shape: [50, 252],
                              mode: :fixed_accuracy, tolerance: 0.001)
# back is a flat Array of 12,600 doubles in the same row-major order
```

A nested Array (`[[...252 values...], [...], ...]`) is accepted too; the gem flattens it.

With Numo::NArray, the matrix is passed directly:

```ruby
require "numo/narray"

closes = Numo::DFloat.cast(all_prices).reshape(50, 252)
bytes  = Zfp.compress(closes, mode: :fixed_accuracy, tolerance: 0.001)
result = Zfp.decompress(bytes, type: :double, shape: [50, 252],
                               mode: :fixed_accuracy, tolerance: 0.001, numo: true)
# result: Numo::DFloat[50, 252]
```

---

## 3-D — Tensors

```ruby
# 10 portfolios × 30 securities × 252 days
tensor = portfolios.flat_map { |p| p.flat_map { |s| daily_closes[s] } }

bytes = Zfp.compress(tensor, type: :double, shape: [10, 30, 252], mode: :reversible)
back  = Zfp.decompress(bytes, type: :double, shape: [10, 30, 252], mode: :reversible)
```

---

## 4-D — Maximum Dimensionality

ZFP supports up to 4 dimensions.

```ruby
# 4-D scientific simulation output: 4 × 8 × 16 × 16 = 8,192 doubles
bytes = Zfp.compress(data4d, type: :double, shape: [4, 8, 16, 16], mode: :reversible)
back  = Zfp.decompress(bytes, type: :double, shape: [4, 8, 16, 16], mode: :reversible)
```

---

## Shape Validation

The gem validates `shape:` before calling libzfp. Invalid shapes raise `Zfp::InvalidShape`:

```ruby
Zfp.compress(data, type: :double, shape: [],          mode: :reversible)
# => Zfp::InvalidShape: shape must be an Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [4, 4, 4, 4, 4], mode: :reversible)
# => Zfp::InvalidShape: shape must be an Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [0, 256],    mode: :reversible)
# => Zfp::InvalidShape: shape must be an Array of 1–4 positive integers

Zfp.compress(ten_values, type: :double, shape: [100], mode: :reversible)
# => Zfp::InvalidShape: shape [100] describes 100 elements but data has 10
```

The last check matters: without it libzfp would read past the end of your data.

---

## Tips for Choosing Shape

- **Describe the real structure.** If your data is a 50×252 matrix, pass `shape: [50, 252]` — not `shape: [12600]`. ZFP works in 4-element blocks per dimension; describing the actual structure means it exploits inter-row correlations.
- **Put the smooth axis last.** The last dimension is the one ZFP sees as contiguous. For a securities × days matrix, days (which are autocorrelated) should be the last dimension.
- **Row-major only.** If your data came from a column-major source (Fortran, some BLAS layouts), transpose it first or reverse the shape to match the memory order.
- **4-D maximum.** If you have higher-dimensional data, batch it into 4-D chunks or collapse dimensions before compressing.
- **Tiny dimensions hurt.** A shape of `[2, 128]` gives ZFP very little 2-D correlation to exploit — `[128, 2]` is equally bad. If a dimension is less than 4 elements, you may get better results collapsing it.
