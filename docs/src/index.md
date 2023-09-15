# NATS.jl

NATS client for Julia.

# Quick examples

## Publish subscribe

```julia-repl
julia> using NATS

julia> nc = NATS.connect("localhost", 4222)
NATS.Connection(CONNECTED, 0 subs, 0 unsubs, 0 outbox)

julia> sub = subscribe(nc, "test_subject") do msg
                  @show payload(msg)
              end
NATS.Sub("test_subject", nothing, "TeQmd23Z")

julia> publish(nc, "test_subject"; payload="Hello.")
NATS.Pub("test_subject", nothing, 6, "Hello.")

payload(msg) = "Hello."
```

## Request reply

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```julia-repl
julia> using NATS

julia> nc = NATS.connect("localhost", 4222)
NATS.Connection(CONNECTED, 0 subs, 0 unsubs, 0 outbox)

julia> rep = @time NATS.request(nc, "help.please");
  0.006738 seconds (88 allocations: 4.969 KiB)

julia> payload(rep)
"OK, I CAN HELP!!!"
```

## JetStream pull consumer.

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

```julia-repl
julia> using NATS

julia> nc = NATS.connect("localhost", 4222);

julia> msg = NATS.next(nc,"TEST_STREAM", "TestConsumerConsume");

julia> payload(msg)
"publication #1 @ 2023-09-15T14:07:03+02:00"

julia> NATS.ack(nc, msg)
NATS.Pub("\$JS.ACK.TEST_STREAM.TestConsumerConsume.1.27.189.1694542978673374959.1", nothing, 0, nothing)
```
