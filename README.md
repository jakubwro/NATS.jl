
# NATS client for Julia.

[![](https://github.com/jakubwro/NATS.jl/actions/workflows/runtests.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/runtests.yml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/chaos.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/chaos.yml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/benchmarks.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/benchmarks.yml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/tls.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/tls.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/auth.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/auth.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/cluster.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/cluster.yaml)
[![](https://github.com/jakubwro/NATS.jl/actions/workflows/documentation.yml/badge.svg)](https://github.com/jakubwro/NATS.jl/actions/workflows/documentation.yml)
[![codecov](https://codecov.io/gh/jakubwro/NATS.jl/graph/badge.svg?token=8X0HPK1T8E)](https://codecov.io/gh/jakubwro/NATS.jl)
[![](https://img.shields.io/badge/NATS.jl%20docs-dev-blue.svg)](https://jakubwro.github.io/NATS.jl/dev)

Work in progress, API not stable yet.

[![Coverage](https://codecov.io/gh/jakubwro/NATS.jl/graphs/sunburst.svg?token=8X0HPK1T8E)](https://app.codecov.io/gh/jakubwro/NATS.jl)

## Description

NATS client for julia.

## Quick examples

Start nats-server:

```
docker run -p 4222:4222 nats:latest
```

### Publish subscribe

```julia-repl
julia> using NATS

julia> NATS.connect(default = true)
NATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs, 0 outbox)

julia> sub = subscribe("test_subject") do msg
                         @show payload(msg)
                     end
NATS.Sub("test_subject", nothing, "4sWlOE")

julia> publish("test_subject", "Hello.")

payload(msg) = "Hello."

julia> unsubscribe(sub)
NATS.Unsub("4sWlOE", nothing)

julia> publish("test_subject", "Hello.")

julia> 
```

## Request reply

### Connecting to external service

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```julia-repl
julia> using NATS

julia> NATS.connect(default = true)
NATS.Connection(unnamed cluster, CONNECTED, 0 subs, 0 unsubs)

julia> rep = @time NATS.request("help.please");
  0.006377 seconds (160 allocations: 10.547 KiB)

julia> payload(rep)
"OK, I CAN HELP!!!"
```

### Reply to requests from julia

```
julia> reply("some.service") do msg
           "This is response"
       end
NATS.Sub("some.service", nothing, "P6mANG")

julia> rep = @time NATS.request("some.service");
  0.003101 seconds (220 allocations: 14.125 KiB)

julia> payload(rep)
"This is response"
```
