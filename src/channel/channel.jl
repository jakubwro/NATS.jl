
const NATS_CHANNEL_SUBJECT_PREFIX = "JLCH"
const NATS_CHANNEL_QUEUEGROUP_PREFIX = "JLCHQG"
const NATS_CHANNEL_PUT_DELAYS = Base.ExponentialBackOff(n=220752000000000000, first_delay=0.0001, max_delay=2.0)
const NATS_CHANNEL_PUT_REQUEST_TIMEOUT = 2


@kwdef struct NATSChannel{T} <: AbstractChannel{T}
    subject::String
    connection::NATS.Connection = NATS.connection(:default)
end

function NATSChannel(subject::String; connection::NATS.Connection = NATS.connection(:default))
    NATSChannel{Msg}(subject, connection)
end

function put_or_throw(ch::NATSChannel, data)
    subject = "$(NATS_CHANNEL_SUBJECT_PREFIX).$(ch.subject)"
    connection = ch.connection
    timer = Timer(NATS_CHANNEL_PUT_REQUEST_TIMEOUT)
    res = request(subject, data; connection, timer)
    if payload(res) != "ack"
        error("No ack received.")
    end
end

function put!(ch::NATSChannel{T}, data) where T
    if T != Msg && !(data isa T)
        error("Cannot put $(typeof(data)) to channel of type $T")
    end
    retry_put = retry(put_or_throw, delays = NATS_CHANNEL_PUT_DELAYS)
    retry_put(ch, data)
end

function take!(ch::NATSChannel{T}) where T
    received = nothing
    cond = Threads.Condition()
    sub = nothing
    canceled = false
    subject = "$(NATS_CHANNEL_SUBJECT_PREFIX).$(ch.subject)"
    queue_group = "$(NATS_CHANNEL_QUEUEGROUP_PREFIX).$(ch.subject)"
    connection = ch.connection
    try
        sub = reply(subject; queue_group, connection) do msg
            @lock cond begin
                received = msg
                resp = canceled ? "nak" : "ack"
                canceled = true # After first msg do not accept another one.
                notify(cond)
                resp
            end
        end
        unsubscribe(sub; max_msgs = 1, connection)
        @lock cond begin
            isnothing(received) && wait(cond)
            canceled = true
        end
    catch
        canceled = true
        rethrow()
    finally
        isnothing(sub) || unsubscribe(sub)
    end
    convert(T, received)
end
