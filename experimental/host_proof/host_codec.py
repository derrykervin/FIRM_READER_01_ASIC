"""Host PROVE profile1 codec. A qualified proof is NOT a login decision."""
from dataclasses import dataclass
from protocol import Frame,encode,decode

ERRORS=frozenset((2,4,5,6,8,9,11,12))
P256_ORDER=0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551

def canonical_device_signature(raw:bytes)->bytes:
    """Normalize raw device r||s before the strict server consumes its challenge.

    This is public signature formatting, never verification or authentication.
    The server's low-S/range checks remain mandatory and unchanged.
    """
    if type(raw)is not bytes or len(raw)!=64:
        raise ValueError('exact64-byte device signature required')
    r,s=int.from_bytes(raw[:32],'big'),int.from_bytes(raw[32:],'big')
    if not 0<r<P256_ORDER or not 0<s<P256_ORDER:
        raise ValueError('device signature scalar out of range')
    return r.to_bytes(32,'big')+min(s,P256_ORDER-s).to_bytes(32,'big')

@dataclass(frozen=True)
class ProofReply:
    sequence:int
    status:int
    card_status:int
    card_error:int
    proof:bytes

def prove_request(sequence:int,digest:bytes)->bytes:
    if not 1<=sequence<=65535 or len(digest)!=32:
        raise ValueError('nonzero sequence and exactly32 digest bytes required')
    return encode(Frame(sequence,0x10,bytes(digest)))

def prove_reply(packet:bytes,expected_sequence:int)->ProofReply:
    frame=decode(packet)
    if not 1<=expected_sequence<=65535 or frame.sequence!=expected_sequence or frame.command!=0x10 or frame.flags!=1:
        raise ValueError('wrong response context')
    if len(frame.payload)<4:
        raise ValueError('missing response status')
    status,card_status,card_error,count=frame.payload[:4]
    proof=frame.payload[4:]
    if status==0:
        if count!=64 or len(proof)!=64 or card_error!=0 or card_status&0x9f!=6:
            raise ValueError('unqualified or incomplete proof')
    elif status not in ERRORS or count!=0 or proof:
        raise ValueError('invalid failure response')
    return ProofReply(frame.sequence,status,card_status,card_error,proof)

@dataclass(frozen=True)
class IdentityReply:
    sequence:int
    status:int
    card_status:int
    card_error:int
    observation:bytes

def identity_request(sequence:int)->bytes:
    if not 1<=sequence<=65535:
        raise ValueError('nonzero sequence required')
    return encode(Frame(sequence,2))

def identity_reply(packet:bytes,expected_sequence:int)->IdentityReply:
    """Return raw public observation. Server registry matching is separate."""
    frame=decode(packet)
    if not 1<=expected_sequence<=65535 or frame.sequence!=expected_sequence or frame.command!=2 or frame.flags!=1:
        raise ValueError('wrong identity response context')
    if len(frame.payload)<4:
        raise ValueError('missing identity status')
    status,card_status,card_error,count=frame.payload[:4]
    observed=frame.payload[4:]
    if status==0:
        if count!=84 or len(observed)!=84 or card_error!=0 or card_status&0x9f!=6:
            raise ValueError('unqualified or incomplete identity observation')
    elif status not in ERRORS or count!=0 or observed:
        raise ValueError('invalid identity failure response')
    return IdentityReply(frame.sequence,status,card_status,card_error,observed)
