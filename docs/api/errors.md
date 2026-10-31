# Errors

All exceptions raised by the `zfp` gem are subclasses of `Zfp::Error`, which is itself a subclass of `StandardError`. This lets you rescue them individually or catch all gem errors with a single `rescue Zfp::Error`.

---

## Hierarchy

```
StandardError
└── Zfp::Error
    ├── Zfp::LibraryNotFound
    ├── Zfp::NumoNotAvailable
    ├── Zfp::InvalidType
    ├── Zfp::InvalidMode
    ├── Zfp::InvalidShape
    ├── Zfp::InvalidParams
    ├── Zfp::CompressionFailed
    ├── Zfp::DecompressionFailed
    └── Zfp::PackerError
```

---

## `Zfp::LibraryNotFound`

Raised at `require "zfp"` time if `libzfp` cannot be found on the system.

**When:** The FFI layer fails to load the native `zfp` library.

**Resolution:** Install `libzfp` — see [Installation](../installation.md).

```ruby
rescue Zfp::LibraryNotFound => e
  warn "ZFP not available: #{e.message}"
  # Fall back to uncompressed storage
```

---

## `Zfp::NumoNotAvailable`

Raised when Numo output is requested but the `numo-narray` gem is not installed.

**When:** `decompress(..., numo: true)`, a `Codec` built with `numo: true`, or `Zfp.unpack` on bytes whose header records that the input was a `Numo::NArray`. The gem attempts `require "numo/narray"` on demand first; this error means that require failed.

**Resolution:** `gem install numo-narray`, or request a Ruby `Array` instead.

---

## `Zfp::InvalidType`

Raised when `type:` is not one of the four supported symbols, or when the data does not fit the declared type.

**Valid values:** `:float`, `:double`, `:int32`, `:int64`

```ruby
Zfp.compress(data, type: :complex, shape: [10], mode: :reversible)
# => Zfp::InvalidType: Unknown type: :complex. Valid: [:float, :double, :int32, :int64]

Zfp.compress([1.9, 2.7], type: :int32, shape: [2], mode: :reversible)
# => Zfp::InvalidType: int32 data must be Integers in -2147483648..2147483647, got 1.9

Zfp.compress([2**40], type: :int32, shape: [1], mode: :reversible)
# => Zfp::InvalidType: int32 data must be Integers in -2147483648..2147483647, got 1099511627776
```

Also raised when `type:` is omitted for a Ruby `Array` (it can only be inferred for Numo input), when `data` is neither an `Array` nor a `Numo::NArray`, and when a `Numo::NArray` subtype is not supported (e.g. `Numo::UInt8`).

Float types accept Ruby `Integer`s and `Float`s; anything else raises a `TypeError` from `Array#pack`.

---

## `Zfp::InvalidMode`

Raised when `mode:` is not one of the four supported symbols, or when a lossy mode is combined with an integer type.

**Valid values:** `:reversible`, `:fixed_rate`, `:fixed_precision`, `:fixed_accuracy`

```ruby
Zfp.compress(data, type: :double, shape: [10], mode: :lz4)
# => Zfp::InvalidMode: Unknown mode: :lz4. Valid: [:fixed_rate, :fixed_precision, :fixed_accuracy, :reversible]

Zfp.compress(counts, type: :int32, shape: [10], mode: :fixed_rate, rate: 8.0)
# => Zfp::InvalidMode: int32 supports mode: :reversible only (got :fixed_rate)
```

---

## `Zfp::InvalidShape`

Raised when `shape:` is not a valid array of 1–4 positive integers, or when its product does not equal the number of elements in the data.

```ruby
Zfp.compress(data, type: :double, shape: [],        mode: :reversible)
# => Zfp::InvalidShape: shape must be an Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [0, 100],  mode: :reversible)
# => Zfp::InvalidShape: shape must be an Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [2,2,2,2,2], mode: :reversible)
# => Zfp::InvalidShape: shape must be an Array of 1–4 positive integers

Zfp.compress(ten_values, type: :double, shape: [100], mode: :reversible)
# => Zfp::InvalidShape: shape [100] describes 100 elements but data has 10
```

Also raised when `shape:` is omitted for a Ruby `Array`. The element-count check is a safety check: without it, libzfp would read past the end of the data buffer.

---

## `Zfp::InvalidParams`

Raised when a mode-specific parameter is missing, not the right type, or out of range.

```ruby
# fixed_rate requires rate: (Float > 0)
Zfp.compress(data, type: :double, shape: [100], mode: :fixed_rate)
# => Zfp::InvalidParams: fixed_rate requires rate: (Float > 0)

# fixed_precision requires precision: (Integer > 0)
Zfp.compress(data, type: :double, shape: [100], mode: :fixed_precision, precision: 0)
# => Zfp::InvalidParams: fixed_precision requires precision: (Integer > 0)

# fixed_accuracy requires tolerance: (Float > 0)
Zfp.compress(data, type: :double, shape: [100], mode: :fixed_accuracy, tolerance: -1.0)
# => Zfp::InvalidParams: fixed_accuracy requires tolerance: (Float > 0)
```

---

## `Zfp::CompressionFailed`

Raised when `libzfp` returns 0 bytes written during compression.

This should not happen under normal conditions. It typically indicates a bug in the gem or a corrupt `libzfp` build.

```ruby
rescue Zfp::CompressionFailed => e
  warn "ZFP compression failed: #{e.message}"
```

---

## `Zfp::DecompressionFailed`

Raised when decompression is given input that is provably unusable:

- An empty byte string.
- A `:fixed_rate` stream shorter than its known exact size (truncated).
- `libzfp` returning 0 bytes read.

!!! warning "Most mismatches cannot be detected"
    The raw bytes from `compress` carry no header, so libzfp has no way to know what type, shape, mode, or parameters produced them. Decompressing with the wrong `type:`, `shape:`, `mode:`, `rate:`, `precision:` or `tolerance:`, or with truncated or corrupt bytes in a variable-rate mode, does **not** raise: it returns an array of the requested size containing garbage. The gem guarantees only that this cannot crash the process or read past the input (short input is zero-padded internally). If you need to detect such mismatches, use `pack`/`unpack`, which store the parameters in a header, and keep a checksum of the payload.

```ruby
rescue Zfp::DecompressionFailed => e
  warn "ZFP decompression failed: #{e.message}"
```

---

## `Zfp::PackerError`

Raised when `Zfp.unpack` receives a byte string with a corrupt, missing, or unsupported header.

**Common causes:**

- Truncated bytes (less than 32 bytes)
- Wrong magic bytes (data was not produced by `pack`)
- Unknown type or mode byte (bit-flip or storage corruption)
- Multi-dimensional data packed by gem version 0.1.0 (`ZFP\x01` header), whose layout was transposed — see [Multi-Dimensional Arrays](../multi-dimensional.md#data-layout)

```ruby
rescue Zfp::PackerError => e
  warn "Corrupt ZFP pack header: #{e.message}"
```

---

## Catching All Gem Errors

```ruby
begin
  packed   = Zfp.pack(data, type: :double, shape: [n], mode: :reversible)
  restored = Zfp.unpack(packed)
rescue Zfp::Error => e
  # Covers LibraryNotFound, InvalidType, CompressionFailed, PackerError, etc.
  Rails.logger.error("ZFP error: #{e.class} — #{e.message}")
end
```
