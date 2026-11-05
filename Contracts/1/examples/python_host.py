#!/usr/bin/env python3
"""Independent minimal host; standard library only, no SwiftTUI implementation imports."""
import argparse
import base64
import json
import math
import sys
import time
from urllib.parse import quote

MAX_ID = 18446744073709551615

def uint64(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 20 or any(c not in '0123456789' for c in value):
        return None
    number = int(value)
    return str(number) if number <= MAX_ID else None

def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise ValueError('duplicate key')
        result[key] = value
    return result

def finite(text):
    number = float(text)
    if not math.isfinite(number): raise ValueError('nonfinite number')
    return number

def bounded_json(data):
    if len(data) > 4194304: raise ValueError('record budget')
    text = data.decode('utf-8')
    depth = 0
    quoted = escaped = False
    for c in text:
        if quoted:
            if escaped: escaped = False
            elif c == '\\': escaped = True
            elif c == '"': quoted = False
        elif c == '"': quoted = True
        elif c in '[{':
            depth += 1
            if depth > 32: raise ValueError('nesting budget')
        elif c in ']}': depth -= 1
    return json.loads(text, object_pairs_hook=object_pairs, parse_float=finite,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite number')))

class Host:
    def __init__(self, mutation=None):
        self.mutation = mutation
        self.next_id = 0
        self.reset()

    def reset(self):
        self.buffer = bytearray()
        self.discarding = False
        self.epoch = self.generation = None
        self.width = self.height = 0
        self.rows = []
        self.styles = []
        self.images = {}
        self.targets = set()
        if self.mutation != 'reset' or not hasattr(self, 'pending'):
            self.pending = {}
        self.acknowledged = []
        self.repair = False

    def snapshot(self, effects):
        return {'epoch': self.epoch, 'generation': self.generation,
                'rows': self.rows, 'styles': self.styles,
                'images': sorted(self.images), 'acknowledged': self.acknowledged[:],
                'pending': sorted(self.pending), 'effects': effects}

    def consume(self, operation):
        effects = []
        self.pending = {key: request for key, request in self.pending.items() if request[1] > time.monotonic()}
        op = operation['op']
        if op == 'reset': self.reset()
        elif op == 'evictImage':
            identity = operation['id']
            self.images.pop(identity, None)
            if self.mutation != 'image': effects.append({'resync': {'scope': 'images', 'ids': [identity]}})
        elif op == 'action':
            target = operation['target']
            if target not in self.targets:
                effects.append({'error': 'staleTarget'})
            elif operation['action'] != 'activate':
                effects.append({'error': 'unsupported'})
            else:
                if self.next_id == MAX_ID: raise ValueError('request IDs exhausted')
                if len(self.pending) == 256: self.pending.pop(next(iter(self.pending)))
                self.next_id += 1
                identity = str(self.next_id)
                self.pending[identity] = (target, time.monotonic() + 30)
                effects.append({'input': '\x1eaccessibility:' + identity + ':' + quote(target, safe="-_.!~*'()") + ':activate\n'})
        elif op == 'feed':
            data = bytes.fromhex(operation['hex'])
            offset = 0
            while offset < len(data):
                newline = data.find(b'\n', offset)
                end = len(data) if newline < 0 else newline
                if not self.discarding:
                    if len(self.buffer) + end - offset > 4194304:
                        self.buffer.clear()
                        self.discarding = True
                        self.request_repair(effects)
                    else: self.buffer.extend(data[offset:end])
                if newline >= 0:
                    if not self.discarding and self.buffer.startswith(b'\x1esurface:'):
                        try: self.frame(bounded_json(bytes(self.buffer[9:])), effects)
                        except (ValueError, KeyError, TypeError, IndexError, OverflowError):
                            self.request_repair(effects)
                    self.buffer.clear()
                    self.discarding = False
                offset = end + 1
        else: raise ValueError('unknown operation: ' + op)
        return self.snapshot(effects)

    def request_repair(self, effects):
        if not self.repair:
            effects.append({'resync': {'scope': 'keyframe'}})
        self.repair = True

    def frame(self, frame, effects):
        width, height = frame['width'], frame['height']
        if type(width) is not int or type(height) is not int or not 0 <= width <= 1024 or not 0 <= height <= 1024 or width * height > 65536:
            raise ValueError('grid')
        version = frame['version']
        if type(version) is not int or version not in [1, 2, 3]: raise ValueError('version')
        epoch, generation = frame.get('epoch'), frame.get('gen')
        stamps = ['epoch','gen'] + (['baselineGen'] if version == 3 else [])
        if any(k in frame for k in stamps) and not all(type(frame.get(k)) is int and 0 <= frame[k] <= 9007199254740991 for k in stamps):
            raise ValueError('stamp')
        if version == 3:
            if frame.get('encoding') != 'delta': raise ValueError('encoding')
            if self.mutation != 'baseline' and (self.repair or epoch != self.epoch or frame.get('baselineGen') != self.generation or (width, height) != (self.width, self.height)):
                self.request_repair(effects)
                return
            rows = [list(row) for row in self.rows]
            base = frame.get('stylesBase')
            if base is not None and base != len(self.styles): raise ValueError('style base')
            styles = self.styles + frame['styles'] if base is not None else frame['styles']
            updates = frame['deltaRows']
            if any(not isinstance(row, list) or len(row) != 2 for row in updates): raise ValueError('delta tuple')
            if len({row[0] for row in updates}) != len(updates): raise ValueError('duplicate row')
        else:
            rows = [[] for _ in range(height)]
            styles = frame['styles']
            updates = list(enumerate(frame['rows']))
        if len(styles) > max(1024, width * height + 1): raise ValueError('styles')
        for y, cells in updates:
            if type(y) is not int or not 0 <= y < height: raise ValueError('row')
            end = 0
            for cell in cells:
                if self.mutation != 'arity' and len(cell) != 4: raise ValueError('cell arity')
                x, text, span, style = cell[:4]
                if any(type(v) is not int for v in [x, span, style]) or not isinstance(text, str) or x < end or span < 1 or x + span > width or not 0 <= style < len(styles) or len(text.encode('utf-8')) > 256:
                    raise ValueError('cell')
                end = x + span
            rows[y] = [cell[:4] for cell in cells]
        # Prepare independently, then commit all state together.
        images = {} if epoch != self.epoch else dict(self.images)
        if len(frame.get('images', [])) > 1024: raise ValueError('image budget')
        for image in frame.get('images', []):
            if 'dataBase64' in image:
                images[image['id']] = base64.b64decode(image['dataBase64'], validate=True)
        # Retain payloads across placement removal, but never grow without bound.
        while len(images) > 1024 or sum(map(len, images.values())) > 32 * 1024 * 1024:
            images.pop(next(iter(images)))
        targets = {node['actionTarget'] for node in frame.get('accessibilityTree', []) if node.get('actionTarget')}
        if epoch != self.epoch:
            if self.mutation != 'reset': self.pending.clear()
            self.acknowledged.clear()
        self.epoch, self.generation = epoch, generation
        self.width, self.height = width, height
        self.rows, self.styles, self.images, self.targets = rows, styles, images, targets
        self.repair = False
        self.pending = {key: request for key, request in self.pending.items() if request[0] in targets}
        reply = frame.get('accessibilityActionResponse')
        if isinstance(reply, dict):
            identity = uint64(reply.get('requestID'))
            if identity in self.pending and self.pending[identity][0] == reply.get('target') and reply.get('result') in ['accepted','staleTarget','disabled','outOfScope','unsupported','invalidValue']:
                self.pending.pop(identity)
                self.acknowledged.append(identity)
                self.acknowledged = self.acknowledged[-256:]
        self.pending = {key: target for key, target in self.pending.items() if target[0] in targets}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=['baseline','arity','image','reset'])
    args = parser.parse_args()
    host = Host(args.mutation)
    for line in sys.stdin:
        print(json.dumps(host.consume(json.loads(line)), separators=(',', ':')), flush=True)
