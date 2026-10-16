"""Exercise the compiled Dart worker over real pipes, using synthetic credentials."""
import argparse
import json
from pathlib import Path
import queue
import socket
import struct
import subprocess
import tempfile
import threading
import time


class Worker:
    def __init__(self, executable, profile):
        self.messages = queue.Queue()
        self.vault = {}
        self.events = []
        self.process = subprocess.Popen(
            [str(executable.resolve()), str(profile), str(Path('assets/test.jks').resolve())],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        threading.Thread(target=self.read, daemon=True).start()
        assert self.next()['kind'] == 'ready'

    def read(self):
        try:
            while True:
                header = self.process.stdout.read(4)
                if len(header) != 4:
                    return
                length = struct.unpack('>I', header)[0]
                assert 0 < length <= 8 * 1024 * 1024
                body = self.process.stdout.read(length)
                assert len(body) == length
                self.messages.put(json.loads(body))
        finally:
            self.messages.put(None)

    def next(self):
        message = self.messages.get(timeout=20)
        assert message is not None, 'Worker exited unexpectedly'
        return message

    def send(self, message):
        body = json.dumps(message).encode()
        self.process.stdin.write(struct.pack('>I', len(body)) + body)
        self.process.stdin.flush()

    def call(self, op, request_id, params=None, version=1, session='test'):
        self.send({'kind': 'request', 'version': version, 'source': 'host',
                   'session': session, 'id': request_id, 'op': op, 'params': params or {}})
        while True:
            message = self.next()
            if message['kind'] == 'vault':
                key = message['key']
                result = self.vault.get(key)
                if message['op'] == 'write':
                    self.vault[key] = message['value']
                elif message['op'] == 'delete':
                    self.vault.pop(key, None)
                self.send({'kind': 'vaultResult', 'id': message['id'], 'result': result})
            elif message['kind'] == 'response' and message['id'] == request_id:
                return message
            elif message['kind'] == 'state':
                self.events.append(message['data'])

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(4)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
                raise AssertionError('Parent EOF did not terminate worker')


def verify(executable):
    with tempfile.TemporaryDirectory(prefix='neutrino-worker-verification-') as temp:
        profile = Path(temp)
        worker = Worker(executable, profile)
        listener = socket.create_server(('127.0.0.1', 0))
        listener.settimeout(5)
        try:
            first = worker.call('attach', '1')['result']
            config = first['config'] | {'ssl': False, 'server': '127.0.0.1', 'port': listener.getsockname()[1]}
            params = {'config': config, 'license': 'synthetic-worker-secret',
                      'password': '', 'revision': first['configRevision']}
            saved = worker.call('save', '2', params)
            assert 'error' not in saved, saved
            assert len(worker.vault) == 1
            # Replayed ID returns the original result, without rotating credentials.
            assert worker.call('save', '2', params) == saved
            assert len(worker.vault) == 1
            assert 'error' in worker.call('save', '3', params), 'Stale revision accepted'
            assert 'error' in worker.call('snapshot', '4', version=999)
            worker.call('connect', '5')
            peer, _ = listener.accept()
            peer.settimeout(5)
            header = peer.recv(4)
            size = struct.unpack('>I', header)[0]
            body = b''
            while len(body) < size:
                body += peer.recv(size - len(body))
            assert body[0] == 2 and b'synthetic-worker-secret' in body
            text = b'{"code":0}'
            peer.sendall(struct.pack('>IBqI', 13 + len(text), 2, 0, len(text)) + text)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                current = worker.call('snapshot', str(time.monotonic()))['result']
                if current['engine']['state'] == 'connected':
                    break
            assert current['engine']['state'] == 'connected'
            started = current['engine']['connectedAt']
            worker.call('detach', '6')
            detached = worker.call('snapshot', '7')['result']
            assert detached['engine']['logs'] == []
            assert detached['engine']['connectedAt'] == started
            attached = worker.call('attach', '8', session='second')['result']
            assert attached['engine']['connectedAt'] == started
            assert 'synthetic-worker-secret' not in json.dumps([saved, attached, worker.events])
            assert 'synthetic-worker-secret' not in (profile / 'neutrino-flutter/config.json').read_text()
            worker.close()
            # Only short heartbeats may precede EOF; no persistent orphan socket.
            while peer.recv(4096):
                pass
            peer.close()
        finally:
            listener.close()
            worker.close()
        saturated = Worker(executable, profile)
        try:
            # Existing config needs a vault read. Leave it pending to model a
            # locked keychain, then ensure further requests have a hard bound.
            for index in range(70):
                saturated.send({'kind': 'request', 'version': 1, 'source': 'host',
                                'session': 'overload', 'id': str(index), 'op': 'snapshot'})
            while True:
                message = saturated.next()
                if message['kind'] == 'response':
                    assert 'error' in message
                    break
        finally:
            saturated.close()
        malformed = Worker(executable, profile / 'malformed')
        malformed.process.stdin.write(struct.pack('>I', 8 * 1024 * 1024 + 1))
        malformed.process.stdin.flush()
        malformed.process.wait(4)
        malformed.close()
    print('PASS: AOT worker, vault boundary, replay, revision, version, detach/reattach, parent EOF, malformed frame, bounded requests')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker', type=Path, required=True)
    verify(parser.parse_args().worker)
