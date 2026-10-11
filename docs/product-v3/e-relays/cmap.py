import struct,sys,glob
def cps(path):
    d=open(path,'rb').read()
    n=struct.unpack('>H',d[4:6])[0]
    for i in range(n):
        tag,cs,off,ln=struct.unpack('>4sIII',d[12+16*i:28+16*i])
        if tag==b'cmap': co=off
    nt=struct.unpack('>H',d[co+2:co+4])[0]; s=set()
    for i in range(nt):
        pid,eid,o=struct.unpack('>HHI',d[co+4+8*i:co+12+8*i]); t=co+o
        f=struct.unpack('>H',d[t:t+2])[0]
        if f==4:
            sc=struct.unpack('>H',d[t+6:t+8])[0]//2
            ends=struct.unpack('>%dH'%sc,d[t+14:t+14+2*sc]); st=struct.unpack('>%dH'%sc,d[t+16+2*sc:t+16+4*sc])
            for a,b in zip(st,ends): s.update(range(a,b+1))
        elif f==12:
            ng=struct.unpack('>I',d[t+12:t+16])[0]
            for g in range(ng):
                a,b,_=struct.unpack('>III',d[t+16+12*g:t+28+12*g]); s.update(range(a,b+1))
    return s
for p in sys.argv[1:]:
    s=cps(p); print(p.split('/')[-1], {hex(c):(c in s) for c in (0x270E,0x2713,0x2715,0x2039)})
