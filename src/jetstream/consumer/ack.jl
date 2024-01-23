# """
# Confirms message delivery to server.
# """
function consumer_ack(msg::NATS.Msg; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`ack` sent for message that doesn't need acknowledgement." 
    NATS.request(connection, msg.reply_to) # TODO: add retry in case of 503
end

# """
# Mark message as undelivered, what avoid waiting for timeout before redelivery.
# """
function consumer_nak(msg::NATS.Msg; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`nak` sent for message that doesn't need acknowledgement." 
    NATS.publish(connection, msg.reply_to, "-NAK")# TODO: add retry in case of 503
end
