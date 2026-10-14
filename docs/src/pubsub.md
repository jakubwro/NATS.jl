
# Publish - Subscribe

Functions implementing the [NATS Publish-Subscribe](https://docs.nats.io/nats-concepts/core-nats/pubsub) distribution model. For [queue group](https://docs.nats.io/nats-concepts/core-nats/queue) `1:1` instead of the default `1:N` fanout configure subscriptions with the same `queue_group` argument.

```@docs
publish
subscribe
next
unsubscribe
drain
```
