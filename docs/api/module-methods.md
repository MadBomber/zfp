# Module Methods

`Zfp` exposes four module-level methods. These are the simplest way to compress and decompress data without creating any objects.

---

## `Zfp.compress`

```ruby
Zfp.compress(data, type: nil, shape: nil, mode:, **params) → String
```

Compresses `data` and returns a plain `String` of compressed bytes.

**Arguments:**

| Argument | Type | Required | Notes |
|---|---|---|---|
| `data` | `Array` or `Numo::NArray` | yes | The numeric data to compress |
| `type:` | Symbol | conditional | Required for plain `Array` input; inferred for `Numo::NArray` |
| `shape:` | Array of Integer | conditional | Required for plain `Array` input; inferred for `Numo::NArray` |
| `mode:` | Symbol | yes | `:reversible`, `:fixed_rate`, `:fixed_precision`, `:fixed_accuracy` |
| `rate:` | Float | if `:fixed_rate` | Bits per value, must be > 0 |
| `precision:` | Integer | if `:fixed_precision` | Significant bits, must be > 0 |
| `tolerance:` | Float | if `:fixed_accuracy` | Max absolute error per element, must be > 0 |

**Returns:** A `String` of compressed bytes. The caller is responsible for retaining `type`, `shape`, and `mode` for decompression.

**Raises:** `Zfp::InvalidType`, `Zfp::InvalidMode`, `Zfp::InvalidShape`, `Zfp::InvalidParams`, `Zfp::CompressionFailed`

**Examples:**

```ruby
# Lossless
bytes = Zfp.compress([1.0, 2.0, 3.0], type: :double, shape: [3], mode: :reversible)

# Lossy — absolute error bounded
bytes = Zfp.compress(prices, type: :double, shape: [1000],
                             mode: :fixed_accuracy, tolerance: 0.001)

# Numo input — type and shape inferred
bytes = Zfp.compress(Numo::DFloat.cast(prices).reshape(10, 100), mode: :reversible)
```

---

## `Zfp.decompress`

```ruby
Zfp.decompress(bytes, type:, shape:, mode:, numo: false, **params) → Array | Numo::NArray
```

Decompresses `bytes` and returns the original data.

**Arguments:**

| Argument | Type | Required | Notes |
|---|---|---|---|
| `bytes` | String | yes | Compressed bytes from `compress` |
| `type:` | Symbol | yes | Must match the type used during compression |
| `shape:` | Array of Integer | yes | Must match the shape used during compression |
| `mode:` | Symbol | yes | Must match the mode used during compression |
| `numo:` | Boolean | no | Return a `Numo::NArray` instead of a Ruby `Array` |
| `rate:` / `precision:` / `tolerance:` | | if required | Must match compression params |

**Returns:** A flat Ruby `Array`, or a shaped `Numo::NArray` when `numo: true`.

**Raises:** `Zfp::DecompressionFailed`

**Examples:**

```ruby
back = Zfp.decompress(bytes, type: :double, shape: [1000], mode: :reversible)
# => Array of 1000 Floats

back = Zfp.decompress(bytes, type: :double, shape: [50, 252],
                             mode: :fixed_accuracy, tolerance: 0.001, numo: true)
# => Numo::DFloat[50, 252]
```

---

## `Zfp.pack`

```ruby
Zfp.pack(data, type: nil, shape: nil, mode:, **params) → String
```

Compresses `data` and prepends a 32-byte header containing all metadata. The result is a self-describing byte string that can be decompressed with `Zfp.unpack` without any additional arguments.

**Arguments:** Same as `compress`, plus the same Numo auto-detection.

**Header format:** The 32-byte header stores magic bytes (`ZFP\x01`), type, mode, dimensionality, shape dimensions, mode parameter (rate/precision/tolerance), and a flag indicating whether the original input was a `Numo::NArray`.

**Returns:** A `String` of `32 + compressed_size` bytes.

**Example:**

```ruby
packed = Zfp.pack(prices, type: :double, shape: [252],
                          mode: :fixed_accuracy, tolerance: 0.001)
# => "ZFP\x01..." (32-byte header + compressed body)

# Can be stored anywhere and decoded without a schema
File.write("prices.zfp", packed, mode: "wb")
Redis.current.set("prices:AAPL", packed)
```

---

## `Zfp.unpack`

```ruby
Zfp.unpack(bytes) → Array | Numo::NArray
```

Decodes a byte string produced by `pack` or `Zfp::Codec#pack`. Reads all metadata from the embedded header and decompresses.

**Arguments:**

| Argument | Type | Notes |
|---|---|---|
| `bytes` | String | Must have been produced by `pack` |

**Returns:** Ruby `Array` or `Numo::NArray` — the same type as the original input to `pack`. If the original was a `Numo::NArray`, returns the same Numo class with the original shape.

**Raises:** `Zfp::PackerError` if the header is corrupt or truncated.

**Example:**

```ruby
packed   = Zfp.pack(matrix, mode: :reversible)  # matrix is Numo::DFloat[50, 252]
restored = Zfp.unpack(packed)
# => Numo::DFloat[50, 252]  — type, shape, and mode all recovered from header
```
