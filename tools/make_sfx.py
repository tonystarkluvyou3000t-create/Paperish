"""Generate the original sound effects for Pip the Pizza Boy.

Small, deliberately simple synthesised cues: sine/triangle notes with short
envelopes plus a couple of noise hits. Written as 22.05 kHz mono 16-bit WAV so
Godot imports them directly. Run:  python tools/make_sfx.py
"""
from pathlib import Path
import array, math, random, wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'audio'
RATE = 22050
random.seed(5)


def write_wav(name, samples):
    data = array.array('h')
    for v in samples:
        data.append(max(-32000, min(32000, int(v * 32000))))
    path = OUT / f'{name}.wav'
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print(f'  {name}.wav  {len(samples) / RATE:.2f}s')


def tone(buf, start, dur, freq, amp=0.6, harm=0.0, decay=6.0, attack=0.005, vibrato=0.0):
    """Additive note with an exponential decay envelope."""
    n0 = int(start * RATE)
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        if t < attack:
            env = t / attack
        else:
            env = math.exp(-decay * (t - attack) / dur)
        w = 2 * math.pi * freq * t
        if vibrato:
            w += vibrato * math.sin(2 * math.pi * 5.5 * t)
        s = math.sin(w) + harm * math.sin(2 * w) * 0.5 + harm * 0.3 * math.sin(3 * w)
        j = n0 + i
        if j < len(buf):
            buf[j] += amp * env * s


def square(buf, start, dur, freq, amp=0.35, decay=4.0):
    n0 = int(start * RATE)
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * t / dur)
        w = 2 * math.pi * freq * t
        s = 1.0 if math.sin(w) > 0 else -1.0
        j = n0 + i
        if j < len(buf):
            buf[j] += amp * env * s


def noise(buf, start, dur, amp=0.5, decay=8.0, lp=0.35, pitch=1.0):
    n0 = int(start * RATE)
    n = int(dur * RATE)
    prev = 0.0
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * t / dur)
        v = random.uniform(-1, 1)
        prev = prev + lp * (v - prev)
        j = n0 + i
        if j < len(buf):
            buf[j] += amp * env * prev * pitch


def buf(dur):
    return [0.0] * int(dur * RATE)


def make_ui():
    b = buf(0.09)
    tone(b, 0, 0.07, 1250, amp=0.5, decay=9)
    write_wav('ui', b)


def make_order():
    b = buf(0.75)
    tone(b, 0.0, 0.5, 784, amp=0.5, harm=0.4, decay=4.5)
    tone(b, 0.17, 0.55, 1046, amp=0.45, harm=0.4, decay=4.0)
    write_wav('order', b)


def make_pickup():
    b = buf(0.6)
    for k, f in enumerate((523, 659, 880)):
        tone(b, k * 0.07, 0.35, f, amp=0.42, harm=0.3, decay=6)
    write_wav('pickup', b)


def make_deliver():
    b = buf(1.0)
    for k, f in enumerate((523, 659, 784, 1046)):
        tone(b, k * 0.1, 0.6, f, amp=0.4, harm=0.35, decay=4.5)
    tone(b, 0.42, 0.55, 1568, amp=0.22, harm=0.2, decay=6)
    write_wav('deliver', b)


def make_cash():
    b = buf(0.55)
    for k in range(4):
        noise(b, k * 0.055, 0.09, amp=0.3, decay=14, lp=0.7)
        tone(b, k * 0.055, 0.12, 1500 + k * 260, amp=0.32, harm=0.5, decay=12)
    tone(b, 0.22, 0.3, 660, amp=0.3, harm=0.4, decay=6)
    write_wav('cash', b)


def make_fail():
    b = buf(0.8)
    square(b, 0.0, 0.22, 300, amp=0.3, decay=3)
    square(b, 0.26, 0.42, 190, amp=0.32, decay=3)
    tone(b, 0.26, 0.5, 95, amp=0.3, harm=0.5, decay=3)
    write_wav('fail', b)


def make_step():
    b = buf(0.16)
    noise(b, 0, 0.1, amp=0.42, decay=11, lp=0.18)
    tone(b, 0, 0.1, 95, amp=0.35, harm=0.2, decay=10)
    write_wav('step', b)


def make_engine():
    """Seamless one-second loop: every partial completes whole cycles in 1.0 s."""
    dur = 1.0
    n = int(dur * RATE)
    b = [0.0] * n
    partials = [(60, 0.34), (90, 0.2), (120, 0.16), (179, 0.09), (240, 0.05)]
    for i in range(n):
        t = i / RATE
        s = 0.0
        for f, a in partials:
            s += a * math.sin(2 * math.pi * f * t)
        s += 0.05 * math.sin(2 * math.pi * 30 * t)
        b[i] = s * (0.85 + 0.15 * math.sin(2 * math.pi * 3 * t))
    peak = max(abs(x) for x in b)
    b = [x / peak * 0.55 for x in b]
    write_wav('engine', b)


def make_horn():
    b = buf(0.7)
    tone(b, 0, 0.55, 440, amp=0.32, harm=0.5, decay=2.2, attack=0.02)
    tone(b, 0, 0.55, 554, amp=0.28, harm=0.5, decay=2.2, attack=0.02)
    write_wav('horn', b)


def make_door():
    b = buf(0.45)
    noise(b, 0, 0.12, amp=0.4, decay=13, lp=0.5)
    tone(b, 0.05, 0.25, 150, amp=0.35, harm=0.4, decay=7)
    noise(b, 0.16, 0.1, amp=0.25, decay=16, lp=0.6)
    write_wav('door', b)


def make_shift_end():
    b = buf(1.6)
    for k, f in enumerate((523, 659, 784, 1046, 1318)):
        tone(b, k * 0.13, 0.9, f, amp=0.36, harm=0.3, decay=3.4)
    write_wav('shift_end', b)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    print('writing sound effects to assets/audio')
    make_ui(); make_order(); make_pickup(); make_deliver(); make_cash(); make_fail()
    make_step(); make_engine(); make_horn(); make_door(); make_shift_end()
    print('done')


if __name__ == '__main__':
    main()
