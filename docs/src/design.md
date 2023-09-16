
# Design notes

## Parsing

Benchmark after any changes to parsing, "4k requests" is a good test case.

### Use `split`

Avoid using regex, `split` is used to extract protocol data. Some performance might be squeezed by avoiding conversion from `SubString` to `String` but it will be observable only for huge payloads.


### Use strings not raw bytes

Parser is not returning raw bytes but rather `String`. This fast thanks to how `String` constructor works.

```julia-repl
julia> bytes = UInt8['a', 'b', 'c'];

julia> str = String(bytes)
"abc"

julia> bytes
UInt8[]

julia> @doc String
  ...
  When possible, the memory of v will be used without copying when the String object is created.
  This is guaranteed to be the case for byte vectors returned by take! on a writable IOBuffer
  and by calls to read(io, nb). This allows zero-copy conversion of I/O data to strings. In
  other cases, Vector{UInt8} data may be copied, but v is truncated anyway to guarantee
  consistent behavior.
  ...
```
