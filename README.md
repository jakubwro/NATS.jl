
# NATS client for Julia.

Work in progress.

## Example

```julia-repl
julia> using NATS

julia> nc = NATS.connect("localhost", 4222)
NATS.Connection(Sockets.TCPSocket(RawFD(21) active, 0 bytes waiting), 0 subs, 0 msgs in outbox)

julia> sub = subscribe(nc, "test_subject") do msg
           @show payload(msg)
       end
NATS.Sub("test_subject", nothing, "ROPIuR0Z")

julia> publish(nc, "test_subject"; payload="Hello.")

payload(msg) = "Hello."
```
