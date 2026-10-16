"""Exercise the real Windows host/UI/worker using isolated synthetic TLS data.

No installed client settings are read or changed. Output contains only resource
measurements and test counters. Run after the Release bundle has been built.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
import socket
import ssl
import statistics
import struct
import subprocess
import tempfile
import threading
import time

kernel = c.WinDLL('kernel32', use_last_error=True)
user = c.WinDLL('user32', use_last_error=True)
psapi = c.WinDLL('psapi', use_last_error=True)
kernel.OpenProcess.restype = w.HANDLE
kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
kernel.CloseHandle.argtypes = [w.HANDLE]
kernel.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
psapi.QueryWorkingSet.argtypes = [w.HANDLE, c.c_void_p, w.DWORD]
user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
user.GetClassNameW.argtypes = [w.HWND, w.LPWSTR, c.c_int]
user.PostMessageW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
user.GetPropW.argtypes = [w.HWND, w.LPCWSTR]
user.GetPropW.restype = w.HANDLE
CALLBACK = c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
user.EnumWindows.argtypes = [CALLBACK, w.LPARAM]


def windows(pid, cls):
    found = []
    @CALLBACK
    def visit(hwnd, _):
        owner = w.DWORD()
        user.GetWindowThreadProcessId(hwnd, c.byref(owner))
        name = c.create_unicode_buffer(256)
        user.GetClassNameW(hwnd, name, len(name))
        if owner.value == pid and name.value == cls:
            found.append(hwnd)
        return True
    user.EnumWindows(visit, 0)
    return found


class Entry(c.Structure):
    _fields_ = [('size', w.DWORD), ('usage', w.DWORD), ('pid', w.DWORD),
                ('heap', c.c_size_t), ('module', w.DWORD), ('threads', w.DWORD),
                ('parent', w.DWORD), ('priority', c.c_long), ('flags', w.DWORD),
                ('name', w.WCHAR * 260)]


kernel.CreateToolhelp32Snapshot.restype = w.HANDLE
kernel.Process32FirstW.argtypes = [w.HANDLE, c.POINTER(Entry)]
kernel.Process32NextW.argtypes = [w.HANDLE, c.POINTER(Entry)]


def processes():
    snapshot = kernel.CreateToolhelp32Snapshot(2, 0)
    entry = Entry()
    entry.size = c.sizeof(entry)
    result = {}
    try:
        ok = kernel.Process32FirstW(snapshot, c.byref(entry))
        while ok:
            result[entry.pid] = (entry.parent, entry.name)
            ok = kernel.Process32NextW(snapshot, c.byref(entry))
    finally:
        kernel.CloseHandle(snapshot)
    return result


class Memory(c.Structure):
    _fields_ = [('cb', w.DWORD), ('faults', w.DWORD)] + [
        (name, c.c_size_t) for name in ('peak_ws', 'ws', 'peak_paged', 'paged',
                                      'peak_nonpaged', 'nonpaged', 'pagefile',
                                      'peak_pagefile', 'private')]


psapi.GetProcessMemoryInfo.argtypes = [w.HANDLE, c.POINTER(Memory), w.DWORD]
kernel.GetProcessHandleCount.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
kernel.GetProcessTimes.argtypes = [w.HANDLE] + [c.POINTER(w.FILETIME)] * 4


def memory(pid):
    handle = kernel.OpenProcess(0x410, False, pid)
    if not handle:
        return None
    try:
        counters = Memory()
        counters.cb = c.sizeof(counters)
        if not psapi.GetProcessMemoryInfo(handle, c.byref(counters), counters.cb):
            raise c.WinError(c.get_last_error())
        for capacity in (262144, 1048576, 4194304):
            buffer = (c.c_size_t * capacity)()
            if psapi.QueryWorkingSet(handle, buffer, c.sizeof(buffer)):
                private_pages = sum(not (buffer[i] & 0x100) for i in range(1, buffer[0] + 1))
                handles = w.DWORD()
                kernel.GetProcessHandleCount(handle, c.byref(handles))
                times = [w.FILETIME() for _ in range(4)]
                kernel.GetProcessTimes(handle, *(c.byref(value) for value in times))
                cpu = sum((value.dwHighDateTime << 32) | value.dwLowDateTime for value in times[2:]) / 10000000
                return {'pid': pid, 'private_ws_mib': round(private_pages * 4096 / 1048576, 3),
                        'total_ws_mib': round(counters.ws / 1048576, 3),
                        'private_commit_mib': round(counters.private / 1048576, 3),
                        'cpu_seconds': round(cpu, 3), 'handles': handles.value}
        raise c.WinError(c.get_last_error())
    finally:
        kernel.CloseHandle(handle)


def tree(root):
    all_processes = processes()
    ids = {root}
    for _ in range(6):
        ids.update(pid for pid, (parent, _) in all_processes.items() if parent in ids)
    values = []
    for pid in sorted(ids):
        if pid in all_processes:
            value = memory(pid)
            if value:
                values.append(value | {'name': all_processes[pid][1], 'parent': all_processes[pid][0]})
    return {'time': time.time(), 'processes': values,
            'private_ws_mib': round(sum(v['private_ws_mib'] for v in values), 3),
            'total_ws_mib': round(sum(v['total_ws_mib'] for v in values), 3),
            'private_commit_mib': round(sum(v['private_commit_mib'] for v in values), 3)}


def wait_for(check, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError('Timed out waiting for condition')


def frame(kind, info='', data=b''):
    text = info.encode()
    return struct.pack('>IBqI', 13 + len(text) + len(data), kind, 0, len(text)) + text + data


def read_exact(connection, count):
    result = b''
    while len(result) < count:
        part = connection.recv(count - len(result))
        if not part:
            raise EOFError()
        result += part
    return result


def read_frame(connection):
    length = struct.unpack('>I', read_exact(connection, 4))[0]
    if not 13 <= length <= 2097152:
        raise AssertionError('Invalid proxy frame')
    body = read_exact(connection, length)
    size = struct.unpack('>I', body[9:13])[0]
    return body[0], body[13:13 + size].decode(), body[13 + size:]


class Server:
    def __init__(self, fixtures, traffic=True, interval=.1):
        self.traffic = traffic
        self.interval = interval
        self.stop = threading.Event()
        self.auth = 0
        self.tcp_frames = 0
        self.udp_frames = 0
        self.failures = []
        self.peers = []
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.load_cert_chain(fixtures / 'server.pem', fixtures / 'server-key.pem')
        self.listener = socket.create_server(('127.0.0.1', 0))
        self.target = socket.create_server(('127.0.0.1', 0))
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind(('127.0.0.1', 0))
        self.port = self.listener.getsockname()[1]
        self.meta = {'visitorId': 'test-udp', 'visitorIp': '127.0.0.1', 'visitorPort': 12345,
                     'serverPort': 7001, 'targetIp': '127.0.0.1', 'targetPort': self.udp.getsockname()[1],
                     'proxyResponses': -1, 'proxyTimeoutMs': 60000}
        threading.Thread(target=self.accept, daemon=True).start()
        threading.Thread(target=self.echo, daemon=True).start()
        threading.Thread(target=self.echo_udp, daemon=True).start()

    def accept(self):
        while not self.stop.is_set():
            try:
                peer, _ = self.listener.accept()
                threading.Thread(target=self.session, args=(peer,), daemon=True).start()
            except OSError:
                break

    def echo(self):
        try:
            while not self.stop.is_set():
                peer, _ = self.target.accept()
                self.peers.append(peer)
                while not self.stop.is_set():
                    data = peer.recv(65536)
                    if not data:
                        break
                    peer.sendall(data)
        except OSError:
            pass

    def echo_udp(self):
        try:
            while not self.stop.is_set():
                data, address = self.udp.recvfrom(65536)
                self.udp.sendto(data, address)
        except OSError:
            pass

    def session(self, raw):
        try:
            peer = self.context.wrap_socket(raw, server_side=True)
            self.peers.append(peer)
            kind, info, data = read_frame(peer)
            if kind == 2:
                assert info == 'synthetic-background-license,test-background-client'
                self.auth += 1
                peer.sendall(frame(2, '{"code":0}'))
                if self.traffic:
                    peer.sendall(frame(3, 'test-tcp', f'127.0.0.1:{self.target.getsockname()[1]}'.encode()))
                    peer.sendall(frame(8, json.dumps(self.meta)))
                while not self.stop.is_set():
                    kind, _, _ = read_frame(peer)
                    if kind == 1:
                        peer.sendall(frame(1))
            else:
                assert kind in (3, 8)
                is_tcp = kind == 3
                if not is_tcp:
                    assert data == b'synthetic-background-license'
                sequence = 0
                while not self.stop.is_set():
                    payload = struct.pack('>I', sequence) + bytes(range(256)) * 4
                    peer.sendall(frame(5 if is_tcp else 16, 'test-tcp' if is_tcp else json.dumps(self.meta), payload))
                    response, _, result = read_frame(peer)
                    while response == 1:
                        response, _, result = read_frame(peer)
                    assert response == (5 if is_tcp else 16) and result == payload
                    if is_tcp:
                        self.tcp_frames += 1
                    else:
                        self.udp_frames += 1
                    sequence += 1
                    time.sleep(self.interval)
        except (EOFError, OSError):
            if not self.stop.is_set():
                self.failures.append('Connection unexpectedly closed')
        except Exception as error:
            self.failures.append(type(error).__name__)

    def close(self):
        self.stop.set()
        for peer in [*self.peers, self.listener, self.target, self.udp]:
            try:
                peer.close()
            except OSError:
                pass


def seed(profile, server, certificate):
    directory = profile / 'neutrino-flutter'
    directory.mkdir(parents=True)
    config = {'schemaVersion': 1, 'credentialId': 'synthetic-id', 'config': {
        'server': 'localhost', 'port': server.port, 'ssl': True,
        'clientId': 'test-background-client', 'certificatePath': str(certificate.resolve()),
        'heartbeatSeconds': 1, 'readIdleSeconds': 120}}
    (directory / 'config.json').write_text(json.dumps(config), encoding='utf-8')
    plain = json.dumps({'neutrino.flutter.synthetic-id': json.dumps({
        'license': 'synthetic-background-license', 'storePassword': ''})}).encode()
    class Blob(c.Structure):
        _fields_ = [('size', w.DWORD), ('data', c.POINTER(c.c_ubyte))]
    data = (c.c_ubyte * len(plain)).from_buffer_copy(plain)
    source, encrypted = Blob(len(plain), data), Blob()
    crypt = c.WinDLL('crypt32', use_last_error=True)
    if not crypt.CryptProtectData(c.byref(source), None, None, None, None, 1, c.byref(encrypted)):
        raise c.WinError(c.get_last_error())
    try:
        (profile / 'flutter_secure_storage.dat').write_bytes(c.string_at(encrypted.data, encrypted.size))
    finally:
        kernel.LocalFree.argtypes = [c.c_void_p]
        kernel.LocalFree(encrypted.data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, default=Path('build/windows/x64/runner/Release'))
    parser.add_argument('--cycles', type=int, default=50)
    parser.add_argument('--samples', type=int, default=60)
    parser.add_argument('--output', type=Path, default=Path('build/background-verification.json'))
    parser.add_argument('--measure-pid', type=int)
    parser.add_argument('--scenario', choices=('traffic', 'tls-idle', 'idle'), default='traffic')
    parser.add_argument('--interval', type=float, default=.1, help='Seconds between traffic frames')
    args = parser.parse_args()
    if args.measure_pid:
        result = []
        for _ in range(args.samples):
            result.append(tree(args.measure_pid))
            time.sleep(1)
        args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps({'samples': len(result), 'median_private_ws_mib': statistics.median(v['private_ws_mib'] for v in result)}))
        return
    server = Server(Path('test/fixtures/tls'), traffic=args.scenario == 'traffic', interval=args.interval)
    samples, foreground, restore_times = [], [], []
    with tempfile.TemporaryDirectory(prefix='neutrino-host-verification-') as temp:
        profile = Path(temp)
        seed(profile, server, Path('test/fixtures/tls/server.pem'))
        process = subprocess.Popen([str(args.bundle.resolve() / 'neutrino_proxy_host.exe'), '--background', '--data-dir', str(profile)], creationflags=0x08000000)
        try:
            hwnd = wait_for(lambda: windows(process.pid, 'NeutrinoDartHost'))[0]
            wait_for(lambda: any(parent == process.pid and name == 'neutrino_worker.exe' for parent, name in processes().values()))
            time.sleep(1)
            idle = [tree(process.pid) for _ in range(5)]
            if args.scenario != 'idle':
                user.PostMessageW(hwnd, 0x111, 102, 0)
                wait_for(lambda: server.auth == 1)
                if args.scenario == 'traffic':
                    wait_for(lambda: server.tcp_frames > 2 and server.udp_frames > 2)
            worker = next(pid for pid, (parent, name) in processes().items() if parent == process.pid and name == 'neutrino_worker.exe')
            for cycle in range(args.cycles):
                started = time.monotonic()
                user.PostMessageW(hwnd, 0x111, 101 if cycle % 2 else 100, 0)
                ui = wait_for(lambda: next((pid for pid, (parent, name) in processes().items() if parent == process.pid and name == 'neutrino_proxy_client_desktop.exe'), None))
                window = wait_for(lambda: windows(ui, 'FLUTTER_RUNNER_WIN32_WINDOW'))[0]
                wait_for(lambda: user.GetPropW(hwnd, 'Neutrino.UIReady') == ui, 25)
                time.sleep(.1)
                restore_times.append(time.monotonic() - started)
                if cycle == 0:
                    foreground.append(tree(process.pid))
                if cycle == args.cycles // 2:
                    handle = kernel.OpenProcess(1, False, ui)
                    kernel.TerminateProcess(handle, 9)
                    kernel.CloseHandle(handle)
                else:
                    user.PostMessageW(window, 0x10, 0, 0)
                wait_for(lambda: ui not in processes(), 4)
                assert worker in processes(), 'UI close terminated worker'
                assert server.auth == (0 if args.scenario == 'idle' else 1) and not server.failures, server.failures
                time.sleep(.1)
            for _ in range(args.samples):
                samples.append(tree(process.pid))
                assert len(samples[-1]['processes']) == 2, samples[-1]
                time.sleep(1)
            assert server.auth == (0 if args.scenario == 'idle' else 1) and not server.failures, server.failures
            tcp_frames, udp_frames = server.tcp_frames, server.udp_frames
            server.stop.set()
            user.PostMessageW(hwnd, 0x111, 104, 0)
            process.wait(7)
            wait_for(lambda: worker not in processes(), 3)
            result = {'scenario': args.scenario, 'interval_seconds': args.interval, 'cycles': args.cycles, 'authentication_count': server.auth,
                      'tcp_frames': tcp_frames, 'udp_frames': udp_frames,
                      'idle': idle, 'foreground': foreground, 'background_tls_traffic': samples,
                      'window_detect_plus_settle_seconds': restore_times,
                      'median_private_ws_mib': statistics.median(v['private_ws_mib'] for v in samples),
                      'p95_private_ws_mib': sorted(v['private_ws_mib'] for v in samples)[int((len(samples) - 1) * .95)],
                      'failures': server.failures}
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
            print(json.dumps({key: value for key, value in result.items() if not isinstance(value, list)}))
        finally:
            server.close()
            if process.poll() is None:
                process.terminate()
                process.wait(5)
            time.sleep(.3)


if __name__ == '__main__':
    main()
