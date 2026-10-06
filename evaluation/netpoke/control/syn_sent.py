# Print the remote address of every TCP connection still being attempted (state SYN_SENT) from /proc/net/tcp on stdin.
import sys
out=[]
for l in sys.stdin.read().splitlines()[1:]:
    f=l.split()
    if len(f)>3 and f[3]=="02":
        h,p=f[2].split(":"); b=bytes.fromhex(h)[::-1]
        out.append("%d.%d.%d.%d:%d"%(*b,int(p,16)))
print(" ".join(out) or "none")
