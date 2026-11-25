from pathlib import Path
import subprocess
p=Path(__file__).resolve().parent
with (p/'console.log').open('a') as f:
 proc=subprocess.Popen(['bash',str(p/'start-srb-160w.sh')],cwd=p,stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT,start_new_session=True,close_fds=True)
print('PID:',proc.pid)
