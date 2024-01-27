
function check_stream_publish_error(s, e)
    # Status 503 may indicate cluster leader is down, retry some time till new one is elected.
    e isa NATS.NATSError && e.code == 503
end

"""
$(SIGNATURES)

Publish a message to stream.
"""
function stream_publish(connection::NATS.Connection, subject, data; delays = ExponentialBackOff(n = 3, first_delay = 0.2, max_delay = 0.5))
    # ack_msg = _try_request(subject, data; connection)
    publish_retry = retry(NATS.request; delays, check = check_stream_publish_error)
    ack_msg = publish_retry(connection, subject, data)
    json = JSON3.read(NATS.payload(ack_msg))
    haskey(json, :error) && throw(StructTypes.constructfrom(ApiError, json.error))
    StructTypes.constructfrom(PubAck, json)
end
