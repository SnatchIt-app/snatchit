import hashlib, subprocess, sys, re
P='src/lib/profile/reputation.ts'
orig=open(P).read(); d0=hashlib.sha256(orig.encode()).hexdigest()
def run():
    r=subprocess.run(['npx','vitest','run','tests/reputation.test.ts'],capture_output=True,text=True)
    out=r.stdout+r.stderr
    m=re.search(r'Tests\s+(?:(\d+) failed \| )?(\d+) passed',out)
    failed=re.findall(r'> (R\d|[a-z].{0,40}?) ',out)
    return (m.group(1) or '0', m.group(2)), re.findall(r'reputation\.test\.ts > .*? > (R\d)',out)
base=run(); print('baseline', base)
muts={
 'A invented zero returns (branch kept)': (orig.replace('const rate = denom > 0 ? num / denom : null;','const rate = denom > 0 ? num / denom : 0;'),),
 'B null-rate branch deleted': (re.sub(r"  if \(rate == null\) \{\n(?:.*\n)*?  \}\n\n","",orig,count=1),),
}
for name,(mut,) in muts.items():
    assert mut!=orig, f'{name}: mutant identical — not applied'
    open(P,'w').write(mut)
    assert open(P).read()==mut
    print(name, run())
    open(P,'w').write(orig)
    assert hashlib.sha256(open(P).read().encode()).hexdigest()==d0, 'restore mismatch'
print('restored clean', run())
