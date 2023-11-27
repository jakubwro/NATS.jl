# Custom transport types.

## Using custom types as handler input.

It is possible to use and return custom types inside subscription handlers if `convert` method from `Union{Msg, HMsg}` is provided.

```
struct Person
    name::String
    age::Int64
end

import Base: convert

function convert(::Type{Person}, msg::NATS.Msg)
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end
```

```
sub = subscribe("EMPLOYEES") do person::Person
    @show person
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
sub = reply("EMPLOYEES.SUPERVISOR") do person::Person
    if person.name == "Alice"
        Person("Bob", 44)
    else
        Person("Unknown", 0)
    end
end

```

## Error handling

Errors can be handled with custom headers.

```
using NATS

import Base: convert, show

struct Person
    name::String
    age::Int64
    departament::String
end

function convert(::Type{Person}, msg::Union{NATS.Msg, NATS.HMsg})
    name, age, departament = split(payload(msg), ",")
    Person(name, parse(Int64, age), departament)
end

function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
    print(io, ",")
    print(io, person.departament)
end


nc = NATS.connect()
sub = reply("EMPLOYEES.SUPERVISOR") do person::Person
    if person.name == "Alice"
        Person("Bob", 44), ["status" => "ok"]
    else
        Person("Unknown", 0), ["status" => "error", "message" => "Supervisor not defined for $(person.name)" ]
    end
end
supervisor = request(Person, "EMPLOYEES.SUPERVISOR", Person("Alice", 33, "IT"))
@show supervisor

hmsg = request(Person, "EMPLOYEES.SUPERVISOR", Person("Anna", 33, "ACCOUNTING"))

unsubscribe(sub)
```
