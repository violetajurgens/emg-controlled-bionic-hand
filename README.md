

## Required components and downloads

* **2× ExG Pill by Upside Down Labs**. These are instrumentation amplifiers with custom RC filters and gain settings designed for measuring small electrical signals from the body, such as EMG, ECG, and EEG. In this project, one ExG Pill measures the flexor muscle signal and the other measures the extensor muscle signal.

* **2× Arduino/Raspberry Pi (etc.) boards**. One board is used for EMG signal acquisition and transmission to the computer. The second board receives movement commands from MATLAB and controls the servo motor of the bionic hand.

* **Chords Arduino Firmware**. When using the ExG Pills, the first step is to upload the Chords Arduino Firmware (https://github.com/upsidedownlabs/Chords-Arduino-Firmware) to the board responsible for EMG acquisition. The board then can send the measured EMG data to the computer in binary packets.

* **Chords LSL Connector**. Using the Chords LSL Connector (https://github.com/upsidedownlabs/Chords-LSL-Connector), the data from the binary packets is made available as a Lab Streaming Layer (LSL) stream, which MATLAB can read in real time or which can be recorded in XDF format for later analysis.

* **LabRecorder**. This application (https://github.com/labstreaminglayer/App-LabRecorder) is used to record the LSL stream and save it as an XDF file. In this project, the recorded XDF files are used by the classifier calibration program to select examples of rest, flexion, and extension and train the EMG classifier.

## Electrode placement

Correct electrode placement is very important for obtaining clear EMG signals. If the electrodes are placed over unsuitable muscle locations, the recorded signals may look similar to Graph A. In this example, the first three peaks correspond to making a fist, while the last three correspond to opening the hand. The two movements are difficult to distinguish because both Channel 1 and Channel 2 have a similar increase during both movements. This makes classification difficult because there is no clear difference in the activation pattern between the flexor and extensor channels. 

<img width="350" height="210" alt="bad example" src="https://github.com/user-attachments/assets/7376d5d7-b5c6-4446-90e7-46277d121c3a" /> <img width="350" height="210" alt="Screenshot 2026-08-28 021311" src="https://github.com/user-attachments/assets/09597519-d71a-40c9-bb74-d64a0b2e5f46" />

In Graph B, the movements are easier to distinguish from one another. The blue channel represents the flexor muscle group and the red channel represents the extensor muscle group. During flexion, flexor activity is much higher than extensor activity, as indicated by “F”. During extension, the activity of the two muscle groups is quite similar, as indicated by “E”, but both show a noticeable increase compared with the resting level near the bottom of the graph. With good electrode placement, the classification accuracy should typically be above 95%.

Experimenting with electrode placement can make a major difference. The electrode locations that I found to work best are shown below. Based on the reference locations in the figure, the two signal electrodes for the flexor channel can be placed around positions 6 and 7, while the electrodes for the extensor channel can be placed around positions 1 and 3. The figure below is adapted from Simar et al. (2024).

<img width="600" height="280" alt="image" src="https://github.com/user-attachments/assets/9fe8f807-8f0c-403c-9350-321dcc48703b" />

## Classifier design and calibration

EMG signals can vary significantly depending on electrode placement, skin contact, signal quality, and the strength of the muscle contraction. Because of this, fixed signal thresholds would not work reliably between different electrode placements or recording sessions. Therefore, the classifier is first calibrated and trained using the current EMG session before it is used for real-time hand control.

During calibration, the user selects representative periods of rest, flexion, and extension from the recorded EMG signal. These selected periods are then divided into equal-length analysis windows, with each window containing a specified number of samples. This means that the classifier does not make a decision based on a single sample; each prediction is based on the behaviour of both EMG channels over a short period of time. 

For every analysis window, the program extracts three features from each channel:

* Mean Absolute Value (MAV) — the average of the absolute EMG amplitudes inside the window. It therefore provides a simple measure of the overall amplitude of the signal. Taking the absolute value is important because EMG contains both positive and negative values, which would otherwise partially cancel each other out when averaged.
  
* Root Mean Square (RMS) — calculated by squaring each EMG sample, averaging the squared values, and then taking the square root. It is similar to MAV because it also shows the strength of muscle activity, but it is more sensitive to large peaks in the EMG signal.
  
* Waveform Length (WL) — calculated by adding together the absolute differences between consecutive EMG samples in the window. It describes how much the signal changes over time. This is useful because it adds information about the shape and variability of the EMG signal, rather than only its amplitude.

The classifier works with three possible states: REST, FLEXION, and EXTENSION. REST means that neither muscle group is intentionally contracting, FLEXION corresponds to closing the hand, and EXTENSION corresponds to opening it. In the final control system, these states are translated into the commands HOLD, CLOSE, and OPEN. 

Classification is then performed in two stages:

1. **Activity Gate** — decides whether the user is resting or actively contracting the muscles. The MAV values from both EMG channels are added together and compared with a threshold found during calibration. The activity threshold is determined automatically from the selected calibration data rather than being chosen manually. The program tests a range of possible threshold values and selects the one that gives the best balanced separation between REST windows and active FLEXION/EXTENSION windows. This allows the activity gate to adapt to the EMG amplitude of the current recording session.If the activity is below the threshold, the signal is classified as **REST**. If it is above the threshold, it is passed to the second stage. 

2. **Linear Discriminant Analysis (LDA)** — distinguishes between FLEXION and EXTENSION using the six extracted features: MAV, RMS, and WL from both channels. Before LDA training and prediction, each feature is standardized separately by subtracting its mean value from the training data and dividing by its standard deviation. This expresses the features relative to the typical variation seen during calibration and prevents features with larger numerical values from having greater influence simply because of their scale. LDA is computationally lightweight and can be trained using a relatively small calibration dataset, making it suitable for real-time hand control. A pseudo-linear LDA model is used, which uses a pseudoinverse when estimating the discriminant model. This makes it more robust if the feature covariance matrix has redundant features. Uniform class priors are also used so that FLEXION and EXTENSION are treated as equally important, regardless of small differences in the number of training windows from each class.

To evaluate the calibration, leave-one-repetition-out cross-validation is used. After classification, a 2-out-of-3 voting system reduces the effect of occasional incorrect predictions: at least two of the three most recent predictions must agree on FLEXION or EXTENSION before a CLOSE or OPEN command is produced; otherwise, the command remains HOLD. If the required calibration accuracies are reached, the classifier is trained again using all selected calibration data, and the final LDA model, activity threshold, feature-standardization values, and real-time processing parameters are saved for use by the hand-control program.

## Bionic hand mechanical design and operation

Each finger consists of several 3D-printed segments connected by bolts that act as joints. Actuation strings run through tunnels on the palm side of the fingers and are connected to a spool mounted on the servo motor. When the servo rotates, the strings wind around the spool and pull the fingers closed. Elastic cords on the opposite side provide a passive restoring force and pull the fingers back open when the strings are released. Although my design is not particularly polished, it contains all the features needed for the hand to function.

<img width="280" height="210" alt="1000054527" src="https://github.com/user-attachments/assets/7ced2d2f-78b6-4478-91eb-ea1fe7070eaf" /> <img width="190" height="210" alt="image" src="https://github.com/user-attachments/assets/ae506ec6-8615-4190-8544-e63e36b278f7" /> <img width="280" height="210" alt="unnamed (2)" src="https://github.com/user-attachments/assets/e201efde-47b5-4fdd-b94b-dbbe15ca6def" />

The over-bending stops on the back of the hand prevent the fingers from bending too far in the wrong direction, while the tunnels on both sides of the finger joints guide the actuation strings and elastic cords. In the images above, the leftmost image shows the palm side with the servo-driven spool, while the rightmost image shows the back side with the elastic cords. The complete design can be viewed in the SolidWorks assembly file inside Simple bionic hand model.zip. The hole in the palm section that holds the servo can be modified to fit the dimensions of a different servo. 

## Real-time hand control

Before running the program, make sure that the correct COM ports are selected. In this project, the Arduino Nano is used for collecting the EMG signal and the Arduino Uno is used for controlling the servo. These boards must use different COM ports. The COM-port numbers can change when the boards are disconnected or connected to a different USB port. If you are unsure which port belongs to which board, unplug one board and check which COM port disappears. It is especially important not to swap the two COM ports. If MATLAB attempts to connect to the Nano using the Arduino Support Package, it may upload its own server firmware to the board and overwrite the Chords firmware. In this case, the Chords firmware must be uploaded to the Nano again before EMG acquisition will work.

The program is written for an Arduino Nano Classic, which sends eight analog channels through the Chords firmware. If a different board or firmware configuration is used, numChannels and possibly the baud rate must also be changed. The servo signal wire is connected to pin D9. The opening and closing positions have to be determined experimentally for each hand mechanism. MATLAB controls the servo using values between 0 and 1, where the complete servo range corresponds approximately to 180 degrees. It is useful to determine the servo movement limits in a separate test program before running the full real-time control system. This makes it easier to find safe OPEN and CLOSE positions without involving the EMG classifier, and helps prevent the servo from pulling the hand mechanism too far.

The incoming EMG signal is processed in the same way as during calibration. If the window size, overlap, baseline removal, feature order, or electrode setup is changed significantly, it is better to repeat the calibration so that the classifier matches the new signal conditions. The activity gate first determines whether the signal represents REST or active muscle contraction. Then, active windows are standardised using the mean and standard deviation saved during calibration and are then classified as FLEXION or EXTENSION by the trained LDA model. The 2-out-of-3 voting system is then applied. FLEXION produces a CLOSE command, EXTENSION produces an OPEN command, and when neither movement receives enough votes the command is HOLD. 

If the hand starts behaving unpredictably, the EMG signal should be checked. Poor electrode contact, incorrect electrode placement, cable movement, or electrical interference can cause large peaks or make one channel much stronger than the other. The hand will not move immediately when a muscle contraction begins. The program first needs to collect enough EMG samples to fill an analysis window, calculate the features, classify the signal, and apply the 2-out-of-3 voting system before a movement command is produced. After this, there is an additional communication delay while the command is sent through the Arduino. If the hand responds much slower than expected, it is useful to check whether the classifier is producing stable FLEXION or EXTENSION predictions or whether it is repeatedly switching between movement and REST.

The EMG acquisition board can occasionally lose its serial connection or temporarily stop transmitting data. Because of this, the program contains a reconnection function. If the connection is lost, MATLAB clears the old serial connection, checks whether the EMG COM port becomes available again, creates a new connection, and sends the Chords START command to restart EMG acquisition. The previous EMG buffers and voting history are also cleared so that samples recorded before and after the interruption are not mixed together. If reconnection happens repeatedly, however, this usually indicates another problem.


**Reference**

Simar, C., Colot, M., Cebolla, A.-M., Petieau, M., Cheron, G., & Bontempi, G. (2024). Machine learning for hand pose classification from phasic and tonic EMG signals during bimanual activities in virtual reality. *Frontiers in Neuroscience, 18*, 1329411. https://doi.org/10.3389/fnins.2024.1329411
