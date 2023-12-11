# Quick examples

Start nats-server:

```
docker run -p 4222:4222 nats:latest
```

## Publish subscribe

```julia-repl
julia> using NATS

julia> NATS.connect(default = true)
NATS.Connection(unnamed cluster, CONNECTED, 0 subs, 0 unsubs)

julia> sub = subscribe("test_subject") do msg
                  @show payload(msg)
              end
NATS.Sub("test_subject", nothing, "48ibFL")

julia> publish("test_subject"; payload="Hello.")

payload(msg) = "Hello."

julia> unsubscribe(sub)
NATS.Unsub("48ibFL", nothing)

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
NATS.Connection(unnamed cluster, CONNECTED, 0 subs, 0 unsubs)

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
NATS.Sub("some_subject", "group1", "I5i09o")

julia> reply("some_subject"; queue_group="group1") do
           "Reply from worker 2"
       end
NATS.Sub("some_subject", "group1", "q79h2T")

julia> rep = request("some_subject");

julia> payload(rep)
"Reply from worker 2"

julia> rep = request("some_subject");

julia> payload(rep)
"Reply from worker 1"

julia> rep = request(String, "some_subject")
"Reply from worker 1"

julia> rep = request(String, "some_subject")
"Reply from worker 2"

julia> rep = request(String, "some_subject")
"Reply from worker 2"

julia> rep = request(String, "some_subject")
"Reply from worker 2"

julia> rep = request(String, "some_subject")
"Reply from worker 1"

julia> rep = request(String, "some_subject")
"Reply from worker 1"
```