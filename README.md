
# NATS client for Julia.

Work in progress.

## Example

### Publish Subscribe.

```julia
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

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```julia
julia> using NATS

julia> nc = NATS.connect("localhost", 4222)
NATS.Connection(Sockets.TCPSocket(RawFD(21) active, 0 bytes waiting), 0 subs, 0 msgs in outbox)

julia> @time NATS.request(nc, "help.please") .|> payload
  0.006126 seconds (609 allocations: 44.527 KiB, 28.24% compilation time)
1-element Vector{String}:
 "OK, I CAN HELP!!!"
```

### JetStream pull consumer next.

```bash
> nats stream add TEST_STREAM
? Subjects to consume FOO.*
...

> nats consumer add
? Consumer name TestConsumerConsume
...

> nats pub FOO.bar --count=1 "publication #{{Count}} @ {{TimeStamp}}"
20:25:18 Published 42 bytes to "FOO.bar"
```

```julia
julia> using NATS

julia> nc = NATS.connect("localhost", 4222);

julia> msg = NATS.next(nc,"TEST_STREAM", "TestConsumerConsume")
NATS.Msg("FOO.asdf", "oUsbQP4B", "\$JS.ACK.TEST_STREAM.TestConsumerConsume.1.27.189.1694542978673374959.1", 42, "publication #1 @ 2023-09-12T20:22:58+02:00")

julia> NATS.ack(nc, msg)
NATS.Pub("\$JS.ACK.TEST_STREAM.TestConsumerConsume.1.27.189.1694542978673374959.1", nothing, 0, nothing)
```