# Transport data structures

## Using custom types as handler input

It is possible to use and return custom types inside subscription handlers if `convert` method from `NATS.Msg` is provided. See `src/protocol/convert.jl` for example implementation for `String`.

```@repl
using NATS
struct Person
    name::String
    age::Int64
end
import Base: convert
function convert(::Type{Person}, msg::NATS.Msg)
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end
connection = NATS.connect() # Important to create a connection after `convert` is defined
sub = subscribe(connection, "EMPLOYEES") do person::Person
    @show person
end
publish(connection, "EMPLOYEES", "John,44")
sleep(0.2) # Wait for message delivered to sub
drain(connection, sub)
```

## Returning custom types from handler

It is also possible to return any type from a handler in `reply` and put any type as `publish` argument if conversion to `UTF-8` string is provided.  
Note that both Julia and NATS protocol use `UTF-8` encoding, so no additional conversions are needed.

NATS module defines custom MIME types for payload and headers serialization:

```julia
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"
```

Conversion method should look like this.

```@repl
using NATS
struct Person
    name::String
    age::Int64
end
import Base: convert, show
function convert(::Type{Person}, msg::NATS.Msg)
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end
function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
end
connection = NATS.connect()
sub = reply(connection, "EMPLOYEES.SUPERVISOR") do person::Person
    if person.name == "Alice"
        Person("Bob", 44)
    else
        Person("Unknown", 0)
    end
end
request(Person, connection, "EMPLOYEES.SUPERVISOR", Person("Alice", 22))
drain(connection, sub)
```

## Error handling

Errors can be handled with custom headers.

```@repl
using NATS
import Base: convert, show
struct Person
    name::String
    age::Int64
    departament::String
end
function convert(::Type{Person}, msg::NATS.Msg)
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
sub = reply(nc, "EMPLOYEES.SUPERVISOR") do person::Person
    
    if person.name == "Alice"
        Person("Bob", 44, "IT"), ["status" => "ok"]
    else
        Person("Unknown", 0, ""), ["status" => "error", "message" => "Supervisor not defined for $(person.name)" ]
    end
end
request(Person, nc, "EMPLOYEES.SUPERVISOR", Person("Alice", 33, "IT"))
error_response = request(nc, "EMPLOYEES.SUPERVISOR", Person("Anna", 33, "ACCOUNTING"));
headers(error_response)
drain(nc, sub)
```
