%% =========================================================
%% BIONIC HAND REAL-TIME CONTROL
% Uses trained classifier from: bionic_hand_classifier.mat.
%
%% Change "servoPort" and "EmgPort" to match the COM ports
%% used by your boards.
%
% In this project, an Arduino Nano is used for EMG data collection, and an
% Arduino Uno R3 is used to control the servo. If different boards are used,
% update "numChannels" and the board name in "servoArduino" accordingly.

clear;
clc;

%% =========================================================
%% LOAD SAVED CLASSIFIER
% Load the trained classifier together with the preprocessing,
% analysis-window and voting parameters saved during calibration.

modelFile = 'bionic_hand_classifier.mat';

if ~isfile(modelFile)
    error(['Could not find ', modelFile, '. Run calibration successfully first.']);
end

load(modelFile);

%% =========================================================
%% EXG AMP PILL CONNECTION

%% CHANGE TO CORRECT PORT
EmgPort = "COM5";

% No need to specify any analog pin, the data is sent from all analog 
% channels anyways.

baudRate = 115200;
% This is supposed to be the same rate that the ExG Amp Pill uses for
% sending binary packets. It can be board-specific, so look inside the
% Chords Arduino firmware file. A wrong rate will corrupt the data.

s = serialport(EmgPort, baudRate);
configureTerminator(s, "LF");
flush(s);

%% =========================================================
%% CHORDS PACKET SETTINGS

% Number of analog channels sent by the Chords firmware.
% Arduino Nano Classic sends 8 channels.
numChannels = 8;

SYNC1 = hex2dec('C7');
SYNC2 = hex2dec('7C');
END_BYTE = hex2dec('01');

% 3 header bytes + 2 bytes/channel + 1 end byte
packetLength = 3 + 2*numChannels + 1;

%% =========================================================
%% SERVO CONNECTION

%% CHANGE TO CORRECT PORT
servoPort = "COM6";  

% Change "Uno" if you are using a different board.
servoArduino = arduino(servoPort, "Uno", "Libraries", "Servo");

% Servo signal wire connected to D9.
handServo = servo(servoArduino, "D9");

% MATLAB servo positions are given from 0 to 1:
%   0   = approximately 0 degrees
%   0.5 = approximately 90 degrees
%   1   = approximately 180 degrees

% The opening and closing values must be determined experimentally 
% for each hand mechanism. The servo also might reset to its default 
% start position when it receives power.
openPosition = 1;
closePosition = openPosition - 130/180;

%% =========================================================
%% BUFFERS

% This two-column array [Ch1, Ch2] keeps recent raw EMG data
% for causal baseline estimation.
rawHistory = zeros(0,2);

% This two-column array stores baseline-corrected EMG samples
% used for the current analysis window.
emgBuffer = zeros(0,2);

% Recent classifier predictions used for voting.
predictionHistory = strings(0,1);

% Number of new samples since previous prediction.
samplesSincePrediction = 0;

% Stores the previous servo command so the same command is not
% repeatedly sent on every classifier prediction.
previousCommand = "";

% Becomes true after the first prediction. From then on, a new
% prediction is made only after stepN new samples have arrived.
firstPredictionMade = false;

%% =========================================================
%% START EMG ACQUISITION

% Remove any old data from the serial buffer.
flush(s);

% Tell the Chords firmware to start sending EMG data.
writeline(s, "START");

fprintf('EMG acquisition started.\n\n');

%% =========================================================
%% REAL-TIME LOOP

