
"""
$(SIGNATURES)

Publish a message to stream.
"""
function stream_publish(connection::NATS.Connection, subject, data)
    jetstream_api_call(PubAck, connection, subject, data)
end
