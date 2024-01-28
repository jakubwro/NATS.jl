
function check_stream_publish_error(s, e)
    # Status 503 may indicate cluster leader is down, retry some time till new one is elected.
    e isa Union{NATS.NATSError, ApiError} && e.code == 503
end


const DEFAULT_STREAM_PUBLISH_DELAYS = ExponentialBackOff(n = typemax(Int64), first_delay = 0.2, max_delay = 0.5)
"""
$(SIGNATURES)

Publish a message to stream.
"""
function stream_publish(connection::NATS.Connection, subject, data; delays = DEFAULT_STREAM_PUBLISH_DELAYS)
    publish_retry = retry(NATS.request; delays, check = check_stream_publish_error)
    publish_retry(PubAck, connection, subject, data)
end
