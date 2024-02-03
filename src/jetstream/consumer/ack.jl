
# https://docs.nats.io/using-nats/developer/develop_jetstream/model_deep_dive#acknowledgement-models 

const CONSUMER_ACK_OPTIONS = [ "+ACK", "-NAK", "+WPI", "+NXT", "+TERM" ]

"""
$(SIGNATURES)

Confirms message delivery to server.
"""
function consumer_ack(connection::NATS.Connection, msg::NATS.Msg, ack::String = "+ACK"; delays = DEFAULT_API_CALL_DELAYS)
    ack in CONSUMER_ACK_OPTIONS || error("Unknown ack type \"$ack\", allowed values: $(join(CONSUMER_ACK_OPTIONS, ", "))")
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`ack` sent for message that doesn't need acknowledgement." 
    jetstream_api_call(NATS.Msg, connection, msg.reply_to; delays)
end
