
function consumer_create_or_update(stream_config::StreamConfiguration; connection, )

end

function consumer_create()

end

function consumer_update()

end

function consumer_ordered()

end

function consumer_delete()

end

function consumer()
    connection::NATS.connection
end

function next(consumer)
    msg = request(nc, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer")

end
