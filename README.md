## Overview

This repository contains MATLAB code for EMG signal analysis and servo control of a bionic hand using two antagonistic forearm muscle signals: a **flexor** and an **extensor**. The processed EMG envelopes are compared with calibrated activation thresholds to classify four muscle states: flexor activation, extensor activation, rest, and co-contraction. Flexor activation commands the hand to close, while extensor activation commands it to open. During rest or co-contraction, no new movement command is issued and the servo maintains its current position. This allows the hand to remain open, closed, or partially closed without requiring continuous muscle contraction.

## Actuation mechanism of a 3D-printed bionic hand

The hand is 3D printed and uses a tendon-driven actuation mechanism with passive elastic return. Finger flexion is produced by a high-torque servo connected to artificial tendons running along the palm side of the fingers. When a closing command is received, the servo winds the tendons around a spool, shortening them and pulling the fingers into flexion. Finger extension is passive. Elastic cords run along the dorsal side of the fingers and are stretched when the hand closes. When an opening command is received, the servo unwinds the flexion tendons, increasing their available length. The elastic cords then pull the fingers back into the extended position. Mechanical stops incorporated into the dorsal side of the finger joints prevent the fingers from extending beyond their intended straight position. Both the flexion tendons and elastic return cords are routed through PTFE tubes attached to the finger segments and palm. The PTFE tubing provides a low-friction path and helps keep the tendons aligned during movement.

<img width="401" height="404" alt="Bionic hand tendon routing" src="https://github.com/user-attachments/assets/c9fe9c93-9d43-4a74-8c66-30434c78948c" />

## Required circuit components

* **2× ExG Pill by Upside Down Labs**. Biopotential amplifier modules designed for measuring low-amplitude physiological electrical signals such as EMG, ECG, and EEG. They provide amplification and signal conditioning before the EMG signal is acquired by the microcontroller.

* **2× Arduino/Raspberry Pi boards**. One board is used for EMG signal acquisition and transmission to the computer. The second board receives movement commands from MATLAB and controls the servo.
