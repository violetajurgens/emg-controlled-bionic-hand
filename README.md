This repository contains MATLAB code for EMG signal analysis and servo control of a bionic hand using two antagonistic forearm muscle signals: a flexor and an extensor. The processed EMG envelopes are compared against calibrated thresholds to detect flexor activation, extensor activation, rest, or co-contraction. Flexor activation commands the hand to close, extensor activation commands it to open, while rest or co-contraction maintains the current servo position, allowing the hand to hold its previous state without continuous muscle contraction.

Bionic hand:
Hand was 3d printed. It works so that when servo opens the hand, lets go of the tight string then the elastic will pulk it straigth from the back of the hand and the mechanical stoppers (second picture) on the bacck of the hand will stop from overextension. and the servo will pull tigether the hand if needed. 



Circuit and component details:
2x ExAmp Pill by Upsidedown labs (instrumentation amplifier with custom low and high passes and gain set to perfectly measure body electric signals)
2x any electric board
2x hdmi cable, one connected to one electric board that transmits emg signal to computer, other one connected to other board that transmits servo commands 
