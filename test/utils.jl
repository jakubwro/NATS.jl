using Test
using NATS


@testset "Instantiation of types from kwargs." begin

    # Happy path.
    @test NATS.from_kwargs(NATS.Unsub, NamedTuple(), (sid = "1234", max_msgs = 5,)) isa NATS.Unsub
    @test NATS.from_kwargs(NATS.Unsub, (sid = "1234", max_msgs = 5), NamedTuple()) isa NATS.Unsub
    @test NATS.from_kwargs(NATS.Unsub, (sid = "1234",), (max_msgs = 5,)) isa NATS.Unsub

    # Missing fields.
    @test_throws ErrorException NATS.from_kwargs(NATS.Unsub, (sid = "1234",), NamedTuple())
    @test_throws ErrorException NATS.from_kwargs(NATS.Unsub, NamedTuple(), (max_msgs = 5,))

    # Unexpected fields.
    @test_throws ErrorException NATS.from_kwargs(NATS.Unsub, (sid = "1234", max_msgs = 5), (stream = "stream1", ))

    # Wrong type of fields.
    @test_throws ErrorException NATS.from_kwargs(NATS.Unsub, (sid = "1234",), (max_msgs = "5",)) isa NATS.Unsub

end