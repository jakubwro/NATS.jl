"""
$(SIGNATURES)

Confirms message delivery to server.
"""
function consumer_ack(connection::NATS.Connection, msg::NATS.Msg)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`ack` sent for message that doesn't need acknowledgement." 
    jetstream_api_call(NATS.Msg, connection, msg.reply_to)
end

"""
$(SIGNATURES)

Mark message as undelivered, what avoid waiting for timeout before redelivery.
"""
function consumer_nak(connection::NATS.Connection, msg::NATS.Msg)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`nak` sent for message that doesn't need acknowledgement." 
    jetstream_api_call(NATS.Msg, connection, msg.reply_to, "-NAK")
end
