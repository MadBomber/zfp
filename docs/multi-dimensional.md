# Multi-Dimensional Arrays

ZFP natively understands 1-D through 4-D array structure. Providing the actual shape — not just the total element count — lets it exploit spatial correlation across all axes simultaneously. The more structure you describe, the better it compresses.

---

## How Shape Works

The `shape:` parameter is a Ruby Array of 1–4 positive integers. The product of all dimensions must equal the number of elements in your data.

```ruby
# These all contain 256 elements — but ZFP treats them differently
Zfp.compress(data, type: :double, shape: [256],      mode: :reversible)  # 1-D
Zfp.compress(data, type: :double, shape: [16, 16],   mode: :reversible)  # 2-D
Zfp.compress(data, type: :double, shape: [4, 8, 8],  mode: :reversible)  # 3-D
Zfp.compress(data, type: :double, shape: [4, 4, 4, 4], mode: :reversible) # 4-D
```

For spatially-correlated data (neighboring elements are numerically related), higher-dimensional shapes produce better compression because ZFP's transform operates across block boundaries in each dimension.

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
# 50 securities × 252 trading days of close prices
# Data is row-major (security, day) — flatten before passing to compress
matrix = securities.flat_map { |s| daily_closes[s] }  # 50 × 252 = 12,600 elements

bytes = Zfp.compress(matrix, type: :double, shape: [50, 252],
                             mode: :fixed_accuracy, tolerance: 0.001)
back  = Zfp.decompress(bytes, type: :double, shape: [50, 252],
                              mode: :fixed_accuracy, tolerance: 0.001)
# back is a flat Array of 12,600 doubles — reshape as needed
```

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
# => Zfp::InvalidShape: shape must be Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [4, 4, 4, 4, 4], mode: :reversible)
# => Zfp::InvalidShape: shape must be Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [0, 256],    mode: :reversible)
# => Zfp::InvalidShape: shape must be Array of 1–4 positive integers
```

---

## Tips for Choosing Shape

- **Describe the real structure.** If your data is a 50×252 matrix, pass `shape: [50, 252]` — not `shape: [12600]`. ZFP works in 4×4 blocks per dimension; describing the actual structure means it exploits inter-row correlations.
- **Row-major order.** ZFP expects data in row-major (C-order) layout. Ruby's flat Array and Numo's default layout are both row-major, so no reordering is needed.
- **4-D maximum.** If you have higher-dimensional data, batch it into 4-D chunks or collapse dimensions before compressing.
- **Tiny dimensions hurt.** A shape of `[2, 128]` gives ZFP very little 2-D correlation to exploit — `[128, 2]` is equally bad. If a dimension is less than 4 elements, you may get better results collapsing it.
