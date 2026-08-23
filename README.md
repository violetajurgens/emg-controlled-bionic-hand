This repository contains MATLAB code for EMG signal analysis and servo control of a bionic hand using two antagonistic forearm muscle signals: a flexor and an extensor. The processed EMG envelopes are compared with calibrated activation thresholds to classify four muscle states: flexor activation, extensor activation, rest, and co-contraction. Flexor activation commands the hand to close, while extensor activation commands it to open. Rest is detected when both the flexor and extensor EMG envelopes remain below their respective activation thresholds, indicating that neither muscle is intentionally activated. Co-contraction is detected when both envelopes exceed their thresholds simultaneously, indicating concurrent activation of the antagonistic muscles. In both cases, MATLAB issues no new movement command to the servo, so the servo remains at its previously commanded position. The hand therefore stays in whatever position it had already reached until a new isolated flexor or extensor activation is detected.

## Actuation mechanism

The hand is 3D printed and uses a tendon-driven actuation mechanism with passive elastic return. Finger flexion is produced by a high-torque servo connected to artificial tendons running along the palm side of the fingers. When a closing command is received, the servo winds the tendons around a spool, shortening them and pulling the fingers into flexion. Finger extension is passive. Elastic cords run along the dorsal side of the fingers and are stretched when the hand closes. When an opening command is received, the servo unwinds the flexion tendons, increasing their available length. The elastic cords then pull the fingers back into the extended position. Mechanical stops incorporated into the dorsal side of the finger joints prevent the fingers from extending beyond their intended straight position. Both the flexion tendons and elastic return cords are routed through holes that are incorporated into the 3d model so that the elastic and the wire will run straight.

## Required circuit components

* **2× ExG Pill by Upside Down Labs**. Instrumentation amplifiers with custom RC filters and gain settings designed specifically for measuring small electrical signals from the body, such as EMG, ECG, and EEG.

* **2× Arduino/Raspberry Pi boards with 2x USB cable**. One board is used for EMG signal acquisition and transmission to the computer. The second board receives movement commands from MATLAB and controls the servo.

## Signal acquisition from ExG Pill

First Arduino chords Firmware is uploaded to one of the boards so that arduino knows how to send info so that LSL chords connector would understand (https://github.com/upsidedownlabs/Chords-Arduino-Firmware). MatLab will read the LSL sognal from LSL Chords connectro (Upside Down Labs software) directly.

## Control of the servo

Servo was controlled through MatLab using MATLAB Support for Arduino hardware package with Servo library enabled.
