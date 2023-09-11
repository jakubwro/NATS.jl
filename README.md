
# NATS client for Julia.

Work in progress.

## Example

### Publish Subscribe.

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

### Request Reply.


```julia-repl
julia> using NATS

julia> nc = NATS.connect("localhost", 4222)
NATS.Connection(Sockets.TCPSocket(RawFD(21) active, 0 bytes waiting), 0 subs, 0 msgs in outbox)

julia> @time NATS.request(nc, "help.please") .|> payload
  0.006126 seconds (609 allocations: 44.527 KiB, 28.24% compilation time)
1-element Vector{String}:
 "OK, I CAN HELP!!!"
```
