# How the voice check works

*Written 2026-10-06, for version 0.1.*

You read a short passage plus the names you say often, about a minute. Because Utter knows exactly what you said, it can measure how well each model heard you. The recording is thrown away as soon as it's checked.

## What it does

1. **Finds your best model.** Every downloaded model transcribes the same recording, and each gets a *word accuracy*: 1 − (wrong words + missing words + extra words) ÷ words read. That's the standard word error rate (WER), flipped so higher is better. Words are lined up with an edit-distance alignment, the same way speech research scores systems.
2. **Learns your names.** For each name, Utter looks at what the model heard in that spot. If it heard something else ("vox two" for "Vox2"), that fix goes into your dictionary. If it heard a very common word ("one" for "Juan"), it doesn't auto-add it, because that would rewrite every "one" you ever say. You can still add that one by hand.
3. **Tunes the match score.** Heard words are grouped by how sure the model was (under 50%, 50–70%, 70–85%, 85–95%, 95%+). For each group, Utter counts how often the model was actually right. Later dictations replace the model's raw number with that real rate, so "85" means about 85% of your words are right.
   - Small groups lean on the model's own number (as if we'd seen 5 extra words where the model was exactly as right as it claimed). That way one lucky or unlucky word doesn't swing the score.
   - The mapping only ever goes up: a more confident word never scores lower than a less confident one.
4. **Checks the mic.** It compares the loudest tenth of the recording (your voice) with the quietest tenth (the room). Too quiet or too noisy gets a plain-language tip.

## What it doesn't do

It doesn't change the models or "learn your voice." Retraining a model with hundreds of millions of parameters isn't practical on a phone, and modern models gain little from a minute of one voice. The voice check changes what Utter does *around* the model: which model you use, the names it fixes, and how honest the score is.

## Caveats

- **Reading isn't talking.** Read speech is cleaner than real rambling, so accuracy here runs a bit higher than everyday use.
- **One sample.** Re-run it if you change mics, rooms, or models. Settings shows when you last did, and the row lights up after 90 days.
- **About 150 words** is enough for rough score tuning, not precise tuning. Running it again replaces the old result.

## Further reading

- Guo et al., *On Calibration of Modern Neural Networks* (2017). Why AI confidence runs high, and binning methods like this one.
- Zadrozny & Elkan, *Transforming Classifier Scores into Accurate Multiclass Probability Estimates* (2002). The isotonic idea behind "only ever goes up."
- Wikipedia's "Word error rate" page.
