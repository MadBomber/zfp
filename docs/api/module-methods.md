# Module Methods

`Zfp` exposes five module-level methods. These are the simplest way to compress and decompress data without creating any objects.

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

**Raises:** `Zfp::InvalidType` (unknown type, non-Array data, integer data out of range), `Zfp::InvalidMode` (unknown mode, or a lossy mode with an integer type), `Zfp::InvalidShape` (bad shape, or shape product ≠ element count), `Zfp::InvalidParams`, `Zfp::CompressionFailed`

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

**Raises:** `Zfp::DecompressionFailed` for empty input or a truncated `:fixed_rate` stream; `Zfp::NumoNotAvailable` if `numo: true` and numo-narray is not installed.

!!! warning
    Mismatched `type:`, `shape:`, `mode:` or params cannot be detected — the raw bytes carry no header. You get a full-size array of garbage, not an error. See [Errors](errors.md#zfpdecompressionfailed).

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
Zfp.pack(data, type: nil, shape: nil, mode:, numo: nil, **params) → Zfp::Packed
```

Compresses `data` and prepends a 32-byte header containing all metadata. The result is a [`Zfp::Packed`](packed.md): self-describing bytes that can be decompressed with `#unpack` or `Zfp.unpack` without any additional arguments, saved with `#save(path)`, and passed anywhere a `String` is accepted.

**Arguments:** Same as `compress`, plus the same Numo auto-detection, plus `numo:` — whether `Zfp.unpack` should return a `Numo::NArray`. Defaults to `true` for Numo input and `false` for a Ruby `Array`.

**Header format:** The 32-byte header stores magic bytes (`ZFP\x02`), type, mode, dimensionality, shape dimensions, mode parameter (rate/precision/tolerance), and a flag indicating whether the original input was a `Numo::NArray`. The header is gem-specific; see [Internals](internals.md#zfppacker) for the layout.

**Returns:** A `Zfp::Packed` of `32 + compressed_size` bytes (`#bytesize`), convertible to a `String` with `#to_str`.

**Example:**

```ruby
packed = Zfp.pack(prices, type: :double, shape: [252],
                          mode: :fixed_accuracy, tolerance: 0.001)
# => #<Zfp::Packed type=:double shape=[252] mode=:fixed_accuracy tolerance=0.001 bytesize=664>

# Can be stored anywhere and decoded without a schema
packed.save("prices.zfp")
Redis.current.set("prices:AAPL", packed)   # String-compatible via to_str
```

---

## `Zfp.unpack`

```ruby
Zfp.unpack(bytes) → Array | Numo::NArray
```

Decodes a `Zfp::Packed`, or the raw bytes of one (for example read back from Redis), produced by `pack` or `Zfp::Codec#pack`. Reads all metadata from the embedded header and decompresses. `packed.unpack` is the same operation.

**Arguments:**

| Argument | Type | Notes |
|---|---|---|
| `bytes` | String or `Zfp::Packed` | Must have been produced by `pack` (anything responding to `to_str`) |

**Returns:** Ruby `Array` or `Numo::NArray` — the same type as the original input to `pack`. If the original was a `Numo::NArray`, returns the same Numo class with the original shape.

**Raises:** `Zfp::PackerError` if the header is corrupt, truncated, or is a 0.1.0 multi-dimensional header (`ZFP\x01`, transposed layout). `Zfp::NumoNotAvailable` if the header asks for Numo output and numo-narray is not installed.

**Example:**

```ruby
packed   = Zfp.pack(matrix, mode: :reversible)  # matrix is Numo::DFloat[50, 252]
restored = Zfp.unpack(packed)
# => Numo::DFloat[50, 252]  — type, shape, and mode all recovered from header

raw = redis.get("closes")     # a String of packed bytes
Zfp.unpack(raw)               # works on the raw bytes too
```

---

## `Zfp.load`

```ruby
Zfp.load(path) → Zfp::Packed
```

Reads a file written with [`Zfp::Packed#save`](packed.md#save) and returns the `Zfp::Packed`, metadata intact. Nothing is decompressed until you call `#unpack`, so loading is cheap and the header fields (`type`, `shape`, `mode`, `params`, `numo?`) can be inspected first.

**Raises:** `Errno::ENOENT` and other `SystemCallError`s from the filesystem; `Zfp::PackerError` if the file is not a zfp pack (or is a multi-dimensional 0.1.0 pack).

**Example:**

```ruby
packed = Zfp.pack(prices, type: :double, shape: [252], mode: :fixed_accuracy, tolerance: 0.001)
packed.save("prices.zfp")

loaded = Zfp.load("prices.zfp")
loaded.shape      # => [252]
loaded.params     # => { tolerance: 0.001 }
prices = loaded.unpack
```

The `.zfp` extension is recommended (`Zfp::Packed::EXTENSION`) but not enforced.
