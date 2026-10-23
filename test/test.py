import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer, with_timeout

CPB=347
BIT_NS=CPB*25

async def receive(d):
    await with_timeout(FallingEdge(d.uart_tx), 2000, 'us')
    await Timer(BIT_NS//2, unit='ns')
    assert int(d.uart_tx.value)==0
    b=0
    for i in range(8):
        await Timer(BIT_NS, unit='ns')
        b |= int(d.uart_tx.value)<<i
    await Timer(BIT_NS, unit='ns')
    assert int(d.uart_tx.value)==1
    return b

async def send(d,b):
    await FallingEdge(d.clk)
    base=int(d.ui_in.value)&254
    d.ui_in.value=base
    await ClockCycles(d.clk,CPB)
    for i in range(8):
        d.ui_in.value=base|((b>>i)&1)
        await ClockCycles(d.clk,CPB)
    d.ui_in.value=base|1
    await ClockCycles(d.clk,CPB)

async def exchange(d, corrupt=False):
    assert await receive(d)==1
    # Start listening before sending the last reply byte to retain fast requests.
    nxt=cocotb.start_soon(receive(d))
    await send(d,1)
    assert await nxt==2
    ident=bytes.fromhex('F100000000000001')
    for b in ident[:-1]:await send(d,b)
    nxt=cocotb.start_soon(receive(d))
    await send(d,ident[-1])
    assert await nxt==0x10
    challenge=bytes([await receive(d) for _ in range(8)])
    assert challenge==bytes.fromhex('0123456789ABCDEF')
    response=bytearray.fromhex('FED480C19D70FFA5')
    if corrupt:response[0]^=1
    for b in response:await send(d,b)

@cocotb.test()
async def reader_protocol(d):
    cocotb.start_soon(Clock(d.clk,25,unit='ns').start())
    d.rst_n.value=0;d.ena.value=1;d.ui_in.value=1;d.uio_in.value=0
    await ClockCycles(d.clk,40)
    d.rst_n.value=1
    await ClockCycles(d.clk,20)
    assert int(d.uo_out.value)&6==0
    assert int(d.uio_oe.value)==255
    for corrupt in [False,True]:
        task=cocotb.start_soon(exchange(d,corrupt))
        d.ui_in.value=3
        await task
        await ClockCycles(d.clk,CPB*3)
        out=int(d.uo_out.value)
        assert bool(out&32)==(not corrupt)
        assert bool(out&64)==corrupt
        assert out&6==0 and out&16==0
        # Read every byte of the observable ID and response.
        expected=bytes.fromhex('F100000000000001')+bytes.fromhex('FFD480C19D70FFA5' if corrupt else 'FED480C19D70FFA5')
        for idx,b in enumerate(expected,2):
            d.ui_in.value=(idx<<2)|3
            await ClockCycles(d.clk,3)
            assert int(d.uio_out.value)==b
        d.ui_in.value=1
        await ClockCycles(d.clk,20)
        assert int(d.uo_out.value)==1
    # Missing card replies must fail with timeout, not pass.
    d.ui_in.value=3
    await ClockCycles(d.clk,CPB*450)
    assert int(d.uo_out.value)&64 and not int(d.uo_out.value)&32
    assert int(d.uio_out.value)&7==2
    d.ui_in.value=1
    await ClockCycles(d.clk,20)
    assert int(d.uo_out.value)==1
