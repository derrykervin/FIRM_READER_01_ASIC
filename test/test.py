"""Formal Reader TT host/legacy-CARD transport acceptance; no authentication."""
import binascii
import struct
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles,FallingEdge,Timer,with_timeout

CPB=347
BIT_NS=CPB*25

def packet(seq,payload,command=0x10):
    body=struct.pack('>BBHBH',2,0,seq,command,len(payload))+payload
    return b'\xa5\x5a'+body+struct.pack('>H',binascii.crc_hqx(body,0xffff))

async def receive(line):
    await with_timeout(FallingEdge(line),100,'ms')
    await Timer(BIT_NS//2,unit='ns')
    assert int(line.value)==0
    value=0
    for i in range(8):
        await Timer(BIT_NS,unit='ns')
        value|=int(line.value)<<i
    await Timer(BIT_NS,unit='ns')
    assert int(line.value)==1
    return value

async def send(d,bit,value):
    await FallingEdge(d.clk)
    for level in [0]+[(value>>i)&1 for i in range(8)]+[1]:
        d.ui_in.value=(int(d.ui_in.value)&~(1<<bit))|(level<<bit)
        await Timer(BIT_NS,unit='ns')

async def host_reply(d,seq,good,proof,identity=False):
    head=bytes([await receive(d.host_uart_tx) for _ in range(9)])
    assert head[:4]==b'\xa5\x5a\x02\x01'
    assert head[4:7]==struct.pack('>HB',seq,2 if identity else 0x10)
    size=int.from_bytes(head[7:9],'big')
    assert size==((88 if identity else 68) if good else 4)
    tail=bytes([await receive(d.host_uart_tx) for _ in range(size+2)])
    assert binascii.crc_hqx(head[2:]+tail[:-2],0xffff)==int.from_bytes(tail[-2:],'big')
    assert tail[:-2]==(bytes([0,0x26,0,84 if identity else 64])+proof if good else bytes([8,0x2a,7,0]))

async def card_fixture(d,digest,proof,good,identity=False):
    assert await receive(d.uart_tx)==(0xa0 if identity else 0xa1)
    if not identity:assert bytes([await receive(d.uart_tx) for _ in range(32)])==digest
    # The physical request stop bit must finish before the CARD responds.
    await Timer(BIT_NS*2,unit='ns')
    for value in proof:
        await send(d,0,0xd0)
        await send(d,0,value)
    for value in [0xf0,0x26 if good else 0x2a,0 if good else 7,84 if identity else 64]:
        await send(d,0,value)

@cocotb.test(timeout_time=400,timeout_unit='ms')
async def host_proof_transport(d):
    cocotb.start_soon(Clock(d.clk,25,unit='ns').start())
    d.rst_n.value=0;d.ena.value=1;d.ui_in.value=7;d.uio_in.value=0
    await ClockCycles(d.clk,40);d.rst_n.value=1
    await ClockCycles(d.clk,5000)
    for seq,good,identity in [(1,True,True),(2,True,False),(3,False,True),(4,False,False),(5,True,False)]:
        digest=bytes((seq+i)&255 for i in range(32))
        proof=bytes((seq^i)&255 for i in range(84 if identity else 64))
        device=cocotb.start_soon(card_fixture(d,digest,proof,good,identity))
        reply=cocotb.start_soon(host_reply(d,seq,good,proof,identity))
        for value in packet(seq,b'' if identity else digest,2 if identity else 0x10):await send(d,2,value)
        await device;await reply
        # A repeated request must use the cached frame without a new CARD reply.
        reply=cocotb.start_soon(host_reply(d,seq,good,proof,identity))
        for value in packet(seq,b'' if identity else digest,2 if identity else 0x10):await send(d,2,value)
        await reply
    d.ena.value=0
    await ClockCycles(d.clk,4)
    assert int(d.uo_out.value)==3 and int(d.uio_oe.value)==0
