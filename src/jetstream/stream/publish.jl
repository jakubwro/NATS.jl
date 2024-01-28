const DEFAULT_STREAM_PUBLISH_DELAYS = ExponentialBackOff(n = 7, first_delay = 0.1, max_delay = 0.5)

"""
$(SIGNATURES)

Publish a message to stream.
"""
function stream_publish(connection::NATS.Connection, subject, data; delays = DEFAULT_STREAM_PUBLISH_DELAYS)
    jetstream_api_call(PubAck, connection, subject, data; delays)
end
