# Numo::NArray Integration

If [numo-narray](https://github.com/ruby-numo/numo-narray) is loaded, the gem auto-detects type and shape from Numo arrays on both compress and pack. No `type:` or `shape:` arguments needed.

---

## Supported Numo Types

| Numo class | ZFP type | Element size |
|---|---|---|
| `Numo::SFloat` | `:float` | 4 bytes |
| `Numo::DFloat` | `:double` | 8 bytes |
| `Numo::Int32` | `:int32` | 4 bytes |
| `Numo::Int64` | `:int64` | 8 bytes |

Other Numo types (e.g. `Numo::UInt8`) raise `Zfp::InvalidType`.

---

## Auto-Detection on Input

When the input is a `Numo::NArray`, `type:` and `shape:` are inferred automatically:

```ruby
require "numo/narray"
require "zfp"

closes = Numo::DFloat.cast(daily_prices).reshape(50, 252)

# type: :double and shape: [50, 252] are detected automatically
bytes = Zfp.compress(closes, mode: :fixed_accuracy, tolerance: 0.001)
```

This works for all four module methods (`compress`, `decompress` does not use auto-detection since it has no input array) and for `pack`.

---

## Getting a Numo Array Back on Decompress

Pass `numo: true` to `decompress` to get a `Numo::NArray` instead of a Ruby `Array`:

```ruby
result = Zfp.decompress(bytes, type: :double, shape: [50, 252],
                               mode: :fixed_accuracy, tolerance: 0.001,
                               numo: true)
# => Numo::DFloat[50, 252]
```

The returned array has the same shape as specified. Without `numo: true`, a flat Ruby `Array` is returned.

---

## Pack / Unpack Preserves the Numo Type

`pack` records whether the input was a Numo array in the 32-byte header. `unpack` returns the same Numo type without any arguments:

```ruby
packed = Zfp.pack(closes, mode: :reversible)
result = Zfp.unpack(packed)
# => Numo::DFloat[50, 252]  — shape and type restored from header
```

If the original input was a Ruby `Array`, `unpack` returns a Ruby `Array`.

---

## All Four Types — Full Example

```ruby
require "numo/narray"
require "zfp"

# SFloat
sf = Numo::SFloat.cast((1..64).map { |i| i * 1.5 })
bytes  = Zfp.compress(sf, mode: :reversible)
result = Zfp.decompress(bytes, type: :float, shape: [64], mode: :reversible, numo: true)
# result: Numo::SFloat[64]

# DFloat
df = Numo::DFloat.cast((1..64).map { |i| i * 1.5 })
bytes  = Zfp.compress(df, mode: :reversible)
result = Zfp.decompress(bytes, type: :double, shape: [64], mode: :reversible, numo: true)
# result: Numo::DFloat[64]

# Int32
i32 = Numo::Int32.cast((1..64).to_a)
bytes  = Zfp.compress(i32, mode: :reversible)
result = Zfp.decompress(bytes, type: :int32, shape: [64], mode: :reversible, numo: true)
# result: Numo::Int32[64]

# Int64
i64 = Numo::Int64.cast((1..64).map { |i| i * 10_000 })
bytes  = Zfp.compress(i64, mode: :reversible)
result = Zfp.decompress(bytes, type: :int64, shape: [64], mode: :reversible, numo: true)
# result: Numo::Int64[64]
```

---

## Multi-Dimensional Numo Arrays

Shape is inferred from `narray.shape`, so reshape before passing:

```ruby
# 2-D: 16 × 16
matrix = Numo::DFloat.cast((1..256).map { |i| Math.sin(i * 0.05) * 50 }).reshape(16, 16)
bytes  = Zfp.compress(matrix, mode: :reversible)
result = Zfp.decompress(bytes, type: :double, shape: [16, 16], mode: :reversible, numo: true)
# result: Numo::DFloat[16, 16]

# 3-D: 4 × 4 × 16
tensor = Numo::DFloat.cast((1..256).map { |i| Math.cos(i * 0.05) * 50 }).reshape(4, 4, 16)
bytes  = Zfp.compress(tensor, mode: :reversible)
result = Zfp.decompress(bytes, type: :double, shape: [4, 4, 16], mode: :reversible, numo: true)
# result: Numo::DFloat[4, 4, 16]
```

---

## Using Codec with Numo

Pass `numo: true` in the constructor so all decompress calls return Numo arrays:

```ruby
codec = Zfp::Codec.new(type: :double, shape: [8, 8], mode: :reversible, numo: true)
na    = Numo::DFloat.cast((1..64).map { |i| Math.log(i + 1) }).reshape(8, 8)

bytes  = codec.compress(na)
result = codec.decompress(bytes)
# result: Numo::DFloat[8, 8]
```

---

## Without Numo

If `numo-narray` is not loaded, passing a `Numo::NArray` raises `Zfp::InvalidType` (since the type cannot be detected), and `numo: true` on decompress simply has no Numo classes to return. Ruby `Array` input and output always work regardless.
