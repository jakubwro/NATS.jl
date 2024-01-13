# Benchmarks

Procedures to compare NATS.jl performance with `go` implementation.

Prerequisites:
- start nats-server

```
docker run -p 4222:4222 nats:latest
```

- enusre `nats` CLI tool is installed

## Request-Reply latency

### Native `go` latency

Start reply service

```
> nats reply foo "This is a reply" 2> /dev/null > /dev/null
```

Run benchmark with 1 publisher

```
> nats bench foo --pub 1 --request --msgs 1000
13:25:53 Benchmark in request-reply mode
13:25:53 Starting request-reply benchmark [subject=foo, multisubject=false, multisubjectmax=0, request=true, reply=false, msgs=1,000, msgsize=128 B, pubs=1, subs=0, pubsleep=0s, subsleep=0s]
13:25:53 Starting publisher, publishing 1,000 messages
Finished      0s [================] 100%

Pub stats: 1,676 msgs/sec ~ 209.57 KB/sec
```

Run benchmark with 10 publishers

```
> nats bench foo --pub 10 --request --msgs 10000
13:30:52 Benchmark in request-reply mode
13:30:52 Starting request-reply benchmark [subject=foo, multisubject=false, multisubjectmax=0, request=true, reply=false, msgs=10,000, msgsize=128 B, pubs=10, subs=0, pubsleep=0s, subsleep=0s]
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
13:30:52 Starting publisher, publishing 1,000 messages
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%

Pub stats: 11,522 msgs/sec ~ 1.41 MB/sec
 [1] 1,158 msgs/sec ~ 144.85 KB/sec (1000 msgs)
 [2] 1,158 msgs/sec ~ 144.84 KB/sec (1000 msgs)
 [3] 1,158 msgs/sec ~ 144.79 KB/sec (1000 msgs)
 [4] 1,157 msgs/sec ~ 144.73 KB/sec (1000 msgs)
 [5] 1,157 msgs/sec ~ 144.68 KB/sec (1000 msgs)
 [6] 1,156 msgs/sec ~ 144.62 KB/sec (1000 msgs)
 [7] 1,154 msgs/sec ~ 144.36 KB/sec (1000 msgs)
 [8] 1,153 msgs/sec ~ 144.22 KB/sec (1000 msgs)
 [9] 1,153 msgs/sec ~ 144.13 KB/sec (1000 msgs)
 [10] 1,152 msgs/sec ~ 144.03 KB/sec (1000 msgs)
 min 1,152 | avg 1,155 | max 1,158 | stddev 2 msgs
```

### NATS.jl latency

Start reply service

```
julia> using NATS
julia> nc = NATS.connect();
julia> reply(nc, "foo") do
           "This is a reply."
       end
NATS.Sub("foo", nothing, "PDrH5FOxIgBpcnLO4xHD")
```

Run benchmark with 1 publisher:

```
> nats bench foo --pub 1 --request --msgs 1000
13:28:56 Benchmark in request-reply mode
13:28:56 Starting request-reply benchmark [subject=foo, multisubject=false, multisubjectmax=0, request=true, reply=false, msgs=1,000, msgsize=128 B, pubs=1, subs=0, pubsleep=0s, subsleep=0s]
13:28:56 Starting publisher, publishing 1,000 messages
Finished      0s [================] 100%

Pub stats: 1,565 msgs/sec ~ 195.64 KB/sec
```

Run benchmark with 10 publishers:

```
nats bench foo --pub 10 --request --msgs 10000
13:29:51 Benchmark in request-reply mode
13:29:51 Starting request-reply benchmark [subject=foo, multisubject=false, multisubjectmax=0, request=true, reply=false, msgs=10,000, msgsize=128 B, pubs=10, subs=0, pubsleep=0s, subsleep=0s]
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
13:29:51 Starting publisher, publishing 1,000 messages
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%
Finished      0s [================] 100%

Pub stats: 11,880 msgs/sec ~ 1.45 MB/sec
 [1] 1,204 msgs/sec ~ 150.62 KB/sec (1000 msgs)
 [2] 1,198 msgs/sec ~ 149.85 KB/sec (1000 msgs)
 [3] 1,197 msgs/sec ~ 149.70 KB/sec (1000 msgs)
 [4] 1,194 msgs/sec ~ 149.31 KB/sec (1000 msgs)
 [5] 1,193 msgs/sec ~ 149.20 KB/sec (1000 msgs)
 [6] 1,192 msgs/sec ~ 149.09 KB/sec (1000 msgs)
 [7] 1,192 msgs/sec ~ 149.06 KB/sec (1000 msgs)
 [8] 1,191 msgs/sec ~ 148.91 KB/sec (1000 msgs)
 [9] 1,191 msgs/sec ~ 148.88 KB/sec (1000 msgs)
 [10] 1,188 msgs/sec ~ 148.50 KB/sec (1000 msgs)
 min 1,188 | avg 1,194 | max 1,204 | stddev 4 msgs
```

