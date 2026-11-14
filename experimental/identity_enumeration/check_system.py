"""Host UART/v2 -> Reader -> CARD TT -> CPU/MMIO/13-command synthetic I2C.
Bench timing is accelerated. Cryptographic fixtures are not device validation.
"""
import argparse,hashlib,json,re,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--card',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--cvc',type=Path);p.add_argument('--cpb',type=int,default=16)
p.add_argument('--share-digest',type=int,choices=[0,1],default=1)
p.add_argument('--simulation-timeout',type=int,default=300,help='Host wall-clock seconds only; does not change any RTL cycle deadline')
a=p.parse_args();here=Path(__file__).resolve().parent;root=here.parents[1];card=a.card.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(card/'FIRM-SYSTEM-SPECS/tools'))
from protocol import Frame,encode
subprocess.run([sys.executable,'-B',str(card/'experimental/personalized_session/vectors.py'),str(out)],check=True,capture_output=True)
lock=json.loads((root/'experimental/host_proof/formal-source-lock.json').read_text())
for n,item in lock.items():
 assert hashlib.sha256((root/n).read_bytes()).hexdigest()==item['sha256']
 assert (root/n).read_bytes()==(root/item['source']).read_bytes()
readhex=lambda name:bytes(int(x,16)for x in(out/name).read_text().split())
base_digests=readhex('session_digests.hex');base_responses=readhex('session_responses.hex');base_commands=readhex('session_commands.hex');requests=[];expected=[]
from challenge_store import ChallengeStore,TrustedContext
from personalized_device import FactoryRecord,PersonalizedRegistry
from public_observation import PublicObservation
from auth_transcript import challenge_digest,encode_challenge
from atecc608_codec import digest_command,crc16
from cryptography.hazmat.primitives.asymmetric import ec,utils
from cryptography.hazmat.primitives import hashes
sys.path.insert(0,str(root/'experimental/host_proof'))
from host_codec import identity_reply,prove_reply,canonical_device_signature,P256_ORDER
from proof_signature import verify_proof
v=json.loads((out/'vectors.json').read_text());registry=PersonalizedRegistry();store=ChallengeStore(clock=lambda:100,ttl=60);contexts=[]
for i in range(2):
 context=TrustedContext(bytes([65+i])*16,76561198000000001+i,f'{i+1:010d}',730,1,bytes([75+i])*8,1);contexts.append(context)
 record=FactoryRecord.from_factory(uid=context.uid,key_id=context.key_id,config=bytes.fromhex(v['configuration'][i]),public_xy=bytes.fromhex(v['public_xy'][i]));registry.enroll(record,context,trusted_factory_authorized=True)
cases=[(0,0,1),(0,0,0),(1,0,1),(1,0,0),(0,31,1),(0,0,1),(1,20,0),(1,0,1),(0,27,1),(0,0,0)]
all_commands=[];all_responses=[];all_digests=[];challenges={};transcripts={}
for seq,(context,fault,identity) in enumerate(cases,1):
 cmd=2 if identity else 0x10;commands=bytearray(base_commands[context*1664:(context+1)*1664]);responses=bytearray(base_responses[context*1664:(context+1)*1664]);digest=base_digests[context*32:context*32+32]
 if not identity:
  challenge=registry.issue(store,contexts[context],trusted_ownership=True);challenges[seq]=challenge;digest=challenge_digest(challenge)
  nonce=digest_command(digest);commands[6*128:6*128+len(nonce)]=nonce
  key=ec.derive_private_key(context+1,ec.SECP256R1());rr,ss=utils.decode_dss_signature(key.sign(digest,ec.ECDSA(utils.Prehashed(hashes.SHA256()))));ss=max(ss,P256_ORDER-ss) if seq in (2,10) else min(ss,P256_ORDER-ss);signature=rr.to_bytes(32,'big')+ss.to_bytes(32,'big');body=bytes([67])+signature;response=body+crc16(body);responses[7*128:7*128+67]=response
  transcripts[seq]={'transcript_hex':encode_challenge(challenge).hex(),'digest_hex':digest.hex(),'scope':'Fresh reference-store challenge, known software fixture scalar signs synthetic I2C response; NOT actual device.'}
 requests.append(encode(Frame(seq,cmd,b'' if identity else digest)))
 data=(responses[1:21]+responses[513:577] if identity else responses[897:961]) if fault==0 else b''
 expected.append(encode(Frame(seq,cmd,bytes([0 if fault==0 else 8,0x26 if fault==0 else 0x2a,0 if fault==0 else 7,len(data)])+data,1)))
 all_commands.extend(commands);all_responses.extend(responses);all_digests.extend(digest)
for name,values in [('session_commands',all_commands),('session_responses',all_responses),('session_digests',all_digests)]:
 (out/(name+'.hex')).write_text('\n'.join(f'{b:02x}'for b in values)+'\n')
(out/'server-challenge-fixtures.json').write_text(json.dumps(transcripts,indent=2)+'\n')
for name,items in [('host_requests',requests),('host_expected',expected)]:
 (out/(name+'.hex')).write_text('\n'.join(f'{b:02x}'for q in items for b in q+bytes(128-len(q)))+'\n')
