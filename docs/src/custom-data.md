# Custom transport types.

## Using custom types as handler input.

It is possible to use and return custom types inside subscription handlers if `convert` method from `Union{Msg, HMsg}` is provided.

```
struct Person
    name::String
    age::Int64
end

function convert(::Type{Person}, msg::Union{NATS.Msg, NATS.HMsg})
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end
```

```
sub = subscribe("EMPLOYEES") do person::Person
    put!(c, person)
end
```

## Returning custom types from handler.

It is also possible to return any type from a handler in `reply` and put any type as `publish` argument if conversion to `UTF-8` string is provided.  
Note that both Julia and NATS protocol use `UTF-8` encoding, so no additional conversions are needed.

NATS module defines custom MIME types for payload and headers serialization:

```
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"
```

Conversion method should look like this.

```
function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
end
```

```

```


