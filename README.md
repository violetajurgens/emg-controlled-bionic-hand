

## Required components and downloads

* **2× ExG Pill by Upside Down Labs**. These are instrumentation amplifiers with custom RC filters and gain settings designed for measuring small electrical signals from the body, such as EMG, ECG, and EEG. In this project, one ExG Pill measures the flexor muscle signal and the other measures the extensor muscle signal.

* **2× Arduino/Raspberry Pi (etc.) boards**. One board is used for EMG signal acquisition and transmission to the computer. The second board receives movement commands from MATLAB and controls the servo motor of the bionic hand.

* **Chords Arduino Firmware**. When using the ExG Pills, the first step is to upload the Chords Arduino Firmware (https://github.com/upsidedownlabs/Chords-Arduino-Firmware) to the board responsible for EMG acquisition. The board then can send the measured EMG data to the computer in binary packets.

* **Chords LSL Connector**. Using the Chords LSL Connector (https://github.com/upsidedownlabs/Chords-LSL-Connector), the data from the binary packets is made available as a Lab Streaming Layer (LSL) stream, which MATLAB can read in real time or which can be recorded in XDF format for later analysis.

* **LabRecorder**. This application (https://github.com/labstreaminglayer/App-LabRecorder) is used to record the LSL stream and save it as an XDF file. In this project, the recorded XDF files are used by the classifier calibration program to select examples of rest, flexion, and extension and train the EMG classifier.

## Electrode placement

Correct electrode placement is very important for obtaining clear EMG signals. If the electrodes are placed over unsuitable muscle locations, the recorded signals may look similar to Graph A. In this example, the first three peaks correspond to making a fist, while the last three correspond to opening the hand. The two movements are difficult to distinguish because both Channel 1 and Channel 2 increase during both movements. This makes classification difficult because there is no clear difference in the activation pattern between the flexor and extensor channels. 

<img width="350" height="210" alt="bad example" src="https://github.com/user-attachments/assets/7376d5d7-b5c6-4446-90e7-46277d121c3a" /> <img width="350" height="210" alt="Screenshot 2026-08-28 021311" src="https://github.com/user-attachments/assets/09597519-d71a-40c9-bb74-d64a0b2e5f46" />

A better signal is shown in Graph B. In this example, the blue channel represents the flexor muscle group and the red channel represents the extensor muscle group. During flexion, flexor activity is much higher than extensor activity, as indicated by “F”. During extension, the activity of the two muscle groups is more similar, as indicated by “E”, but both show a noticeable increase compared with the resting level near the bottom of the graph. With good electrode placement, the classification accuracy should typically be above 95%.

Experimenting with electrode placement can make a major difference. The electrode locations that I found to work best are shown below. Based on the reference locations in the figure, the two signal electrodes for the flexor channel can be placed around positions 6 and 7, while the electrodes for the extensor channel can be placed around positions 1 and 3. The figure below is adapted from Simar et al. (2024).

<img width="600" height="280" alt="image" src="https://github.com/user-attachments/assets/9fe8f807-8f0c-403c-9350-321dcc48703b" />

## Classifier model and its calibration and training

EMG signals can vary significantly depending on electrode placement, skin contact, signal quality, and the strength of the muscle contraction. Because of this, fixed signal thresholds would not work reliably between different electrode placements or recording sessions. Therefore, the classifier is first calibrated and trained using the current EMG session before it is used for real-time hand control.

During calibration, the user selects representative periods of rest, flexion, and extension from the recorded EMG signal. These selected periods are then divided into equal-length analysis windows, with each window containing a specified number of samples. This means that the classifier does not make a decision based on a single sample; each prediction is based on the behaviour of both EMG channels over a short period of time. 

For every analysis window, the program extracts three features from each channel:

* Mean Absolute Value (MAV) — the average of the absolute EMG amplitudes inside the window. It therefore provides a simple measure of the overall amplitude of the signal. Taking the absolute value is important because EMG contains both positive and negative values, which would otherwise partially cancel each other out when averaged.
  
* Root Mean Square (RMS) — calculated by squaring each EMG sample, averaging the squared values, and then taking the square root. It is similar to MAV because it also shows the strength of muscle activity, but it is more sensitive to large peaks in the EMG signal.
  
* Waveform Length (WL) — calculated by adding together the absolute differences between consecutive EMG samples in the window. It describes how much the signal changes over time. This is useful because it adds information about the shape and variability of the EMG signal, rather than only its amplitude.

The classifier works with three possible states: REST, FLEXION, and EXTENSION. REST means that neither muscle group is intentionally contracting, FLEXION corresponds to closing the hand, and EXTENSION corresponds to opening it. In the final control system, these states are translated into the commands HOLD, CLOSE, and OPEN. 

Classification is then performed in two stages:

1. **Activity Gate** — decides whether the user is resting or actively contracting the muscles. The MAV values from both EMG channels are added together and compared with a threshold found during calibration. If the activity is below the threshold, the signal is classified as **REST**. If it is above the threshold, it is passed to the second stage.

2. **Linear Discriminant Analysis (LDA)** — distinguishes between **FLEXION** and **EXTENSION** using the six extracted features: MAV, RMS, and WL from both channels. Before training, these features are standardized so that differences in numerical scale do not influence the classifier. Unlike more complex machine-learning methods, LDA does not require a very large training dataset, making it suitable for a short calibration procedure.

To evaluate the calibration, leave-one-repetition-out cross-validation is used. After classification, a 2-out-of-3 voting system reduces the effect of occasional incorrect predictions: at least two of the three most recent predictions must agree on FLEXION or EXTENSION before a CLOSE or OPEN command is produced; otherwise, the command remains HOLD. If the required accuracy is reached, the trained classifier and its calibration parameters are saved. 

## Bionic hand mechanical design and operation

Each finger consists of several 3D-printed segments connected by bolts that act as joints. Actuation strings run through tunnels on the palm side of the fingers and are connected to a spool mounted on the servo motor. When the servo rotates, the strings wind around the spool and pull the fingers closed. Elastic cords on the opposite side provide a passive restoring force and pull the fingers back open when the strings are released. Although my design is not particularly polished, it contains all the features needed for the hand to function.

The over-bending stops on the back of the hand prevent the fingers from bending too far in the wrong direction, while the tunnels on both sides of the finger joints guide the actuation strings and elastic cords. In the images below, the leftmost image shows the palm side with the servo-driven spool, while the rightmost image shows the back side with the elastic cords. The complete design can be viewed in the SolidWorks assembly file inside Simple bionic hand model.zip. The hole in the palm section that holds the servo can be modified to fit the dimensions of a different servo. 

<img width="280" height="210" alt="1000054527" src="https://github.com/user-attachments/assets/7ced2d2f-78b6-4478-91eb-ea1fe7070eaf" /> <img width="190" height="210" alt="image" src="https://github.com/user-attachments/assets/ae506ec6-8615-4190-8544-e63e36b278f7" /> <img width="280" height="210" alt="unnamed (2)" src="https://github.com/user-attachments/assets/e201efde-47b5-4fdd-b94b-dbbe15ca6def" />


## Control of the servo

Servo was controlled through MatLab using MATLAB Support for Arduino hardware package with Servo library enabled.

**References**
Simar, C., Colot, M., Cebolla, A.-M., Petieau, M., Cheron, G., and Bontempi, G. (2024). Machine learning for hand pose classification from phasic and tonic EMG signals during bimanual activities in virtual reality. Front. Neurosci. 18:1329411. doi: 10.3389/fnins.2024.1329411
