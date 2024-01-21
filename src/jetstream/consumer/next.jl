const DEFAULT_NEXT_TIMEOUT_SECONDS = 5

function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo; no_wait = false, timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS), batch = 1)
    req = Dict()
    req[:no_wait] = no_wait
    req[:batch] = batch
    subject = "\$JS.API.CONSUMER.MSG.NEXT.$(consumer.stream_name).$(consumer.name)"
    msgs = NATS.request(connection, batch, subject, JSON3.write(req); timer)
    isempty(msgs) && error("No replies.") # TODO NATSError
    msg = first(msgs)
    # @show msg.reply_to
    msg
end
