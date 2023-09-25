
# NATS client for Julia.

Work in progress.

## CI status

[![](https://github.com/jakubwro/NATS.jl/actions/workflows/test.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions?query=workflow%3A%22Run+tests%22++)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/documentation.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions?query=workflow%3ADocumentation)
[![codecov](https://codecov.io/gh/jakubwro/NATS.jl/graph/badge.svg?token=8X0HPK1T8E)](https://codecov.io/gh/jakubwro/NATS.jl)

![Coverage](https://codecov.io/gh/jakubwro/NATS.jl/graphs/sunburst.svg?token=8X0HPK1T8E)



## Documentation

[![](https://img.shields.io/badge/NATS.jl%20docs-dev-blue.svg)](https://jakubwro.github.io/NATS.jl/dev)


## Description

### Using with REPL.

NATS connection uses asynchronous tasks to handle connection. To make `CTR+C` work smooth in REPL
start `julia` with at least one interactive thread `JULIA_NUM_THREADS=1,1 julia --project`, otherwise interrupt
signal might not be delivered to a repl task.

```
julia> using NATS

julia> nc = NATS.connect("localhost", 4222);

julia> request(nc, "some.long.operation")
^CERROR: InterruptException:
```

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
