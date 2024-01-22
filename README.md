
# NATS client for Julia.

[![](https://github.com/jakubwro/NATS.jl/actions/workflows/runtests.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/runtests.yml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/chaos.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/chaos.yml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/benchmarks.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/benchmarks.yml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/tls.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/tls.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/auth.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/auth.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/cluster.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/cluster.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/jetstream.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/jetstream.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/documentation.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/documentation.yml)
[![codecov](https://codecov.io/gh/jakubwro/NATS.jl/graph/badge.svg?token=8X0HPK1T8E)](https://codecov.io/gh/jakubwro/NATS.jl)
[![](https://img.shields.io/badge/NATS.jl%20docs-dev-blue.svg)](https://jakubwro.github.io/NATS.jl/dev)

## Description

[NATS](https://nats.io) client for Julia.

This client is feature complete in terms of `Core NATS` protocol and most of [JetStream](https://docs.nats.io/nats-concepts/jetstream) API.
- [x] All `NATS` authentication methods
- [x] TLS support
- [x] Zero copy protocol parser

Performance is matching reference `go` implementation.

For [JetStream](https://docs.nats.io/nats-concepts/jetstream) check [JetStream.jl](https://github.com/jakubwro/JetStream.jl) - work in progress.

## Compatibility

### Julia

It was tested in `julia` `1.9` and `1.10`

### NATS

It was tested on `NATS` `2.10`.

## Quick examples

Start nats-server:

```
docker run -p 4222:4222 nats:latest
```

### Publish subscribe

```julia
julia> using NATS

julia> nc = NATS.connect()
NATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs)

julia> sub = subscribe(nc, "test_subject") do msg
                 @show payload(msg)
             end;

julia> publish(nc, "test_subject", "Hello.")

payload(msg) = "Hello."

julia> drain(nc, sub)

```

## Request reply

### Connecting to external service

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```julia
julia> using NATS

julia> nc = NATS.connect()
NATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs)

julia> rep = @time NATS.request(nc, "help.please");
  0.003854 seconds (177 allocations: 76.359 KiB)

julia> payload(rep)
"OK, I CAN HELP!!!"
```

### Reply to requests from julia

```julia
julia> using NATS

julia> nc = NATS.connect()
NATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs)

julia> sub = reply(nc, "some.service") do msg
                 "This is response"
             end

julia> rep = @time NATS.request(nc, "some.service");
  0.002897 seconds (231 allocations: 143.078 KiB)

julia> payload(rep)
"This is response"

julia> drain(nc, sub)

```
