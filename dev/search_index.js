var documenterSearchIndex = {"docs":
[{"location":"protocol/#Protocol-messages","page":"Protocol messages","title":"Protocol messages","text":"","category":"section"},{"location":"protocol/","page":"Protocol messages","title":"Protocol messages","text":"NATS.Info\nNATS.Connect\nNATS.Pub\nNATS.HPub\nNATS.Sub\nNATS.Unsub\nNATS.Msg\nNATS.HMsg\nNATS.Ping\nNATS.Pong\nNATS.Err\nNATS.Ok","category":"page"},{"location":"protocol/#NATS.Info","page":"Protocol messages","title":"NATS.Info","text":"A client will need to start as a plain TCP connection, then when the server accepts a connection from the client, it will send information about itself, the configuration and security requirements necessary for the client to successfully authenticate with the server and exchange messages. When using the updated client protocol (see CONNECT below), INFO messages can be sent anytime by the server. This means clients with that protocol level need to be able to asynchronously handle INFO messages.\n\nserver_id::String: The unique identifier of the NATS server.\nserver_name::String: The name of the NATS server.\nversion::String: The version of NATS.\ngo::String: The version of golang the NATS server was built with.\nhost::String: The IP address used to start the NATS server, by default this will be 0.0.0.0 and can be configured with -client_advertise host:port.\nport::Int64: The port number the NATS server is configured to listen on.\nheaders::Bool: Whether the server supports headers.\nmax_payload::Int64: Maximum payload size, in bytes, that the server will accept from the client.\nproto::Int64: An integer indicating the protocol version of the server. The server version 1.2.0 sets this to 1 to indicate that it supports the \"Echo\" feature.\nclient_id::Union{Nothing, UInt64}: The internal client identifier in the server. This can be used to filter client connections in monitoring, correlate with error logs, etc...\nauth_required::Union{Nothing, Bool}: If this is true, then the client should try to authenticate upon connect.\ntls_required::Union{Nothing, Bool}: If this is true, then the client must perform the TLS/1.2 handshake. Note, this used to be ssl_required and has been updated along with the protocol from SSL to TLS.\ntls_verify::Union{Nothing, Bool}: If this is true, the client must provide a valid certificate during the TLS handshake.\ntls_available::Union{Nothing, Bool}: If this is true, the client can provide a valid certificate during the TLS handshake.\nconnect_urls::Union{Nothing, Vector{String}}: List of server urls that a client can connect to.\nws_connect_urls::Union{Nothing, Vector{String}}: List of server urls that a websocket client can connect to.\nldm::Union{Nothing, Bool}: If the server supports Lame Duck Mode notifications, and the current server has transitioned to lame duck, ldm will be set to true.\ngit_commit::Union{Nothing, String}: The git hash at which the NATS server was built.\njetstream::Union{Nothing, Bool}: Whether the server supports JetStream.\nip::Union{Nothing, String}: The IP of the server.\nclient_ip::Union{Nothing, String}: The IP of the client.\nnonce::Union{Nothing, String}: The nonce for use in CONNECT.\ncluster::Union{Nothing, String}: The name of the cluster.\ndomain::Union{Nothing, String}: The configured NATS domain of the server.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Connect","page":"Protocol messages","title":"NATS.Connect","text":"The CONNECT message is the client version of the INFO message. Once the client has established a TCP/IP socket connection with the NATS server, and an INFO message has been received from the server, the client may send a CONNECT message to the NATS server to provide more information about the current connection as well as security information.\n\nverbose::Bool: Turns on +OK protocol acknowledgements.\npedantic::Bool: Turns on additional strict format checking, e.g. for properly formed subjects.\ntls_required::Bool: Indicates whether the client requires an SSL connection.\nauth_token::Union{Nothing, String}: Client authorization token.\nuser::Union{Nothing, String}: Connection username.\npass::Union{Nothing, String}: Connection password.\nname::Union{Nothing, String}: Client name.\nlang::String: The implementation language of the client.\nversion::String: The version of the client.\nprotocol::Union{Nothing, Int64}: Sending 0 (or absent) indicates client supports original protocol. Sending 1 indicates that the client supports dynamic reconfiguration of cluster topology changes by asynchronously receiving INFO messages with known servers it can reconnect to.\necho::Union{Nothing, Bool}: If set to false, the server (version 1.2.0+) will not send originating messages from this connection to its own subscriptions. Clients should set this to false only for server supporting this feature, which is when proto in the INFO protocol is set to at least 1.\nsig::Union{Nothing, String}: In case the server has responded with a nonce on INFO, then a NATS client must use this field to reply with the signed nonce.\njwt::Union{Nothing, String}: The JWT that identifies a user permissions and account.\nno_responders::Union{Nothing, Bool}: Enable quick replies for cases where a request is sent to a topic with no responders.\nheaders::Union{Nothing, Bool}: Whether the client supports headers.\nnkey::Union{Nothing, String}: The public NKey to authenticate the client. This will be used to verify the signature (sig) against the nonce provided in the INFO message.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Pub","page":"Protocol messages","title":"NATS.Pub","text":"The PUB message publishes the message payload to the given subject name, optionally supplying a reply subject. If a reply subject is supplied, it will be delivered to eligible subscribers along with the supplied payload. Note that the payload itself is optional. To omit the payload, set the payload size to 0, but the second CRLF is still required.\n\nsubject::String: The destination subject to publish to.\nreply_to::Union{Nothing, String}: The reply subject that subscribers can use to send a response back to the publisher/requestor.\nbytes::Int64: The payload size in bytes.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.HPub","page":"Protocol messages","title":"NATS.HPub","text":"The HPUB message is the same as PUB but extends the message payload to include NATS headers. Note that the payload itself is optional. To omit the payload, set the total message size equal to the size of the headers. Note that the trailing CR+LF is still required.\n\nsubject::String: The destination subject to publish to.\nreply_to::Union{Nothing, String}: The reply subject that subscribers can use to send a response back to the publisher/requestor.\nheader_bytes::Int64: The size of the headers section in bytes including the ␍␊␍␊ delimiter before the payload.\ntotal_bytes::Int64: The total size of headers and payload sections in bytes.\nheaders::Union{Nothing, String}: Header version NATS/1.0␍␊ followed by one or more name: value pairs, each separated by ␍␊.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Sub","page":"Protocol messages","title":"NATS.Sub","text":"SUB initiates a subscription to a subject, optionally joining a distributed queue group.\n\nsubject::String: The subject name to subscribe to.\nqueue_group::Union{Nothing, String}: If specified, the subscriber will join this queue group.\nsid::String: A unique alphanumeric subscription ID, generated by the client.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Unsub","page":"Protocol messages","title":"NATS.Unsub","text":"UNSUB unsubscribes the connection from the specified subject, or auto-unsubscribes after the specified number of messages has been received.\n\nsid::String: The unique alphanumeric subscription ID of the subject to unsubscribe from.\nmax_msgs::Union{Nothing, Int64}: A number of messages to wait for before automatically unsubscribing.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Msg","page":"Protocol messages","title":"NATS.Msg","text":"The MSG protocol message is used to deliver an application message to the client.\n\nsubject::String: Subject name this message was received on.\nsid::String: The unique alphanumeric subscription ID of the subject.\nreply_to::Union{Nothing, String}: The subject on which the publisher is listening for responses.\nbytes::Int64: Size of the payload in bytes.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.HMsg","page":"Protocol messages","title":"NATS.HMsg","text":"The HMSG message is the same as MSG, but extends the message payload with headers. See also ADR-4 NATS Message Headers.\n\nsubject::String: Subject name this message was received on.\nsid::String: The unique alphanumeric subscription ID of the subject.\nreply_to::Union{Nothing, String}: The subject on which the publisher is listening for responses.\nheader_bytes::Int64: The size of the headers section in bytes including the ␍␊␍␊ delimiter before the payload.\ntotal_bytes::Int64: The total size of headers and payload sections in bytes.\nheaders::Union{Nothing, String}: Header version NATS/1.0␍␊ followed by one or more name: value pairs, each separated by ␍␊.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Ping","page":"Protocol messages","title":"NATS.Ping","text":"PING and PONG implement a simple keep-alive mechanism between client and server.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Pong","page":"Protocol messages","title":"NATS.Pong","text":"PING and PONG implement a simple keep-alive mechanism between client and server.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Err","page":"Protocol messages","title":"NATS.Err","text":"The -ERR message is used by the server indicate a protocol, authorization, or other runtime connection error to the client. Most of these errors result in the server closing the connection.\n\nmessage::String: Error message.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Ok","page":"Protocol messages","title":"NATS.Ok","text":"When the verbose connection option is set to true (the default value), the server acknowledges each well-formed protocol message from the client with a +OK message.\n\n\n\n\n\n","category":"type"},{"location":"design/#Design-notes","page":"Design notes","title":"Design notes","text":"","category":"section"},{"location":"design/#Parsing","page":"Design notes","title":"Parsing","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Benchmark after any changes to parsing, \"4k requests\" is a good test case.","category":"page"},{"location":"design/#Use-split","page":"Design notes","title":"Use split","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Avoid using regex, split is used to extract protocol data. Some performance might be squeezed by avoiding conversion from SubString to String but it will be observable only for huge payloads.","category":"page"},{"location":"design/#Use-strings-not-raw-bytes","page":"Design notes","title":"Use strings not raw bytes","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Parser is not returning raw bytes but rather String. This fast thanks to how String constructor works.","category":"page"},{"location":"design/","page":"Design notes","title":"Design notes","text":"julia> bytes = UInt8['a', 'b', 'c'];\n\njulia> str = String(bytes)\n\"abc\"\n\njulia> bytes\nUInt8[]\n\njulia> @doc String\n  ...\n  When possible, the memory of v will be used without copying when the String object is created.\n  This is guaranteed to be the case for byte vectors returned by take! on a writable IOBuffer\n  and by calls to read(io, nb). This allows zero-copy conversion of I/O data to strings. In\n  other cases, Vector{UInt8} data may be copied, but v is truncated anyway to guarantee\n  consistent behavior.\n  ...","category":"page"},{"location":"pubsub/#Publish-subscribe","page":"Publish - subscribe","title":"Publish - subscribe","text":"","category":"section"},{"location":"pubsub/","page":"Publish - subscribe","title":"Publish - subscribe","text":"publish\nsubscribe\nunsubscribe","category":"page"},{"location":"pubsub/#NATS.publish","page":"Publish - subscribe","title":"NATS.publish","text":"publish(nc, subject; reply_to, payload, headers)\n\n\nPublish message to a subject.\n\n\n\n\n\npublish(subject; reply_to, payload, headers)\n\n\nPublish message to a subject with default connection.\n\n\n\n\n\n","category":"function"},{"location":"pubsub/#NATS.subscribe","page":"Publish - subscribe","title":"NATS.subscribe","text":"subscribe(f, nc, subject; queue_group)\n\n\nSubscribe to a subject.\n\n\n\n\n\nsubscribe(f, subject; queue_group)\n\n\nSubscribe to a subject with default connection.\n\n\n\n\n\n","category":"function"},{"location":"pubsub/#NATS.unsubscribe","page":"Publish - subscribe","title":"NATS.unsubscribe","text":"unsubscribe(nc, sub; max_msgs)\n\n\nUnsubscrible from a subject.\n\n\n\n\n\nunsubscribe(sub; max_msgs)\n\n\nUnsubscrible from with default connection.\n\n\n\n\n\n","category":"function"},{"location":"reqreply/#Request-reply","page":"Request - reply","title":"Request - reply","text":"","category":"section"},{"location":"reqreply/","page":"Request - reply","title":"Request - reply","text":"request\nreply","category":"page"},{"location":"reqreply/#NATS.request","page":"Request - reply","title":"NATS.request","text":"request(nc, subject)\nrequest(nc, subject, data; timer)\n\n\nSend NATS Request-Reply message.\n\nDefault timeout is 5 seconds which can be overriden by passing timer.\n\nExamples\n\njulia> NATS.request(nc, \"help.please\")\nNATS.Msg(\"l9dKWs86\", \"7Nsv5SZs\", nothing, 17, \"OK, I CAN HELP!!!\")\n\njulia> request(nc, \"help.please\"; timer = Timer(0))\nERROR: No replies received.\n\njulia> request(nc, \"help.please\", nreplies = 2; timer = Timer(0))\nNATS.Msg[]\n\n\n\n\n\nrequest(subject, data, nreplies; timer)\n\n\nThe same as above but uses implicit connection (this functionality to be defined yet).\n\n\n\n\n\n","category":"function"},{"location":"reqreply/#NATS.reply","page":"Request - reply","title":"NATS.reply","text":"Reply for messages for a subject. Works like subscribe with automatic publish to the subject from reply_to field.\n\nreply(f, nc, subject; queue_group, info)\n\n\nExamples\n\njulia> sub = reply(\"FOO.REQUESTS\") do msg\n    \"This is a reply payload.\"\nend\nNATS.Sub(\"FOO.REQUESTS\", nothing, \"jdnMEcJN\")\n\njulia> sub = reply(\"FOO.REQUESTS\") do msg\n    \"This is a reply payload.\", [\"example_header\" => \"This is a header value\"]\nend\nNATS.Sub(\"FOO.REQUESTS\", nothing, \"jdnMEcJN\")\n\njulia> unsubscribe(sub)\n\n\n\n\n\nThe same as above but uses implicit connection (this functionality to be defined yet).\n\nreply(f, subject; queue_group, info)\n\n\nExamples\n\njulia> nc = NATS.connect()\nNATS.Connection(CONNECTED, 0 subs, 0 unsubs, 0 outbox)\n\njulia> sub = reply(nc, \"FOO.REQUESTS\") do msg\n    \"This is a reply payload.\"\nend\n\n\n\n\n\n","category":"function"},{"location":"#NATS.jl","page":"NATS.jl","title":"NATS.jl","text":"","category":"section"},{"location":"","page":"NATS.jl","title":"NATS.jl","text":"NATS client for Julia.","category":"page"},{"location":"#Quick-examples","page":"NATS.jl","title":"Quick examples","text":"","category":"section"},{"location":"#Publish-subscribe","page":"NATS.jl","title":"Publish subscribe","text":"","category":"section"},{"location":"","page":"NATS.jl","title":"NATS.jl","text":"julia> using NATS\n\njulia> nc = NATS.connect(\"localhost\", 4222)\nNATS.Connection(CONNECTED, 0 subs, 0 unsubs, 0 outbox)\n\njulia> sub = subscribe(nc, \"test_subject\") do msg\n                  @show payload(msg)\n              end\nNATS.Sub(\"test_subject\", nothing, \"TeQmd23Z\")\n\njulia> publish(nc, \"test_subject\"; payload=\"Hello.\")\nNATS.Pub(\"test_subject\", nothing, 6, \"Hello.\")\n\npayload(msg) = \"Hello.\"","category":"page"},{"location":"#Request-reply","page":"NATS.jl","title":"Request reply","text":"","category":"section"},{"location":"","page":"NATS.jl","title":"NATS.jl","text":"> nats reply help.please 'OK, I CAN HELP!!!'\n\n20:35:19 Listening on \"help.please\" in group \"NATS-RPLY-22\"","category":"page"},{"location":"","page":"NATS.jl","title":"NATS.jl","text":"julia> using NATS\n\njulia> nc = NATS.connect(\"localhost\", 4222)\nNATS.Connection(CONNECTED, 0 subs, 0 unsubs, 0 outbox)\n\njulia> rep = @time NATS.request(nc, \"help.please\");\n  0.006738 seconds (88 allocations: 4.969 KiB)\n\njulia> payload(rep)\n\"OK, I CAN HELP!!!\"","category":"page"},{"location":"#JetStream-pull-consumer.","page":"NATS.jl","title":"JetStream pull consumer.","text":"","category":"section"},{"location":"","page":"NATS.jl","title":"NATS.jl","text":"> nats stream add TEST_STREAM\n? Subjects to consume FOO.*\n...\n\n> nats consumer add\n? Consumer name TestConsumerConsume\n...\n\n> nats pub FOO.bar --count=1 \"publication #{{Count}} @ {{TimeStamp}}\"\n20:25:18 Published 42 bytes to \"FOO.bar\"","category":"page"},{"location":"","page":"NATS.jl","title":"NATS.jl","text":"julia> using NATS\n\njulia> nc = NATS.connect(\"localhost\", 4222);\n\njulia> msg = NATS.next(nc,\"TEST_STREAM\", \"TestConsumerConsume\");\n\njulia> payload(msg)\n\"publication #1 @ 2023-09-15T14:07:03+02:00\"\n\njulia> NATS.ack(nc, msg)\nNATS.Pub(\"\\$JS.ACK.TEST_STREAM.TestConsumerConsume.1.27.189.1694542978673374959.1\", nothing, 0, nothing)","category":"page"},{"location":"connect/#Connect","page":"Connect","title":"Connect","text":"","category":"section"},{"location":"connect/","page":"Connect","title":"Connect","text":"connect","category":"page"},{"location":"connect/#NATS.connect","page":"Connect","title":"NATS.connect","text":"connect([host, port; kw...])\n\nInitialize and return Connection. See Connect protocol message.\n\n\n\n\n\n","category":"function"},{"location":"custom-data/#Custom-transport-types.","page":"Custom transport types.","title":"Custom transport types.","text":"","category":"section"},{"location":"custom-data/#Using-custom-types-as-handler-input.","page":"Custom transport types.","title":"Using custom types as handler input.","text":"","category":"section"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"It is possible to use and return custom types inside subscription handlers if convert method from Union{Msg, HMsg} is provided.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"struct Person\n    name::String\n    age::Int64\nend\n\nimport Base: convert\n\nfunction convert(::Type{Person}, msg::NATS.Message)\n    name, age = split(payload(msg), \",\")\n    Person(name, parse(Int64, age))\nend","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"sub = subscribe(\"EMPLOYEES\") do person::Person\n    @show person\nend","category":"page"},{"location":"custom-data/#Returning-custom-types-from-handler.","page":"Custom transport types.","title":"Returning custom types from handler.","text":"","category":"section"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"It is also possible to return any type from a handler in reply and put any type as publish argument if conversion to UTF-8 string is provided.   Note that both Julia and NATS protocol use UTF-8 encoding, so no additional conversions are needed.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"NATS module defines custom MIME types for payload and headers serialization:","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"const MIME_PAYLOAD  = MIME\"application/nats-payload\"\nconst MIME_HEADERS  = MIME\"application/nats-headers\"","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"Conversion method should look like this.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)\n    print(io, person.name)\n    print(io, \",\")\n    print(io, person.age)\nend","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"sub = reply(\"EMPLOYEES.SUPERVISOR\") do person::Person\n    if person.name == \"Alice\"\n        Person(\"Bob\", 44)\n    else\n        Person(\"Unknown\", 0)\n    end\nend\n","category":"page"},{"location":"custom-data/#Error-handling","page":"Custom transport types.","title":"Error handling","text":"","category":"section"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"Errors can be handled with custom headers.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"using NATS\n\nimport Base: convert, show\n\nstruct Person\n    name::String\n    age::Int64\n    departament::String\nend\n\nfunction convert(::Type{Person}, msg::Union{NATS.Msg, NATS.HMsg})\n    name, age, departament = split(payload(msg), \",\")\n    Person(name, parse(Int64, age), departament)\nend\n\nfunction show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)\n    print(io, person.name)\n    print(io, \",\")\n    print(io, person.age)\n    print(io, \",\")\n    print(io, person.departament)\nend\n\n\nnc = NATS.connect()\nsub = reply(\"EMPLOYEES.SUPERVISOR\") do person::Person\n    if person.name == \"Alice\"\n        Person(\"Bob\", 44), [\"status\" => \"ok\"]\n    else\n        Person(\"Unknown\", 0), [\"status\" => \"error\", \"message\" => \"Supervisor not defined for $(person.name)\" ]\n    end\nend\nsupervisor = request(Person, \"EMPLOYEES.SUPERVISOR\", Person(\"Alice\", 33, \"IT\"))\n@show supervisor\n\nhmsg = request(Person, \"EMPLOYEES.SUPERVISOR\", Person(\"Anna\", 33, \"ACCOUNTING\"))\n\nunsubscribe(sub)","category":"page"}]
}
