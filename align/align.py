import whisper, json
m = whisper.load_model("medium")
r = m.transcribe("full.wav", language="hi", word_timestamps=True, fp16=False)
segs = [{"start": s["start"], "end": s["end"], "text": s["text"], "words": [(w["word"], round(w["start"], 2), round(w["end"], 2)) for w in s["words"]]} for s in r["segments"]]
json.dump(segs, open("out/words.json", "w"), ensure_ascii=False, indent=0)
for s in segs: print(round(s["start"], 2), round(s["end"], 2), s["text"])
