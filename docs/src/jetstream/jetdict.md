# JetDict

## Basic usage

```@repl
using NATS
using NATS.JetStream
nc = NATS.connect()
kv = JetDict{String}(nc, "example_kv")
kv["key1"] = "Value 1"
kv["key2"] = "Value 2"
kv
delete!(kv, "key1")
keyvalue_stream_delete(nc, "example_kv")
```

## Key encoding

Keys of keyvalue stream have limitations. They cannot start and and with '.' and can contain limited set of characters.

Alowed characters:
- letters
- digits
- `'-', '/', '_', '=', '.'`

To allow arbitrary string as a key `:base64url` `encoding` parameter may be specified.


```@repl
using NATS
using NATS.JetStream
nc = NATS.connect()
kv = JetDict{String}(nc, "example_kv_enc", :base64url)
kv["encoded_key1"] = "Value 1"
kv["!@#%^&"] = "Value 2"
kv["!@#%^&"]
keyvalue_stream_delete(nc, "example_kv_enc")
```

## Custom values

```@repl
using NATS
using NATS.JetStream
import Base: show, convert
struct Person
    name::String
    age::Int64
end
function convert(::Type{Person}, msg::NATS.Msg)
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end
function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
end
nc = NATS.connect()
kv = JetDict{Person}(nc, "people")
kv["jakub"] = Person("jakub", 22)
kv["martha"] = Person("martha", 22)
kv["martha"]
kv
keyvalue_stream_delete(nc, "people")
```

## Watching changes

```@repl
using NATS
using NATS.JetStream
nc = NATS.connect()
kv = JetDict{String}(nc, "example_kv_watch")
sub = watch(kv) do change
    @show change
end
@async begin
    kv["a"] = "1"
    kv["b"] = "2"
    delete!(kv, "a")
    kv["b"] = "3"
    kv["a"] = "4"
end
sleep(1) # Wait for changes
stream_unsubscribe(nc, sub)
keyvalue_stream_delete(nc, "example_kv_watch")
```

## Optimistic concurrency

```@repl
using NATS
using NATS.JetStream
connection = NATS.connect()
kv = JetStream.JetDict{String}(connection, "test_kv_concurrency")
kv["a"] = "1"
@async (sleep(2); kv["a"] = "2")
with_optimistic_concurrency(kv) do 
    old = kv["a"]
    sleep(3)
    kv["a"] = "$(old)_updated"
end
kv["a"]
keyvalue_stream_delete(connection, "test_kv_concurrency")
```
