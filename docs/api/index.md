# API Reference

The `zfp` gem exposes three layers of API. Choose the one that fits your use case.

| API | Description | When to use |
|---|---|---|
| [Module methods](module-methods.md) | `Zfp.compress`, `Zfp.decompress`, `Zfp.pack`, `Zfp.unpack` | One-off operations; the easy path |
| [`Zfp::Codec`](codec.md) | Reusable object with a fixed configuration | Many arrays with the same type/shape/mode |
| [Errors](errors.md) | `Zfp::Error` and subclasses | Error handling |
| [Internals](internals.md) | `Zfp::Field`, `Zfp::Stream`, `Zfp::Packer`, `Zfp::FFI` | Understanding the implementation |

---

## Quick Reference

```ruby
# Module methods
Zfp.compress(data, type:, shape:, mode:, **params)   → String (bytes)
Zfp.decompress(bytes, type:, shape:, mode:, numo: false, **params)  → Array | Numo::NArray
Zfp.pack(data, type: nil, shape: nil, mode:, **params)  → String (bytes with 32-byte header)
Zfp.unpack(bytes)  → Array | Numo::NArray

# Codec
codec = Zfp::Codec.new(type:, shape:, mode:, numo: false, **params)
codec.compress(data)     → String (bytes)
codec.decompress(bytes)  → Array | Numo::NArray
codec.pack(data)         → String (bytes with 32-byte header)
```

---

## Parameter Reference

### `type:` — scalar type

| Symbol | Ruby input | FFI type | Bytes/element |
|---|---|---|---|
| `:float` | `Array` of `Float` or `Numo::SFloat` | 32-bit IEEE 754 | 4 |
| `:double` | `Array` of `Float` or `Numo::DFloat` | 64-bit IEEE 754 | 8 |
| `:int32` | `Array` of `Integer` or `Numo::Int32` | 32-bit signed | 4 |
| `:int64` | `Array` of `Integer` or `Numo::Int64` | 64-bit signed | 8 |

### `shape:` — array dimensions

An `Array` of 1–4 positive integers whose product equals the element count:

```ruby
shape: [1000]           # 1-D, 1000 elements
shape: [50, 252]        # 2-D, 12,600 elements
shape: [10, 30, 252]    # 3-D, 75,600 elements
shape: [4, 8, 16, 16]  # 4-D, 8,192 elements
```

### `mode:` — compression mode

| Symbol | Required params | Description |
|---|---|---|
| `:reversible` | _(none)_ | Lossless, bit-exact |
| `:fixed_rate` | `rate: Float` | Fixed bits per value |
| `:fixed_precision` | `precision: Integer` | Fixed significant bits |
| `:fixed_accuracy` | `tolerance: Float` | Absolute error bound |

### `numo:` — Numo output flag

When `true`, `decompress` returns a `Numo::NArray` instead of a Ruby `Array`. The Numo type is inferred from `type:`.
