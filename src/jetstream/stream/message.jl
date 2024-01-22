
function check_allow_direct(connection::NATS.Connection, stream_name::String)
    @lock connection.allow_direct_lock begin
        cached = get(connection.allow_direct, stream_name, nothing)
        if !isnothing(cached)
            cached
        else
            stream = stream_info(connection, stream_name)
            connection.allow_direct[stream_name] = stream.config.allow_direct
            stream.config.allow_direct
        end
    end
end

function stream_message_get(connection::NATS.Connection, stream_name::String, subject::String; allow_direct = nothing)
    allow_direct = @something allow_direct check_allow_direct(connection, stream_name)
    if allow_direct
        m = NATS.request(connection, "\$JS.API.DIRECT.GET.$(stream_name)", "{\"last_by_subj\": \"$subject\"}")
        #TODO: structured NATSError
        m
    else
        @warn "not working"
        res = NATS.request(connection, "\$JS.API.STREAM.MSG.GET.$(stream_name)", "{\"last_by_subj\": \"$subject\"}")
        @show res
        json = JSON3.read(NATS.payload(res))
        throw(StructTypes.constructfrom(ApiError, json.error))
        #TODO: implement
        # first(replies)
    end
end

function stream_message_get(connection::NATS.Connection, stream::StreamInfo, subject::String)
    stream_message_get(connection, stream.config.name, subject; stream.config.allow_direct)
end


function stream_message_delete(stream_name::String, seq::UInt64; connection = NATS.connection(:default))
    replies = NATS.request(connection, "\$JS.API.STREAM.MSG.DELETE.$stream_name", "{\"seq\": \"\$KV.asdf.$subject\"}", 1)
    isempty(replies) && error("No replies.")
    first(replies)
end