Results show 1,155 msgs/s for native go library and 1,194 msgs/s NATS.jl, we are good here.

## Publish-Subscribe benchmarks

### Run nats CLI benchmarks

```
> nats bench foo --pub 1 --sub 1 --size 16
13:43:05 Starting Core NATS pub/sub benchmark [subject=foo, multisubject=false, multisubjectmax=0, msgs=100,000, msgsize=16 B, pubs=1, subs=1, pubsleep=0s, subsleep=0s]
13:43:05 Starting subscriber, expecting 100,000 messages
13:43:05 Starting publisher, publishing 100,000 messages
Finished      0s [================] 100%
Finished      0s [================] 100%

NATS Pub/Sub stats: 2,251,521 msgs/sec ~ 34.36 MB/sec
 Pub stats: 1,215,686 msgs/sec ~ 18.55 MB/sec
 Sub stats: 1,154,802 msgs/sec ~ 17.62 MB/sec

```

### Benchmark NATS.jl publish

```
julia> using NATS

julia> nc = NATS.connect();
Threads.threadid() = 
julia> 
julia> Threads.threadid() = 1
Threads.threadid() = 1
julia> 

julia> while true
           for i in 1:100000
            publish(nc, "foo", "This is a payload")
           end
           sleep(0.001)
       end
```

```
> > nats bench foo --sub 1 --size 16
13:46:23 Starting Core NATS pub/sub benchmark [subject=foo, multisubject=false, multisubjectmax=0, msgs=100,000, msgsize=16 B, pubs=0, subs=1, pubsleep=0s, subsleep=0s]
13:46:23 Starting subscriber, expecting 100,000 messages
Finished      0s [================] 100%

Sub stats: 904,350 msgs/sec ~ 13.80 MB/sec
```

0.9M msgs vs 1.2M messages, I think all good here, received messages are buffered and async processed in separate task.

### Benchmark NATS.jl subscribe

Supress warnings

```julia
julia> using Logging

julia> Logging.LogLevel(Error)
Error
```

```julia
using NATS
nc = NATS.connect(send_buffer_limit = 1000000000)
function subscribe_until_timeout(nc::NATS.Connection, timeout = 1.0)
    tm = Timer(timeout)
    counter = 0
    start = nothing
    sub = subscribe(nc, "foo") do
        if isnothing(start)
            start = time()
        end
        counter += 1
    end
    wait(tm)
    unsubscribe(nc, sub)
    if counter == 0
        @info "No messages"
    else
        @info "Processed $counter messages in $(time() - start) s. $(counter / (time() - start)) msgs/sec)"
    end
    counter
end

bench_task = @async begin
    sub_task = Threads.@spawn :default subscribe_until_timeout(nc, 10.0)
    Threads.@spawn :default while !istaskdone(sub_task)
        publish(nc, "foo", "This is payload!")
    end
    wait(sub_task)
    sub_task.result
end
_, tm = @timed wait(bench_task);
received_messages = bench_task.result
@info "$(received_messages / tm) msgs / sec"


```

```

```

Start publisher:


```
> nats bench foo --pub 1 --size 16 --msgs 20000000
13:50:56 Starting Core NATS pub/sub benchmark [subject=foo, multisubject=false, multisubjectmax=0, msgs=20,000,000, msgsize=16 B, pubs=1, subs=0, pubsleep=0s, subsleep=0s]
13:50:56 Starting publisher, publishing 20,000,000 messages
Publishing    3s [==========>-----]  68%
```

```julia
julia> subscribe_for_one_second()
[ Info: Processed 1680882 messages in 0.9680750370025635 s.
```

1,68M messages in NATS.jl vs 1.7M messages by go client.
