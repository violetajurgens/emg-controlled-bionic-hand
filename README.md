This repository contains MATLAB code for EMG signal analysis and servo control of a bionic hand using two antagonistic forearm muscle signals: a flexor and an extensor. The processed EMG envelopes are compared with calibrated activation thresholds to classify four muscle states: flexor activation, extensor activation, rest, and co-contraction. Flexor activation commands the hand to close, while extensor activation commands it to open. Rest is detected when both the flexor and extensor EMG envelopes remain below their respective activation thresholds, indicating that neither muscle is intentionally activated. Co-contraction is detected when both envelopes exceed their thresholds simultaneously, indicating concurrent activation of the antagonistic muscles. In both cases, MATLAB issues no new movement command to the servo, so the servo remains at its previously commanded position. The hand therefore stays in whatever position it had already reached until a new isolated flexor or extensor activation is detected.

**Required circuit components**

* **2× ExG Pill by Upside Down Labs**. Instrumentation amplifiers with custom RC filters and gain settings designed specifically for measuring small electrical signals from the body, such as EMG, ECG, and EEG.

* **2× Arduino/Raspberry Pi boards**. One board is used for EMG signal acquisition and transmission to the computer. The second board receives movement commands from MATLAB and controls the servo.

## Actuation mechanism

The hand is 3D printed and uses a tendon-driven actuation mechanism with passive elastic return. Finger flexion is produced by a high-torque servo connected to artificial tendons running along the palm side of the fingers. When a closing command is received, the servo winds the tendons around a spool, shortening them and pulling the fingers into flexion. Finger extension is passive. Elastic cords run along the dorsal side of the fingers and are stretched when the hand closes. When an opening command is received, the servo unwinds the flexion tendons, increasing their available length. The elastic cords then pull the fingers back into the extended position. Mechanical stops incorporated into the dorsal side of the finger joints prevent the fingers from extending beyond their intended straight position. Both the flexion tendons and elastic return cords are routed through holes that are incorporated into the 3d model so that the elastic and the wire will run straight. The hole in the labakäsi part of the 3D model that holds the servo can be modified for your servo size, I used FT3625M.

**Signal acquisition from ExG Pill**
First Arduino chords Firmware is uploaded to one of the boards so that arduino knows how to send info so that LSL chords connector would understand (https://github.com/upsidedownlabs/Chords-Arduino-Firmware). MatLab will read the LSL sognal from LSL Chords connectro (Upside Down Labs software) directly. Additionally, if you want to analyze saved LSL streams (.xdf) then you need to download a repository for XDF fiule readinf in MATLAB.

**Classifier algorithm**
You need statistics and machine learning toolbox.
We are making a decision to close or open the hand by deciding whether the extensor or flexor has noticeably larger signal than another. But the raw signal we get from ExG pill about muscle activity, it is jumping around in negative and positive voltages around 0, see below on graph A so the two signals are incomparable if lets say one of them is -33mV and other is 3mV but the first has much larger amplitude. This is why we calculate the mean absolute value (MAV) over a short moving window:
<img width="123" height="44.25" alt="image" src="https://github.com/user-attachments/assets/d861b93b-d4f7-423e-aa39-5d4fd1238371" />
Below on graph B you can see the MAV values for.

We also set the flex treshold to detect activity of muscle as important and we set the difference threshold meaning that the computer will only use this info when its important. But since different people will have different muscle activity strength, or the electrodes can be attached weakly or other reason, each time we must do calibration. We measure maximal and minimal flexions for both muscles flexNorm = (flexMAV - flexRest) / (flexMax - flexRest);
extNorm  = (extMAV  - extRest)  / (extMax  - extRest). And then we later normalize everything to these valyues like this.

## Electrode placement
Correct electrode placement is very important for obtaining clear EMG signals. If the electrodes are placed over unsuitable muscle locations, the recorded signals may look similar to Graph A. In this example, the first three peaks correspond to making a fist, while the last three correspond to opening the hand. The two movements are difficult to distinguish because both Channel 1 and Channel 2 increase during both movements. This makes classification difficult because there is no clear difference in the activation pattern between the flexor and extensor channels. 

<img width="350" height="210" alt="bad example" src="https://github.com/user-attachments/assets/7376d5d7-b5c6-4446-90e7-46277d121c3a" /> <img width="350" height="210" alt="Screenshot 2026-08-28 021311" src="https://github.com/user-attachments/assets/09597519-d71a-40c9-bb74-d64a0b2e5f46" />

A better signal is shown in Graph B. In this example, the blue channel represents the flexor muscle group and the red channel represents the extensor muscle group. During flexion, flexor activity is much higher than extensor activity, as indicated by “F”. During extension, the activity of the two muscle groups is more similar, as indicated by “E”, but both show a noticeable increase compared with the resting level near the bottom of the graph. With good electrode placement, the classification accuracy should typically be above 95%.

Experimenting with electrode placement can make a major difference. The electrode locations that I found to work best are shown below. Based on the reference locations in the figure, the two signal electrodes for the flexor channel can be placed around positions 6 and 7, while the electrodes for the extensor channel can be placed around positions 1 and 3. The figure below is adapted from Simar et al. (2024).

<img width="600" height="280" alt="image" src="https://github.com/user-attachments/assets/9fe8f807-8f0c-403c-9350-321dcc48703b" />

## Bionic hand mechanical design and operation

The 3D-printed bionic hand uses a simple mechanism to open and close the fingers. Each finger consists of several 3D-printed segments connected by bolts that act as joints. Pulling strings run through tunnels on the palm side of the fingers and are connected to a spool mounted on the servo motor. When the servo rotates, the strings wind around the spool and pull the fingers closed. Elastic cords on the opposite side provide a passive restoring force and pull the fingers back open when the strings are released. Although my design is not particularly polished, it contains all the features needed for the hand to function.

The over-bending stops on the back of the hand prevent the fingers from bending too far in the wrong direction, while the tunnels on both sides of the finger joints guide the pulling strings and elastic cords. In the images below, the left image shows the palm side with the servo-driven spool, while the right image shows the back side with the elastic cords. The complete design can also be viewed in the SolidWorks assembly file inside Simple bionic hand model.zip. The hole in the palm section that holds the servo can be modified to fit the dimensions of a different servo. I used an FT3625M servo in my design.

<img width="280" height="210" alt="1000054527" src="https://github.com/user-attachments/assets/7ced2d2f-78b6-4478-91eb-ea1fe7070eaf" /> <img width="280" height="210" alt="unnamed (2)" src="https://github.com/user-attachments/assets/e201efde-47b5-4fdd-b94b-dbbe15ca6def" />


## Control of the servo

Servo was controlled through MatLab using MATLAB Support for Arduino hardware package with Servo library enabled.

**References**
Simar, C., Colot, M., Cebolla, A.-M., Petieau, M., Cheron, G., and Bontempi, G. (2024). Machine learning for hand pose classification from phasic and tonic EMG signals during bimanual activities in virtual reality. Front. Neurosci. 18:1329411. doi: 10.3389/fnins.2024.1329411