while true

    %% =====================================================
    %% READ ONE CHORDS BINARY PACKET

    try

        packet = readChordsPacket(s, packetLength, SYNC1, SYNC2, END_BYTE);

    catch ME

        fprintf('\n');
        fprintf('========================================\n');
        fprintf('EMG connection lost.\n');
        fprintf('MATLAB message: %s\n', ME.message);
        fprintf('Attempting to reconnect to %s...\n', EmgPort);
        fprintf('========================================\n');

        % The old serialport object may no longer be valid.
        % Clear it before attempting to create a new connection.
        clear s

        pause(0.5);

        % Attempt to create a new serial connection and
        % restart Chords acquisition.
        s = reconnectEmg(EmgPort, baudRate);

        % There was a gap in the EMG signal, so do not combine
        % old samples with samples received after reconnection.
        rawHistory = zeros(0,2);
        emgBuffer = zeros(0,2);
        predictionHistory = strings(0,1);
        samplesSincePrediction = 0;
        firstPredictionMade = false;
        previousCommand = "";
        fprintf('EMG acquisition restarted.\n\n');
        continue;
    end

    %% =====================================================
    %% DECODE EMG CHANNELS
    %
    % Official Chords packet:
    %
    % Byte 1  = C7
    % Byte 2  = 7C
    % Byte 3  = packet counter
    % Byte 4  = A0 high byte
    % Byte 5  = A0 low byte
    % Byte 6  = A1 high byte
    % Byte 7  = A1 low byte
    % ...remaining Arduino channels...
    % Last byte = 01

    ch1Raw = double(packet(4)) * 256 + double(packet(5));
    ch2Raw = double(packet(6)) * 256 + double(packet(7));

    %% =====================================================
    %% CAUSAL BASELINE REMOVAL
    % Uses the same trailing-median baseline removal as during calibration.
    % Only current and previous samples are used, so it can operate in real time.

    rawHistory(end+1,:) = [ch1Raw ch2Raw];

    % Keep no more than baselineN samples.
    if size(rawHistory,1) > baselineN
        rawHistory(1,:) = [];
    end

    % Current running median.
    ch1Baseline = median(rawHistory(:,1));
    ch2Baseline = median(rawHistory(:,2));

    % Baseline-corrected sample.
    ch1 = ch1Raw - ch1Baseline;
    ch2 = ch2Raw - ch2Baseline;

    %% =====================================================
    %% ADD SAMPLE TO ANALYSIS WINDOW

    emgBuffer(end+1,:) = [ch1 ch2];

    % Keep only the latest windowN baseline-corrected samples.
    % This forms the sliding analysis window used for feature extraction.
    if size(emgBuffer,1) > windowN
        emgBuffer(1,:) = [];
    end

    samplesSincePrediction = samplesSincePrediction + 1;

    %% =====================================================
    %% WAIT FOR COMPLETE ANALYSIS WINDOW

    if size(emgBuffer,1) < windowN
        continue;
    end

    %% =====================================================
    %% OVERLAP

    if firstPredictionMade

        if samplesSincePrediction < stepN
            % Not enough new samples have arrived for the next prediction,
            % so MATLAB returns to the start of the loop and keeps
            % collecting data.
            continue;
        end

    end

    samplesSincePrediction = 0;
    firstPredictionMade = true;

    %% =====================================================
    %% FEATURE EXTRACTION

    x1 = emgBuffer(:,1);
    x2 = emgBuffer(:,2);

    % Mean Absolute Value (MAV)
    MAV1 = mean(abs(x1));
    MAV2 = mean(abs(x2));

    % Root Mean Square (RMS)
    RMS1 = sqrt(mean(x1.^2));
    RMS2 = sqrt(mean(x2.^2));

    % Waveform Length (WL)
    WL1 = sum(abs(diff(x1)));
    WL2 = sum(abs(diff(x2)));

    %% =====================================================
    %% FEATURE VECTOR

    features = [MAV1, MAV2, RMS1, RMS2, WL1, WL2];

    %% =====================================================
    %% ACTIVITY GATE

    totalActivity = MAV1 + MAV2;

    if totalActivity < finalActivityThreshold
        prediction = "REST";

    else

        %% =================================================
        %% STANDARDIZATION
        % Apply the same feature mean and standard deviation calculated
        % during calibration before giving the features to LDA.

        featuresStandardized = (features - featureMean) ./ featureSTD;

        %% =================================================
        %% LDA CLASSIFICATION

        result = predict(ldaModel, featuresStandardized);
        prediction = string(result);
    end

    %% =====================================================
    %% 2-OUT-OF-3 VOTING

    predictionHistory(end+1) = prediction;

    if length(predictionHistory) > voteWindow
        predictionHistory(1) = [];
    end

    flexVotes = sum(predictionHistory == "FLEXION");
    extVotes = sum(predictionHistory == "EXTENSION");

    %% =====================================================
    %% CONTROL DECISION

    if flexVotes >= requiredVotes
        command = "CLOSE";

    elseif extVotes >= requiredVotes
        command = "OPEN";

    else
        command = "HOLD";
    end

    %% =====================================================
    %% CONTROL SERVO

    if command ~= previousCommand

        if command == "CLOSE"
            % Move servo approximately 130 degrees
            % from the open position.
            writePosition(handServo, closePosition);

        elseif command == "OPEN"
            % Return servo to the open position.
            writePosition(handServo, openPosition);

        elseif command == "HOLD"
            % Do nothing.
            % Servo stays at its current commanded position.
        end
        previousCommand = command;
    end
