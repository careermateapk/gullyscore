# Makes Hindi narration with Indic Parler-TTS (Apache-2.0); checks each take with Whisper and keeps the clearest.
import json, os, sys, difflib, unicodedata
import numpy as np, torch, soundfile as sf
from parler_tts import ParlerTTSForConditionalGeneration
from transformers import AutoTokenizer
import whisper

torch.set_num_threads(os.cpu_count())
MID = "ai4bharat/indic-parler-tts"
model = ParlerTTSForConditionalGeneration.from_pretrained(MID).eval()
tok = AutoTokenizer.from_pretrained(MID)
dtok = AutoTokenizer.from_pretrained(model.config.text_encoder._name_or_path)
SR = model.config.sampling_rate
DESC = os.environ.get("DESC", "Rohit speaks in a confident, energetic and expressive tone with a slightly fast pace, like a sports promo narrator. The recording is very clear and close-up with no background noise.")
asr = whisper.load_model("small")
lines = json.load(open("lines.json"))
os.makedirs("out", exist_ok=True)

def norm(s):
    s = unicodedata.normalize("NFC", s)
    return "".join(c for c in s if c.isalnum())

def score(wav, text):
    a = wav.astype(np.float32)
    import librosa
    a16 = librosa.resample(a, orig_sr=SR, target_sr=16000)
    r = asr.transcribe(a16, language="hi", fp16=False)["text"]
    return difflib.SequenceMatcher(None, norm(r), norm(text)).ratio(), r

d = dtok(DESC, return_tensors="pt")
report = []
for lid, sents in lines:
    parts = []
    for si, s in enumerate(sents):
        best = None
        for take in range(3):
            torch.manual_seed(1000 * take + si + 7)
            p = tok(s, return_tensors="pt")
            with torch.no_grad():
                g = model.generate(input_ids=d.input_ids, attention_mask=d.attention_mask,
                                   prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask,
                                   do_sample=True, temperature=1.0)
            w = g.cpu().numpy().squeeze()
            sc, heard = score(w, s)
            print(lid, si, take, round(sc, 3), heard, flush=True)
            if best is None or sc > best[0]:
                best = (sc, w, heard)
            if sc >= 0.9:
                break
        w = best[1]
        # trim silence at ends
        thr = 0.02 * np.abs(w).max()
        idx = np.where(np.abs(w) > thr)[0]
        if len(idx):
            w = w[max(0, idx[0] - int(0.03 * SR)): idx[-1] + int(0.08 * SR)]
        parts.append(w)
        parts.append(np.zeros(int(0.22 * SR), dtype=w.dtype))
        report.append({"line": lid, "sent": si, "score": round(best[0], 3), "text": s, "heard": best[2]})
    out = np.concatenate(parts[:-1])
    sf.write(f"out/{lid}.wav", out / max(1e-6, np.abs(out).max()) * 0.9, SR)
json.dump(report, open("out/report.json", "w"), ensure_ascii=False, indent=1)
