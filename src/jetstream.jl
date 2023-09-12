@enum AckPolicy EXPLICIT

"""
https://docs.nats.io/reference/reference-protocols/nats_api_reference
"""

function next(nc::Connection, stream::String, consumer::String)
    msg = request(nc, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer")
end

function ack(nc::Connection, msg::Msg)
    publish(nc, msg.reply_to)
end

function nak(nc::Connection, msg::Msg)
    publish(nc, msg.reply_to; payload = "-NAK")
end