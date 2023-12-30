# Scoped connection

This feature allows to use implicit connection in a block of code. It utilizes [ScopedValues](https://github.com/vchuravy/ScopedValues.jl) package.

## Functions

```@docs
with_connection
```

## Examples

```julia
using NATS
conn1 = NATS.connect()
conn2 = NATS.connect()

with_connection(conn1) do
    sub = subscribe("foo") do msg
        @show payload(msg)
    end
    sleep(0.1) # Wait some time to let server process sub.
    with_connection(conn2) do
        publish("foo", "Some payload")
    end
    sleep(0.1) # Wait some time to message be delivered.
    unsubscribe(sub)
    nothing
end

@assert conn1.stats.msgs_received == 1
@assert conn1.stats.msgs_published == 0

@assert conn2.stats.msgs_received == 0
@assert conn2.stats.msgs_published == 1

```