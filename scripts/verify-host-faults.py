"""Fault injection against isolated Windows host processes; never opens a UI."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import time

spec = importlib.util.spec_from_file_location('background', Path(__file__).with_name('verify-background.py'))
background = importlib.util.module_from_spec(spec)
spec.loader.exec_module(background)


def verify(bundle):
    server = background.Server(Path('test/fixtures/tls'))
    with tempfile.TemporaryDirectory(prefix='neutrino-host-faults-') as temp:
        profile = Path(temp)
        background.seed(profile, server, Path('test/fixtures/tls/server.pem'))
        host = subprocess.Popen([str(bundle.resolve() / 'neutrino_proxy_host.exe'), '--background', '--data-dir', str(profile)], creationflags=0x08000000)
        try:
            window = background.wait_for(lambda: background.windows(host.pid, 'NeutrinoDartHost'))[0]
            def worker():
                return next((pid for pid, (parent, name) in background.processes().items()
                             if parent == host.pid and name == 'neutrino_worker.exe'), None)
            background.wait_for(worker)
            time.sleep(.5)
            background.user.PostMessageW(window, 0x111, 102, 0)
            background.wait_for(lambda: server.auth == 1 and server.tcp_frames > 2 and server.udp_frames > 2)
            for attempt in range(3):
                original = worker()
                handle = background.kernel.OpenProcess(1, False, original)
                assert handle
                assert background.kernel.TerminateProcess(handle, 9)
                background.kernel.CloseHandle(handle)
                background.wait_for(lambda: worker() and worker() != original, 15)
                background.wait_for(lambda: server.auth == attempt + 2)
            original = worker()
            handle = background.kernel.OpenProcess(1, False, original)
            background.kernel.TerminateProcess(handle, 9)
            background.kernel.CloseHandle(handle)
            background.wait_for(lambda: worker() is None)
            time.sleep(11)
            assert worker() is None, 'Crash loop did not stop'
            background.user.PostMessageW(window, 0x111, 102, 0)
            restarted = background.wait_for(worker)
            background.wait_for(lambda: server.auth == 5)
            assert len(background.tree(host.pid)['processes']) == 2
            host.terminate()
            host.wait(4)
            background.wait_for(lambda: restarted not in background.processes(), 4)
            print('PASS: worker crash reconnect, bounded retries, manual retry, host crash cleanup; no Flutter process')
        finally:
            server.close()
            if host.poll() is None:
                host.terminate(); host.wait(4)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    verify(parser.parse_args().bundle)
