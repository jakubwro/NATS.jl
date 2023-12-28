# Quick examples

Start nats-server:

```
docker run -p 4222:4222 nats:latest
```

## Publish subscribe

```julia
julia> using NATS

julia> nc = NATS.connect(default = true)
NATS.Connection(unnamed cluster, CONNECTED, 0 subs, 0 unsubs)

julia> sub = subscribe(nc, "test_subject") do msg
                  @show payload(msg)
              end
NATS.Sub("test_subject", nothing, "48ibFL")

julia> publish(nc, "test_subject"; payload="Hello.")

payload(msg) = "Hello."

julia> unsubscribe(nc, sub)
NATS.Unsub("48ibFL", nothing)

julia> publish(nc, "test_subject"; payload="Hello.")

julia> 
```

## Request reply

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```julia-repl
julia> using NATS

julia> nc = NATS.connect()
NATS.Connection(unnamed cluster, CONNECTED, 0 subs, 0 unsubs)

julia> rep = @time NATS.request(nc, "help.please");
  0.002072 seconds (174 allocations: 10.711 KiB)

julia> payload(rep)
"OK, I CAN HELP!!!"
```

### Reliable message delivery with request-reply pattern

NATS protocol does not guarantee message delivery. Simple ack mechanism may be implemented like this.

```julia

function try_publish(connection, subject::String, data)
    resp = NATS.request(connection, subject, data)
    if NATS.payload(resp) != "ack"
        error("No ack received")
    end
end

function reliable_publish(connection, subject::String, data)
    retry_request = retry(try_publish, delays=zeros(10)) # Retry 10 times without delay.
    retry_request(connection, subject, data)
end
```

On receiver "ack" payload is returned on success.

```julia
reply(connection, "some_subject") do msg
    # Do some stuff with message here.
    "ack"
end
```

## Work queues

If `subscription` or `reply` is configured with `queue_group`, messages will be distributed equally between subscriptions with the same group.

```julia
julia> reply(connection, "some_subject"; queue_group="group1") do
           "Reply from worker 1"
       end
NATS.Sub("some_subject", "group1", "I5i09o")

julia> reply(connection, "some_subject"; queue_group="group1") do
           "Reply from worker 2"
       end
NATS.Sub("some_subject", "group1", "q79h2T")

julia> rep = request(connection, "some_subject");

julia> payload(rep)
"Reply from worker 2"

julia> rep = request(connection, "some_subject");

julia> payload(rep)
"Reply from worker 1"

julia> rep = request(connection, String, "some_subject")
"Reply from worker 1"

julia> rep = request(connection, String, "some_subject")
"Reply from worker 2"

julia> rep = request(connection, String, "some_subject")
"Reply from worker 2"

julia> rep = request(connection, String, "some_subject")
"Reply from worker 2"

julia> rep = request(connection, String, "some_subject")
"Reply from worker 1"

julia> rep = request(connection, String, "some_subject")
"Reply from worker 1"
```