(out/'host_lengths.hex').write_text('\n'.join(f'{len(q):02x}'for q in expected)+'\n')
(out/'host_request_lengths.hex').write_text('\n'.join(f'{len(q):02x}'for q in requests)+'\n')
words=re.findall(r"8'h([0-9a-f]{2}): data=16'h([0-9a-f]{4});",(card/'src/firm_core/firm_serial_rom.v').read_text());assert len(words)==256
(out/'serial_secure_rom.hex').write_text('\n'.join(y for x,y in words)+'\n')
info=(card/'info.yaml').read_text();names=re.findall(r'    - "([^"]+)"',info.split('  source_files:\n',1)[1].split('pinout:',1)[0]);assert len(names)==23
reader_info=(root/'info.yaml').read_text();reader_names=re.findall(r'    - "([^"]+)"',reader_info.split('  source_files:\n',1)[1].split('pinout:',1)[0]);assert len(reader_names)==9
original=[card/'src'/n for n in names]+[root/'src'/n for n in reader_names]+[here/'tb_identity_system.v']
files=[]
for i,f in enumerate(original):
 code=f.read_text();name=('reader_project.v' if f==root/'src/project.v' else f.name)
 if f==root/'src/uart_rx.v' or f==root/'src/uart_tx.v':
  code=code.replace(f.stem,'reader_'+f.stem);name='reader_'+name
 elif f in [root/'src/firm_reader_host_uart.v',root/'src/firm_reader_proof_uart.v']:
  code=code.replace('uart_rx #','reader_uart_rx #').replace('uart_tx #','reader_uart_tx #')
 elif f==here/'tb_identity_system.v':code=code.replace('parameter CPB=16,DIV=2;',f'parameter CPB={a.cpb},DIV=2;').replace('defparam reader.core.CLKS_PER_BIT=CPB;',f'defparam reader.core.CLKS_PER_BIT=CPB;\n defparam reader.core.SHARE_DIGEST={a.share_digest};')
 target=out/name;target.write_text(code);files.append(target)
binary=out/'cvcsim'
if binary.exists():binary.unlink()
cmd=[str(a.cvc.resolve()),'+define+FIRM_CVC_NO_ASYNC_ATTR',*map(str,files)] if a.cvc else ['iverilog','-g2012','-s','tb_identity_system','-o','sim',*map(str,files)]
r=subprocess.run(cmd,cwd=out,capture_output=True,text=True,timeout=60);(out/'compile.log').write_text(r.stdout+r.stderr)
assert r.returncode==0 and(not a.cvc or binary.exists()),r.stdout+r.stderr
assert 0<a.simulation_timeout<=1500,'Bounded host execution budget required'
with (out/'simulation.log').open('w')as log:r=subprocess.run([str(binary)]if a.cvc else['vvp','sim'],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=a.simulation_timeout)
log=(out/'simulation.log').read_text();ok=r.returncode==0 and f'PASS identity TT system CPB={a.cpb} DIV=2 completed=20 ROM=256' in log and 'FATAL:'not in log and '$fatal['not in log
wire_results=[]
if ok:
 packets=[bytes.fromhex(line)for line in(out/'host_uart_frames.hex').read_text().splitlines()];assert len(packets)==20
 for seq,(context,fault,identity)in enumerate(cases,1):
  raw_packet,retry=packets[(seq-1)*2:seq*2];assert raw_packet==retry
  if identity:
   reply=identity_reply(raw_packet,seq)
   if fault==0:
    observation=PublicObservation.from_bytes(reply.observation)
    record=registry.resolve_observed(observation,trusted_account_id=contexts[context].account_id,trusted_steam_id=contexts[context].steam_id,trusted_ownership=True)
    assert record.key_id==contexts[context].key_id
   else:assert reply.status!=0 and not reply.observation
   wire_results.append({'sequence':seq,'kind':'identity','status':reply.status,'registry_lookup':fault==0,'login_granted':False})
  else:
   reply=prove_reply(raw_packet,seq);challenge=challenges[seq]
   canonical=canonical_device_signature(reply.proof) if reply.status==0 else bytes(64)
   high_s=reply.status==0 and int.from_bytes(reply.proof[32:],'big')>P256_ORDER//2
   if high_s:assert not verify_proof(ec.derive_private_key(context+1,ec.SECP256R1()).public_key(),challenge,reply.proof)
   accepted=registry.consume(store,challenge.challenge_id,canonical,context=contexts[context],trusted_ownership=True)
   assert accepted==(fault==0)
   replay=registry.consume(store,challenge.challenge_id,reply.proof,context=contexts[context],trusted_ownership=True);assert replay is False
   wire_results.append({'sequence':seq,'kind':'proof','status':reply.status,'reference_signature_accepted':accepted,'device_high_s':high_s,'normalized_before_strict_consume':canonical!=reply.proof if reply.status==0 else False,'cached_replay_accepted':replay})
 (out/'wire-server-results.json').write_text(json.dumps({'status':'PASS_REFERENCE_ONLY','scope':'Actual UART frames from native RTL through factory-fixture lookup / strict one-use reference verification. Challenges preissued for deterministic device-fixture preparation; no interactive production server. Software P256 device fixture; NOT real security-device, production factory or deployed server validation.','results':wire_results},indent=2)+'\n')
result=dict(status='PASS'if ok else'FAIL',scope=__doc__,cases=20 if ok else None,share_digest=a.share_digest,cpb=a.cpb,clock_hz=40000000,source_sha256={str(f):hashlib.sha256(f.read_bytes()).hexdigest()for f in original},staged_sha256={str(f):hashlib.sha256(f.read_bytes()).hexdigest()for f in files},compile_command=cmd)
(out/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
if not ok:raise SystemExit(log[-2500:])
