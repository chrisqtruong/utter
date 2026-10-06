# How Utter's match score works

*Written 2026-10-06, for version 0.1.*

## The short version

While a speech model turns your voice into text, it picks each word (or piece of a word) from a list of candidates and knows how likely its pick is. Utter keeps that number for every word. The **match score** is the average of those numbers across your words, shown from 0 to 100.

| Score | Label | What it usually means |
|---|---|---|
| 85–100 | high | almost certainly what you said |
| 65–84 | check | mostly right; give it a glance |
| under 65 | low | noisy room, mumbling or crosstalk; read it before sending |

Words the model gave less than a 50% chance get a **dotted underline**, so you know where to look.

These cutoffs are the same as Vox2's meaning check, so the colors mean the same thing in both apps.

## Where the numbers come from

**Parakeet** (via FluidAudio) decodes in word pieces ("Phil", "adel", "phia"). Each piece comes with the probability the model gave it. Utter joins the pieces into words and gives each word the probability of its **weakest piece**. A word is only as sure as its least sure part. That way one shaky syllable flags the whole word instead of being averaged away.

**Whisper** (via WhisperKit) reports a probability per word when word timings are on, which Utter always turns on. If timings are missing for a stretch, Utter falls back to that segment's average token probability, `exp(avgLogprob)`, for every word in it.

The score is the plain average of the word probabilities. Every word counts the same.

## Why it's useful

- It's free: the models compute these probabilities anyway, so the score costs no extra time or battery.
- It points at the right spots. In testing, the underlined words were where the transcript actually went wrong: names, mumbled phrases, overlapping voices. A clean clip from the Mac's `say` voice scored 98. A real conversation picked up from across a room scored 82, with the garbled acronyms underlined.

## Where it fails (honestly)

- **Confidently wrong.** A model can be sure and still be wrong, especially on names it has never heard ("Caitlin" written "Katelyn"). The score can't catch that. The dictionary can: add the fix once and it's applied every time.
- **Not calibrated, until you run a voice check.** Out of the box, "90" doesn't mean "9 out of 10 words are right"; raw probabilities tend to run high, so treat the score as a ranking. A [voice check](voice-check.md) measures how often each model is really right for your voice and tunes the score to match.
- **Not comparable across models.** Whisper and Parakeet measure certainty differently, so a Whisper 80 and a Parakeet 80 aren't the same thing.
- **Edits aren't rescored.** After you edit or tidy a note, the score still describes what the model heard. The app marks it "edited".

## How this compares to research practice

Speech researchers call this *confidence estimation*. Using the decoder's own probabilities, as Utter does, is the classic baseline. Research systems improve on it by training a small extra model to predict whether each word is correct (a "confidence estimation module"), which fixes the overconfidence. That would mean another download and more battery, so Utter sticks with the free signal and labels it as a guide.

Further reading:
- Li et al., *Confidence Estimation for Attention-based Sequence-to-sequence Models for Speech Recognition* (ICASSP 2021). Shows why raw model probabilities are overconfident and how a small add-on model helps.
- Laptev & Ginsburg, *Fast Entropy-Based Methods of Word-Level Confidence Estimation for End-to-End ASR* (2022). From NVIDIA, the team behind Parakeet. Compares cheap confidence measures like the one used here.

## Ideas for later

1. ~~Calibrate on a small set of your own clips, so "85" means roughly what it says.~~ Done: the voice check.
2. Weigh words by length, so a shaky "a" counts less than a shaky "Philadelphia".
3. Use the per-word timings to show *where in the recording* the shaky words were.
