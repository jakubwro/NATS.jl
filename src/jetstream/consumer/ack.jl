# """
# Confirms message delivery to server.
# """
function message_ack(msg::NATS.Msg; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`ack` sent for message that don't need acknowledgement." 
    NATS.publish(connection, msg.reply_to)
end

# """
# Mark message as undelivered, what avoid waiting for timeout before redelivery.
# """
function message_nak(msg::NATS.Msg; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`nak` sent for message that don't need acknowledgement." 
    NATS.publish(connection, msg.reply_to, "-NAK")
end
