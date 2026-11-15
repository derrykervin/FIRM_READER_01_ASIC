"""Actual bridge queue ownership test and a real full-slot overwrite mutant."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
source=(root/'src/firm_host_proof_bridge.v').read_text()
needle='if(frame_valid && !reject_pending) begin'
assert source.count(needle)==1
rows=[]
for name,s in [('normal',source),('overwrite_full_slot',source.replace(needle,'if(frame_valid) begin'))]:
 w=out/name;w.mkdir(exist_ok=True);f=w/'bridge.v';f.write_text(s)
 cmd=['iverilog','-g2012','-s','tb_reject_metadata','-o',str(w/'sim'),str(f),str(root/'src/firm_frame_rx.v'),str(root/'experimental/host_proof/tb_reject_metadata.v')]
 r=subprocess.run(cmd,capture_output=True,text=True,timeout=60);assert r.returncode==0,r.stderr
 r=subprocess.run(['vvp',str(w/'sim')],capture_output=True,text=True,timeout=60)
 log=r.stdout+r.stderr;(w/'run.log').write_text(log)
 good=r.returncode==0 and 'PASS rejection metadata' in log and 'FATAL' not in log
 detected=r.returncode!=0 and 'full rejection metadata overwritten' in log
 accepted=good if name=='normal' else detected
 rows.append(dict(name=name,accepted=accepted,source_sha256=hashlib.sha256(s.encode()).hexdigest()))
 assert accepted,log
(out/'results.json').write_text(json.dumps(dict(status='PASS',rows=rows,scope=__doc__),indent=2)+'\n')
print('PASS rejection metadata and real overwrite mutant detected')
