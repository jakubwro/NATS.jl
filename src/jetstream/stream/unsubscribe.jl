"""
$(SIGNATURES)

Unsubscribe stream subscription.
"""
function stream_unsubscribe(connection, subscription::Tuple{NATS.Sub, JetStream.ConsumerInfo})
    sub, cons = subscription
    NATS.unsubscribe(connection, sub)
    consumer_delete(connection, cons)
end
