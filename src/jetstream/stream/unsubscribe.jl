
function stream_unsubscribe(connection, subscription::Tuple{NATS.Sub, JetStream.ConsumerInfo})
    sub, cons = subscription
    NATS.unsubscribe(connection, sub)
    delete(connection, cons)
end
