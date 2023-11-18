# Quick examples

Start nats-server:

```
docker run -p 4222:4222 nats:latest
```

## Publish subscribe

```julia-repl
julia> using NATS

julia> NATS.connect(default = true)
NATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs, 0 outbox)

julia> sub = subscribe(nc, "test_subject") do msg
                  @show payload(msg)
              end
NATS.Sub("test_subject", nothing, "Z8bTW3WlXMTF5lYi640j")

julia> publish("test_subject"; payload="Hello.")

payload(msg) = "Hello."

julia> unsubscribe(sub)
NATS.Unsub("Z8bTW3WlXMTF5lYi640j", nothing)

julia> publish("test_subject"; payload="Hello.")

julia> 
```

## Request reply

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```julia-repl
julia> using NATS

julia> NATS.connect(default = true)
NATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs, 0 outbox)

julia> rep = @time NATS.request("help.please");
  0.002072 seconds (174 allocations: 10.711 KiB)

julia> payload(rep)
"OK, I CAN HELP!!!"
```

# Work queues

If `subscription` or `reply` is configured with `queue_group`, messages will be distributed equally between subscriptions with the same group.

```
julia> reply("some_subject"; queue_group="group1") do
           "Reply from worker 1"
       end
NATS.Sub("some_subject", "group1", "711R7LpDEZrEJxLRZYCY")

julia> reply("some_subject"; queue_group="group1") do
           "Reply from worker 2"
       end

julia> rep = request("some_subject")
NATS.Msg("inbox.TV4SZSpnoy", "zn9pM2R57PShuJgklOA5", nothing, 19, "Reply from worker 2")

julia> rep = request("some_subject")
NATS.Msg("inbox.Yu3nU5StiI", "PmplJhL6o63DenNcYl0P", nothing, 19, "Reply from worker 1")

julia> rep = request("some_subject")
NATS.Msg("inbox.64Ezpek0Iz", "SwmKsA3x2tvyRGEVSgFz", nothing, 19, "Reply from worker 2")

julia> rep = request("some_subject")
NATS.Msg("inbox.jG2OeV9ej9", "8IZ8SjPWaaOgJIx0HfUg", nothing, 19, "Reply from worker 1")
```