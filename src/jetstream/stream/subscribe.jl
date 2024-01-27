

# Subscribe to a stream by creating a consumer.
# Might be more performant to configure republish subject on steram.
"""
$(SIGNATURES)

Subscribe to a stream.
"""
function stream_subscribe(f, connection, subject)
    subject_streams = stream_infos(connection, subject)
    if isempty(subject_streams)
        error("No stream found for subject `$subject`")
    end
    if length(subject_streams) > 1
        error("Multiple streams found")
    end
    stream = only(subject_streams)
    name = randstring(20)
    deliver_subject = randstring(8)
    idle_heartbeat = 1000 * 1000 * 1000 * 3 # 300 ms
    consumer_config = ConsumerConfiguration(;name, deliver_subject) # TODO: filter subject
    consumer = consumer_create(connection, consumer_config, stream)
    f_typed = NATS._fast_call(f)
    sub = NATS.subscribe(connection, deliver_subject) do msg
        if NATS.statuscode(msg) == 100
            @info "heartbeat"
        else
            f_typed(msg)
        end
    end
    StreamSub(sub, consumer)
end
