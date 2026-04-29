# Internals

This page documents the internal classes used by the gem. You do not normally interact with these directly — use the [module methods](module-methods.md) or [`Zfp::Codec`](codec.md) instead. This is useful for contributors, for building custom wrappers, or for understanding how the FFI bridge works.

---

## Architecture Overview

```
Zfp (module methods)
  └── Zfp::Codec
        ├── Zfp::Field      — wraps zfp_field_t (array descriptor)
        ├── Zfp::Stream     — wraps zfp_stream_t + bitstream_t (compression engine)
        ├── Zfp::Packer     — 32-byte header encode/decode
        └── Zfp::TypeCoercion — Ruby Array ↔ FFI::MemoryPointer, Numo integration
              └── Zfp::FFI  — raw libzfp bindings via ruby-ffi
```

---

## `Zfp::FFI`

`lib/zfp/ffi.rb` — Raw bindings to `libzfp` via `ruby-ffi`. Loaded at `require "zfp"` time; raises `Zfp::LibraryNotFound` if the native library is absent.

**Constants:**

| Constant | Value | libzfp meaning |
|---|---|---|
| `ZFP_TYPE_INT32` | 1 | 32-bit signed integer |
| `ZFP_TYPE_INT64` | 2 | 64-bit signed integer |
| `ZFP_TYPE_FLOAT` | 3 | 32-bit IEEE 754 float |
| `ZFP_TYPE_DOUBLE` | 4 | 64-bit IEEE 754 double |

**Attached functions (selected):**

| Function | Purpose |
|---|---|
| `zfp_stream_open` / `zfp_stream_close` | Allocate/free a compression stream |
| `zfp_stream_set_rate` | Configure fixed-rate mode |
| `zfp_stream_set_precision` | Configure fixed-precision mode |
| `zfp_stream_set_accuracy` | Configure fixed-accuracy mode |
| `zfp_stream_set_reversible` | Configure lossless mode |
| `zfp_stream_maximum_size` | Query worst-case buffer size before compressing |
| `zfp_compress` / `zfp_decompress` | Perform compression/decompression |
| `zfp_field_alloc` / `zfp_field_free` | Allocate/free an array descriptor |
| `zfp_field_set_pointer` | Point the field at a data buffer |
| `zfp_field_set_type` | Set the element type |
| `zfp_field_set_size_1d` … `_4d` | Set array dimensionality |
| `stream_open` / `stream_close` | Allocate/free the underlying bitstream |

---

## `Zfp::Field`

`lib/zfp/field.rb` — Manages the `zfp_field_t` struct, which describes the input/output array to libzfp.

A `Field` holds:

- A pointer to the data buffer (`FFI::MemoryPointer`)
- The element type integer (`ZFP_TYPE_*`)
- The shape (1–4 dimensions)

The buffer reference is retained as an instance variable to prevent GC while the field is alive.

```ruby
field = Zfp::Field.new(:double, [50, 252], buffer)
field.pointer   # => FFI::Pointer to zfp_field_t
field.dims      # => 2
field.shape     # => [50, 252]
field.free      # release zfp_field_t
```

`Field#free` is called in the `ensure` block of `Codec#compress` and `Codec#decompress`.

---

## `Zfp::Stream`

`lib/zfp/stream.rb` — Manages the `zfp_stream_t` + `bitstream_t` pair for a single compress or decompress operation.

A `Stream` is constructed with a mode and params, then used once:

```ruby
stream = Zfp::Stream.new(:fixed_accuracy, { tolerance: 0.001 })
compressed = stream.compress(field)   # → String of bytes
stream.decompress(field, compressed)  # fills field's output buffer
```

The stream allocates `zfp_stream_t` and `bitstream_t`, calls `zfp_compress` or `zfp_decompress`, and frees both in `ensure`.

**`#compress` flow:**

1. Open a `zfp_stream_t`
2. Call `apply_mode` to configure the stream (rate/precision/accuracy/reversible)
3. Query `zfp_stream_maximum_size` to allocate a worst-case output buffer
4. Open a `bitstream_t` over that buffer
5. Call `zfp_compress`; raise `CompressionFailed` if it returns 0
6. Read back exactly `written` bytes

**`#decompress` flow:**

1. Copy compressed bytes into a new `FFI::MemoryPointer`
2. Open `zfp_stream_t` and configure mode
3. Open `bitstream_t` over the input
4. Call `zfp_decompress` into the field's output buffer; raise `DecompressionFailed` if it returns 0

---

## `Zfp::TypeCoercion`

`lib/zfp/type_coercion.rb` — Converts between Ruby data and `FFI::MemoryPointer` buffers, and handles Numo integration.

**Key constants:**

| Constant | Purpose |
|---|---|
| `RUBY_TO_ZFP_TYPE` | Maps `:float`/`:double`/`:int32`/`:int64` → ZFP_TYPE_* integer |
| `PACK_FORMAT` | `Array#pack` format strings: `"e*"`, `"E*"`, `"l<*"`, `"q<*"` |
| `ELEMENT_SIZE` | Bytes per element: `{ float: 4, double: 8, int32: 4, int64: 8 }` |

**Public methods:**

| Method | Input | Output |
|---|---|---|
| `detect_type(data)` | `Numo::NArray` | Symbol or `nil` |
| `detect_shape(data)` | `Numo::NArray` | Array or `nil` |
| `numo?(data)` | any | Boolean |
| `to_buffer(data, type)` | Array or Numo | `FFI::MemoryPointer` |
| `from_buffer(ptr, type, shape, as_numo)` | pointer | Array or Numo |

---

## `Zfp::Packer`

`lib/zfp/packer.rb` — Encodes and decodes the 32-byte self-describing header for `pack`/`unpack`.

**Header layout (32 bytes, format `"a4CCCCVVVVE"`):**

| Bytes | Field | Notes |
|---|---|---|
| 0–3 | Magic | `"ZFP\x01"` |
| 4 | Type byte | 0=float, 1=double, 2=int32, 3=int64 |
| 5 | Mode byte | 0=fixed_rate, 1=fixed_precision, 2=fixed_accuracy, 3=reversible |
| 6 | Rank (dims) | 1–4 |
| 7 | Flags | Bit 0: was Numo input |
| 8–11 | Dim0 | `uint32` |
| 12–15 | Dim1 | `uint32` (0 if unused) |
| 16–19 | Dim2 | `uint32` (0 if unused) |
| 20–23 | Dim3 | `uint32` (0 if unused) |
| 24–31 | Param | `double` — rate, precision, tolerance, or 0.0 for reversible |

**Public methods:**

```ruby
Zfp::Packer.encode(compressed_bytes, type:, shape:, mode:, params: {}, numo: false)
# => String: 32-byte header + compressed_bytes

Zfp::Packer.decode(bytes)
# => [type, shape, mode, params, numo, compressed_data]
# raises Zfp::PackerError if header is corrupt
```
