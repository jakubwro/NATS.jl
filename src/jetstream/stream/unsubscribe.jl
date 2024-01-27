"""
$(SIGNATURES)

Unsubscribe stream subscription.
"""
function stream_unsubscribe(connection, stream_sub::StreamSub)
    NATS.unsubscribe(connection, stream_sub.sub)
    consumer_delete(connection, stream_sub.consumer)
end
