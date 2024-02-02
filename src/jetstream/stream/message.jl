
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

"""
$(SIGNATURES)

Get a message from stream.
"""
function stream_message_get(connection::NATS.Connection, stream_name::String, subject::String; allow_direct = nothing)
    allow_direct = @something allow_direct check_allow_direct(connection, stream_name)
    if allow_direct
        msg = NATS.request(connection, "\$JS.API.DIRECT.GET.$(stream_name)", "{\"last_by_subj\": \"$subject\"}")
        msg_status = NATS.statuscode(msg) 
        msg_status >= 400 && throw(NATSError(msg_status, ""))
        msg
    else
        res = NATS.request(connection, "\$JS.API.STREAM.MSG.GET.$(stream_name)", "{\"last_by_subj\": \"$subject\"}")
        json = JSON3.read(NATS.payload(res))
        if haskey(json, :error)
            throw(StructTypes.constructfrom(ApiError, json.error))
        end
        subject = json.message.subject
        hdrs = haskey(json.message, :hdrs) ? base64decode(json.message.hdrs) : UInt8[]
        append!(hdrs, "Nats-Stream: $(stream_name)\r\n")
        append!(hdrs, "Nats-Subject: $(json.message.subject)\r\n")
        append!(hdrs, "Nats-Sequence: $(json.message.seq)\r\n")
        append!(hdrs, "Nats-Time-Stamp: $(json.message.time)\r\n")
        payload = base64decode(json.message.data)
        NATS.Msg(res.subject, res.sid, nothing, length(hdrs), vcat(hdrs, payload))
    end
end

"""
$(SIGNATURES)

Get a message from stream.
"""
function stream_message_get(connection::NATS.Connection, stream::StreamInfo, subject::String)
    stream_message_get(connection, stream.config.name, subject; stream.config.allow_direct)
end

"""
$(SIGNATURES)

Delete a message from stream.
"""
function stream_message_delete(connection::NATS.Connection, stream::StreamInfo, msg::NATS.Msg)
    seq = NATS.header(msg, "Nats-Sequence")
    isnothing(seq) && error("Message has no `Nats-Sequence` header")
    # TODO: validate stream name
    req = Dict()
    req[:seq] = parse(UInt8, seq)
    req[:no_erase] = true
    NATS.request(ApiResult, connection, "\$JS.API.STREAM.MSG.DELETE.$(stream.config.name)", JSON3.write(req))
end
