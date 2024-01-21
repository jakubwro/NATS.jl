
function stream_message_get(connection::NATS.Connection, stream::StreamInfo, subject)
    if stream.config.allow_direct
        m = NATS.request(connection, "\$JS.API.DIRECT.GET.$(stream.config.name)", "{\"last_by_subj\": \"$subject\"}")
        #TODO: structured NATSError
        m
    else
        @warn "not working"
        res = NATS.request(connection, "\$JS.API.STREAM.MSG.GET.$(stream.config.name)", "{\"last_by_subj\": \"$subject\"}")
        @show res
        json = JSON3.read(NATS.payload(res))
        throw(StructTypes.constructfrom(ApiError, json.error))
        #TODO: implement
        # first(replies)
    end
end

function stream_message_delete(stream_name::String, seq::UInt64; connection = NATS.connection(:default))
    replies = NATS.request(connection, "\$JS.API.STREAM.MSG.DELETE.$stream_name", "{\"seq\": \"\$KV.asdf.$subject\"}", 1)
    isempty(replies) && error("No replies.")
    first(replies)
end
