#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal parser for inMusic FIT-style (.img = DTB) update images.
usage: inmimg.py info IMG | extract IMG OUTDIR | dts IMG OUT.dts
  extract also verifies sha1 and decompresses xz
  dts writes the image as device tree source, each data property as /incbin/("<node>.img.xz")"""
import sys, struct, hashlib, lzma, os
def parse(path):
    b=open(path,'rb').read()
    magic,tot,off_s,off_str,off_rsv,ver,lcv,cpu,sz_str,sz_s=struct.unpack('>10I',b[:40])
    assert magic==0xd00dfeed
    strs=b[off_str:off_str+sz_str]
    def sname(o): return strs[o:strs.index(b'\0',o)].decode()
    p=off_s; path_=[]; nodes={}; cur=None
    while True:
        tok,=struct.unpack('>I',b[p:p+4]); p+=4
        if tok==1:
            e=b.index(b'\0',p); name=b[p:e].decode(); p=(e+4)&~3
            path_.append(name); cur='/'.join(path_) or '/'; nodes[cur]={}
        elif tok==3:
            ln,no=struct.unpack('>II',b[p:p+8]); p+=8
            nodes[cur][sname(no)]=(p,ln); p=(p+ln+3)&~3
        elif tok==2: path_.pop(); cur='/'.join(path_) or '/'
        elif tok==4: continue
        elif tok==9: break
    return b,nodes
def val(b,pl,raw=False):
    p,l=pl; d=b[p:p+l]
    if raw: return d
    if l and d[-1:]==b'\0' and all(32<=c<127 for c in d[:-1].replace(b'\0',b' ')): return d.rstrip(b'\0').decode().replace('\0',' | ')
    if l%4==0 and l<=40: return ' '.join('%08x'%x for x in struct.unpack('>%dI'%(l//4),d))
    return '<%d bytes>'%l
def dts(b,nodes):
    def prop(k,pl):
        p,l=pl; d=b[p:p+l]
        if k=='data': return '%s = /incbin/("%%s.img.xz");'%k
        if l and d[-1:]==b'\0' and all(32<=c<127 for c in d[:-1].replace(b'\0',b' ')): return '%s = %s;'%(k,', '.join('"%s"'%x for x in d[:-1].decode().split('\0')))
        assert l%4==0, k
        return '%s = <%s>;'%(k,' '.join('0x%x'%x for x in struct.unpack('>%dI'%(l//4),d)))
    def node(path,depth):
        t='\t'*depth; name=path.split('/')[-1] or '/'
        out=[t+name+' {']+[t+'\t'+(prop(k,v)%name if k=='data' else prop(k,v)) for k,v in nodes[path].items()]
        for c in nodes:
            if c!=path and c.rsplit('/',1)[0]==(path if path!='/' else ''): out+=['']+node(c,depth+1)
        return out+[t+'};']
    return '/dts-v1/;\n\n'+'\n'.join(node('/',0))+'\n'
if __name__=='__main__':
    cmd,img=sys.argv[1],sys.argv[2]; b,nodes=parse(img)
    if cmd=='dts': open(sys.argv[3],'w').write(dts(b,nodes)); sys.exit()
    for n,props in nodes.items():
        print('['+n+']')
        for k,v in props.items(): print('   %s = %s'%(k,val(b,v)))
    if cmd=='extract':
        out=sys.argv[3]; os.makedirs(out,exist_ok=True)
        for n,props in nodes.items():
            if 'data' in props:
                d=val(b,props['data'],True); name=n.split('/')[-1]
                h=nodes.get(n+'/hash',{})
                if h:
                    algo=val(b,h['algo']); want=val(b,h['value'],True)
                    got=hashlib.new(algo,d).digest()
                    print(name,algo,'hash OK (over compressed blob)' if got==want else 'hash MISMATCH')
                open(os.path.join(out,name+'.xz'),'wb').write(d)
                if val(b,props.get('compression',(0,0))) in ('xz',):
                    with lzma.open(os.path.join(out,name+'.xz')) as f, open(os.path.join(out,name+'.raw'),'wb') as o:
                        while (c:=f.read(1<<22)): o.write(c)
                    os.remove(os.path.join(out,name+'.xz'))
