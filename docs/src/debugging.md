# Debugging

## Monitoring connection state

```@repl
using NATS
nc = NATS.connect()
@async NATS.status_change(nc) do state
    @info "Connection to $(NATS.clustername(nc)) changed state to $state"
end
NATS.reconnect(nc)
NATS.drain(nc)
```

## Connection an subscription statistics

There are detailed statistics of published and received messages collected.
They can be accessed for each subscription and connection. Connection statistics
aggregates stats for all its subscriptions.

```@repl
using NATS
nc = NATS.connect()
sub1 = subscribe(nc, "topic") do msg
    t = Threads.@spawn publish(nc, "other_topic", payload(msg))
    wait(t)    
end
sub2 = subscribe(nc, "other_topic") do msg
    @show payload(msg)
end
NATS.stats(nc)
publish(nc, "topic", "Hi!")
NATS.stats(nc)
NATS.stats(nc, sub1)
NATS.stats(nc, sub2)
NATS.drain(nc)
```