end


%% =========================================================
%% READ CHORDS BINARY PACKET

function packet = readChordsPacket(s, packetLength, SYNC1, SYNC2, END_BYTE)

% Maximum amount of time MATLAB will wait for serial data before
% assuming that the EMG connection has failed.
maxWait = 2;

while true

    %% =====================================================
    %% WAIT FOR FIRST BYTE

    tStart = tic;
    while s.NumBytesAvailable < 1

        if toc(tStart) > maxWait
            error('No EMG serial data received for %.1f seconds.', maxWait);
        end
        pause(0.001);
    end

    byte1 = read(s, 1, "uint8");

    % A valid Chords packet must begin with SYNC1 (C7).
    % If this byte is not C7, discard it and continue searching
    % for the beginning of the next packet.
    if byte1 ~= SYNC1
        continue;
    end

    %% =====================================================
    %% WAIT FOR SECOND BYTE

    tStart = tic;
    while s.NumBytesAvailable < 1

        if toc(tStart) > maxWait
            error('EMG stream stopped while reading a packet.');
        end

        pause(0.001);
    end

    byte2 = read(s, 1, "uint8");

    if byte2 ~= SYNC2
        continue;
    end

    %% =====================================================
    %% WAIT FOR REMAINDER OF PACKET

    bytesRemaining = packetLength - 2;
    tStart = tic;

    while s.NumBytesAvailable < bytesRemaining

        if toc(tStart) > maxWait
            error('Incomplete Chords packet received.');
        end

        pause(0.001);
    end

    remainingBytes = read(s, bytesRemaining, "uint8");
    packet = [byte1, byte2, remainingBytes];

    %% =====================================================
    %% VALIDATE COMPLETE PACKET

    % Ignore packets that do not contain the expected
    % number of bytes.
    if numel(packet) ~= packetLength
        continue;
    end

    % Accept the packet only if its final byte is correct.
    if packet(end) == END_BYTE
        return;
    end
end
end

%% =========================================================
%% RECONNECT EMG BOARD
% An electric board may temporarily disconnect or reset when the serial
% connection is opened. If this happens during operation, this function
% attempts to reconnect to the board and restart EMG acquisition.

function s = reconnectEmg(EmgPort, baudRate)

% Maximum number of reconnection attempts before stopping
% the complete bionic-hand program.
maxAttempts = 10;

% Time between reconnection attempts.
retryDelay = 1;

for attempt = 1:maxAttempts
    fprintf('Reconnect attempt %d/%d...\n', attempt, maxAttempts);

    try
        %% =================================================
        %% CHECK WHETHER COM PORT EXISTS

        availablePorts = serialportlist("available");

        if ~any(availablePorts == EmgPort)
            fprintf('%s is not currently available.\n', EmgPort);
            pause(retryDelay);
            continue;
        end

        %% =================================================
        %% CREATE NEW SERIAL CONNECTION

        s = serialport(EmgPort, baudRate);
        configureTerminator(s, "LF");
        pause(2);
        flush(s);

        %% =================================================
        %% RESTART CHORDS STREAMING

        writeline(s, "START");

        % Allow some EMG packets to arrive.
        pause(0.5);

        %% =================================================
        %% CHECK WHETHER DATA RETURNED

        if s.NumBytesAvailable > 0
            fprintf('Reconnected successfully to %s.\n', EmgPort);
            return;
        end

        fprintf(['Connected to %s, but no EMG data was received.\n'], EmgPort);

        % Release the unsuccessful connection before
        % another attempt.
        clear s

    catch reconnectError
        fprintf('Reconnect failed: %s\n', reconnectError.message);

        % If an incomplete serial object was created,
        % release it before retrying.
        clear s

    end
    pause(retryDelay);
end

%% =========================================================
%% RECONNECTION FAILED

error(['Could not reconnect to the EMG board after ', num2str(maxAttempts), ' attempts.']);
end