%% =========================================================
%% BIONIC HAND EMG CALIBRATION
% Activity Gate + Binary LDA + 2-out-of-3 Voting
%
% This script trains and validates an EMG classifier for controlling
% the bionic hand using two EMG channels.
%
% Calibration procedure:
%   1. Select an XDF recording containing the calibration movements.
%   2. Select the required FLEXION contraction intervals.
%   3. Select the required EXTENSION contraction intervals.
%   4. Select the required REST intervals.
%
% The selected EMG data is divided into overlapping analysis windows
% and EMG features are extracted from each window.
%
% The classifier uses:
%   - An activity threshold to distinguish REST from muscle activity.
%   - Binary LDA to distinguish FLEXION from EXTENSION.
%   - 2-out-of-3 voting to make the final OPEN/CLOSE/HOLD command
%     more stable.
%
% Cross-validation is used to estimate classifier performance before
% the final model is trained.
%
% If the required calibration accuracies are reached, the trained
% classifier is saved as: bionic_hand_classifier.mat
%
% Only one temporary graph is displayed for selecting calibration
% intervals. The graph closes automatically after selection.

clear;
clc;
close all;
rng(1);

%% =========================================================
%% USER SETTINGS

nReps = 3;
% Size of the analysis window
windowSeconds = 0.10;     
overlap = 0.75;            

% 2-out-of-3 voting system
voteWindow = 3;           
requiredVotes = 2;        

% Calibration accuracy criteria
requiredRestAccuracy = 90;       
requiredFlexAccuracy = 75;       
requiredExtAccuracy  = 75;       
requiredBalancedAccuracy = 80;

%% =========================================================
%% CHECK IF REQUIRED MATLAB ADD-ONS ARE DOWNLOADED

if exist('load_xdf','file') ~= 2
    error(['MATLAB cannot find load_xdf. ' 'xdf-Matlab is required to download.']);
end

if exist('fitcdiscr','file') ~= 2
    error(['MATLAB cannot find fitcdiscr. ' 'Statistics and Machine Learning Toolbox is required to download.']);
end


%% =========================================================
%% LOAD XDF FILE

fprintf('\nSelect your XDF recording...\n');
[file,path] = uigetfile('*.xdf','Select calibration XDF');

if isequal(file,0)
    error('No XDF file selected.');
end

filename = fullfile(path,file);
streams = load_xdf(filename);
fprintf('XDF loaded.\n');

%% =========================================================
%% FIND A STREAM WITH AT LEAST TWO CHANNELS

streamIndex = [];

for s = 1:length(streams)
    channelCount = str2double(streams{s}.info.channel_count);
    nominalRate = str2double(streams{s}.info.nominal_srate);

    if channelCount >= 2 && nominalRate > 0
        streamIndex = s;
        break;
    end
end

if isempty(streamIndex)
    error('Could not find a suitable 2-channel LSL stream.')
end

stream = streams{streamIndex};
data = double(stream.time_series);
timestamps = double(stream.time_stamps);

if size(data,1) < 2
    error('The selected stream contains fewer than 2 channels.');
end

t = timestamps - timestamps(1);
fs = 1 / median(diff(timestamps));
fprintf('Sampling rate: %.2f Hz\n',fs);
fprintf('Recording length: %.2f seconds\n',t(end));

%% =========================================================
%% CHANNELS

ch1Raw = data(1,:);
ch2Raw = data(2,:);

%% =========================================================
%% REMOVE BASELINE DRIFT / DC OFFSET
% A trailing 1-second moving median estimates the slowly changing
% baseline of each channel. Only current and previous samples are used,
% making this preprocessing causal and reproducible in real-time control.

baselineSeconds = 1.0;
baselineN = round(baselineSeconds * fs);

ch1Baseline = movmedian(ch1Raw, [baselineN-1 0]);
ch2Baseline = movmedian(ch2Raw, [baselineN-1 0]);

% Subtract baseline from raw signal
ch1 = ch1Raw - ch1Baseline;
ch2 = ch2Raw - ch2Baseline;

%% =========================================================
%% FEATURE WINDOW SETTINGS

windowN = round(windowSeconds * fs);
stepN = round(windowN * (1-overlap));
stepN = max(stepN,1);

% Overlap controls how much of the previous analysis window is reused
% in the next prediction.
%
% Example with a 100 ms window and 75% overlap:
%
%   Window 1:   0-100 ms
%   Window 2:  25-125 ms
%   Window 3:  50-150 ms
%
% Therefore, each new prediction is made after only about 25 ms of new
% EMG data, while still using a full 100 ms window to calculate features.
%
% A higher overlap gives more frequent predictions and therefore a
% faster response, but neighbouring predictions become more similar
% because they share more of the same EMG samples.
%
% windowN is the number of samples used in each prediction window.
% stepN is the number of samples MATLAB moves forward before making
% the next prediction.
%
% At fs = 250 Hz:
%   windowN = 25 samples ≈ 100 ms
%   stepN   = 6 samples  ≈ 24 ms
%
% Example:
%   Window 1: samples 1-25
%   Window 2: samples 7-31
%   Window 3: samples 13-37
%
% windowN and stepN are both measured in samples, but they describe
% different things: window size and prediction update interval.

fprintf('\nFeature window: %.0f ms\n', windowSeconds*1000);
fprintf('Window samples: %d\n',windowN);
fprintf('Prediction step: %.1f ms\n\n', 1000*stepN/fs);

%% =========================================================
%% MINIMUM CALIBRATION INTERVAL
% We only need enough data for 2 predictions because
% 2 votes can already trigger the 2-out-of-3 system.
%
% The first prediction requires one complete window (windowN samples).
% Each additional prediction requires stepN new samples because the
% windows overlap.
%
% With:
%   windowN = 25 samples  (~100 ms)
%   stepN   = 6 samples   (~24 ms)
%
% Two predictions require:
%   25 + 6 = 31 samples
%   31 / 250 Hz = 0.124 s = 124 ms

minimumSamples = windowN + (requiredVotes-1)*stepN;
minimumSelectionDuration = minimumSamples / fs;

%% =========================================================
%% CREATE MAV FOR TEMPORARY SELECTION GRAPH

displayMAVN = round(0.10 * fs);
ch1Display = movmean(abs(ch1),displayMAVN);
% Moving average of the absolute Channel 1 EMG over 25 consecutive samples (~100 ms).

ch2Display = movmean(abs(ch2),displayMAVN);
% Moving average of the absolute Channel 2 EMG over 25 consecutive samples (~100 ms).

%% =========================================================
%% GENERATE CALIBRATION REGION SELECTION GRAPH

selectionFig = figure('Name','Select calibration intervals', 'NumberTitle','off');
plot(t,ch1Display,'LineWidth',1.2);
hold on;
plot(t,ch2Display,'LineWidth',1.2);
xlabel('Time (s)');
ylabel('MAV');
title('Select calibration intervals');
legend('Channel 1','Channel 2');
grid on;
xlim([0 t(end)]);

%% =========================================================
%% SELECT FLEXION

flexIntervals = zeros(nReps,2);
fprintf('SELECT 3 FLEXION CONTRACTIONS\n');

for r = 1:nReps
    flexIntervals(r,:) = selectInterval(selectionFig, minimumSelectionDuration);
    xline(flexIntervals(r,1), '--', 'HandleVisibility','off');
    xline(flexIntervals(r,2), '--', 'HandleVisibility','off');
end

%% =========================================================
%% SELECT EXTENSION

extIntervals = zeros(nReps,2);
fprintf('SELECT 3 EXTENSION CONTRACTIONS\n');

for r = 1:nReps
    extIntervals(r,:) = selectInterval( selectionFig, minimumSelectionDuration);
    xline(extIntervals(r,1), ':', 'HandleVisibility','off');
    xline( extIntervals(r,2), ':', 'HandleVisibility','off');
end

%% =========================================================
%% SELECT REST

restIntervals = zeros(nReps,2);
fprintf('SELECT 3 REST PERIODS\n\n');

for r = 1:nReps
    restIntervals(r,:) = selectInterval(selectionFig, minimumSelectionDuration);
    xline(restIntervals(r,1), '-.', 'HandleVisibility','off');
    xline(restIntervals(r,2),'-.', 'HandleVisibility','off');
end


%% =========================================================
%% FINISHED SELECTING

if ishandle(selectionFig)
    close(selectionFig);
end
fprintf('\nAll intervals selected successfully.\n\n');

%% =========================================================
%% CREATE DATASET
% X stores the six extracted features for every analysis window.
% labels stores the true class of each window.
%
% repFold identifies which repetition the window came from and is used
% for leave-one-repetition-out cross-validation.
%
% segmentID identifies the original selected interval so temporal voting
% is never allowed to continue across separate contractions/rest periods.

X = [];
labels = strings(0,1);
repFold = [];
segmentID = [];
segmentCounter = 0;

%% =========================================================
%% FLEXION DATA

for r = 1:nReps
    segmentCounter = segmentCounter + 1;
    mask = t >= flexIntervals(r,1) & t <= flexIntervals(r,2);
    % Selects only samples in time that belong to flexion training data.
    features = extractEMGfeatures(ch1(mask), ch2(mask), windowN, stepN);
    % This function is defined at the bottom of the script.

    if size(features,1) < requiredVotes
        error(['Flexion %d did not contain enough EMG for classification.'], r);
    end

    n = size(features,1);
    X = [X; features];
    labels = [labels; repmat("FLEXION",n,1)];
    repFold = [repFold; repmat(r,n,1)];
    segmentID = [segmentID; repmat(segmentCounter,n,1)];
end

%% =========================================================
%% EXTENSION DATA

for r = 1:nReps

    segmentCounter = segmentCounter + 1;
    mask = t >= extIntervals(r,1) & t <= extIntervals(r,2);
    features = extractEMGfeatures(ch1(mask), ch2(mask), windowN, stepN);

    if size(features,1) < requiredVotes
        error(['Extension %d did not contain enough EMG for classification.'], r);
    end

    n = size(features,1);
    X = [X; features];
    labels = [labels; repmat("EXTENSION",n,1)];
    repFold = [repFold; repmat(r,n,1)];
    segmentID = [segmentID; repmat(segmentCounter,n,1)];
end

%% =========================================================
%% REST DATA

for r = 1:nReps

    segmentCounter = segmentCounter + 1;
    mask = t >= restIntervals(r,1) & t <= restIntervals(r,2);
    features = extractEMGfeatures(ch1(mask), ch2(mask), windowN, stepN);

    if size(features,1) < requiredVotes
        error(['Rest %d did not contain enough EMG for classification.'],r);
    end

    n = size(features,1);
    X = [X; features];
    labels = [labels; repmat("REST",n,1)];
    repFold = [repFold; repmat(r,n,1)];
    segmentID = [segmentID; repmat(segmentCounter,n,1)];
end

%% =========================================================
%% FEATURE DEFINITIONS
% X(:,1) = MAV channel 1
% X(:,2) = MAV channel 2
% X(:,3) = RMS channel 1
% X(:,4) = RMS channel 2
% X(:,5) = Waveform length channel 1
% X(:,6) = Waveform length channel 2
%
% These are the six following features the LDA classifier will use to
% distinguish between extension and flexion.

%% =========================================================
%% ACTIVITY MEASURE
% Overall muscle activity is estimated as the sum of the MAV values
% from Channel 1 and Channel 2.

totalActivity = X(:,1) + X(:,2);

%% =========================================================
%% CROSS VALIDATION

fprintf('Running cross-validation...\n');
predicted = strings(size(labels));

for fold = 1:nReps
    trainIdx = repFold ~= fold;
    testIdx = repFold == fold;

    %% -----------------------------------------------------
    %% ACTIVITY GATE

    trainRest = trainIdx & labels=="REST";
    trainActive = trainIdx & (labels=="FLEXION" | labels=="EXTENSION");
    restActivity = totalActivity(trainRest);
    activeActivity = totalActivity(trainActive);
    activityThreshold = findBestActivityThreshold(restActivity, activeActivity);
    % This function is also defined at the bottom of the script.

    %% -----------------------------------------------------
    %% BINARY LDA TRAINING DATA

    ldaTrainIdx = trainIdx & (labels=="FLEXION" | labels=="EXTENSION");
    XtrainRaw = X(ldaTrainIdx,:);
    Ytrain = categorical(labels(ldaTrainIdx));

    %% -----------------------------------------------------
    % STANDARDIZE FROM TRAINING DATA

    trainMean = mean(XtrainRaw,1);
    trainSTD = std(XtrainRaw,[],1);
    trainSTD(trainSTD < eps) = 1;
    Xtrain = (XtrainRaw-trainMean) ./trainSTD;

    %% -----------------------------------------------------
    % Train binary LDA
    %
    % pseudoLinear LDA is used for improved numerical robustness if the
    % estimated feature covariance matrix is poorly conditioned.

    ldaFold = fitcdiscr(Xtrain, Ytrain, 'DiscrimType','pseudoLinear', 'Prior','uniform');

    %% -----------------------------------------------------
    %% TEST UNSEEN REPETITION

    testIndices = find(testIdx);

    for k = 1:length(testIndices)
        i = testIndices(k);

        %% REST / ACTIVE gate
        if totalActivity(i) < activityThreshold
            predicted(i) = "REST";
        else

            %% FLEXION vs EXTENSION
            xTest = (X(i,:)-trainMean) ./ trainSTD;
            result = predict(ldaFold, xTest);
            predicted(i) = string(result);
        end
    end
end

fprintf('Cross-validation complete.\n');

%% =========================================================
%% RAW CLASSIFIER ACCURACY THROUGH CROSS-VALIDATION

rawRestAccuracy = 100 * mean(predicted(labels=="REST") == "REST");
rawFlexAccuracy = 100 * mean(predicted(labels=="FLEXION") == "FLEXION");
rawExtAccuracy = 100 * mean(predicted(labels=="EXTENSION") == "EXTENSION");
rawBalancedAccuracy = mean([rawRestAccuracy, rawFlexAccuracy, rawExtAccuracy]);

%% =========================================================
%% 2-OUT-OF-3 TEMPORAL VOTING

fprintf('Applying 2-out-of-3 voting...\n\n');
command = repmat("HOLD",size(predicted));
uniqueSegments = unique(segmentID)';

for seg = uniqueSegments
    idx = find(segmentID==seg);

    for j = 1:length(idx)
        currentIndex = idx(j);

        %% Look at up to the last three predictions
        firstRecent = max(1,j-voteWindow+1);
        recentIndices = idx(firstRecent:j);
        recent = predicted(recentIndices);
        flexVotes = sum(recent=="FLEXION");
        extVotes = sum(recent=="EXTENSION");

        %% CLOSE
        if flexVotes >= requiredVotes
            command(currentIndex) = ...
                "CLOSE";

        %% OPEN
        elseif extVotes >= requiredVotes
            command(currentIndex) = "OPEN";

        %% HOLD
        else
            command(currentIndex) = "HOLD";
        end
    end
end

%% =========================================================
%% REMOVE INTENTIONAL INITIAL VOTING DELAY FROM EVALUATION
% First prediction cannot possibly have 2 votes.

eligible = true(size(labels));
for seg = uniqueSegments
    idx = find(segmentID==seg);

    if isempty(idx)
        continue;
    end

    thisClass = labels(idx(1));

    if thisClass=="FLEXION" || thisClass=="EXTENSION"
        nIgnore = min(requiredVotes-1, length(idx));
        eligible(idx(1:nIgnore)) = false;
    end
end

%% =========================================================
%% FINAL CONTROL ACCURACY

restMask = labels=="REST";
flexMask = labels=="FLEXION" & eligible;
extMask = labels=="EXTENSION" & eligible;
stableRestAccuracy = 100 * mean(command(restMask)=="HOLD");
stableFlexAccuracy = 100 * mean(command(flexMask)=="CLOSE");
stableExtAccuracy = 100 * mean(command(extMask)=="OPEN");
stableBalancedAccuracy = mean([stableRestAccuracy, stableFlexAccuracy, stableExtAccuracy]);

%% =========================================================
%% TRAIN FINAL CLASSIFIER ONLY IF CALIBRATION PASSES

calibrationSuccessful =(stableRestAccuracy >= requiredRestAccuracy) && (stableFlexAccuracy >= requiredFlexAccuracy)...
    && (stableExtAccuracy >= requiredExtAccuracy) && (stableBalancedAccuracy >= requiredBalancedAccuracy);
if calibrationSuccessful

    %% -----------------------------------------------------
    %% FINAL ACTIVITY THRESHOLD

    restActivity = totalActivity(labels=="REST");
    activeActivity = totalActivity(labels=="FLEXION" | labels=="EXTENSION");
    finalActivityThreshold = findBestActivityThreshold(restActivity, activeActivity);

    %% -----------------------------------------------------
    %% FINAL LDA

    activeIdx = labels=="FLEXION" | labels=="EXTENSION";
    XactiveRaw = X(activeIdx,:);
    Yactive = categorical(labels(activeIdx));
    featureMean = mean(XactiveRaw,1);
    featureSTD = std(XactiveRaw,[],1);
    featureSTD(featureSTD < eps) = 1;
    Xactive = (XactiveRaw-featureMean) ./ featureSTD;
    ldaModel = fitcdiscr(Xactive, Yactive,'DiscrimType','pseudoLinear','Prior','uniform');

    %% -----------------------------------------------------
    %% SAVE MODEL

    save('bionic_hand_classifier.mat', 'ldaModel', 'finalActivityThreshold', 'featureMean', ...
        'featureSTD','baselineN','windowN', 'stepN','windowSeconds','fs','voteWindow','requiredVotes');
end

%% =========================================================
%% PRINT FINAL RESULTS

fprintf('========================================\n');
fprintf('CALIBRATION ANALYSIS FINISHED\n');
fprintf('========================================\n');
fprintf('RAW CLASSIFIER\n');
fprintf('REST:      %.1f %%\n', rawRestAccuracy);
fprintf('FLEXION:   %.1f %%\n', rawFlexAccuracy);
fprintf('EXTENSION: %.1f %%\n', rawExtAccuracy);
fprintf('Balanced:  %.1f %%\n\n', rawBalancedAccuracy);

fprintf('========================================\n');
fprintf('WITH 2-OUT-OF-3 VOTING\n');
fprintf('========================================\n');
fprintf('REST / HOLD:        %.1f %%\n', stableRestAccuracy);
fprintf('FLEXION / CLOSE:    %.1f %%\n', stableFlexAccuracy);
fprintf('EXTENSION / OPEN:   %.1f %%\n', stableExtAccuracy);
fprintf('Balanced accuracy:  %.1f %%\n\n', stableBalancedAccuracy);

%% =========================================================
%% SUCCESS / FAILURE

if calibrationSuccessful
    fprintf('========================================\n');
    fprintf('CALIBRATION SUCCESSFUL\n');
    fprintf('========================================\n');
    fprintf('Classifier saved as:\n');
    fprintf('bionic_hand_classifier.mat\n');

else
    fprintf('========================================\n');
    fprintf('CALIBRATION SHOULD BE REPEATED\n');
    fprintf('========================================\n');
    fprintf('\nFailed requirement(s):\n');

    if stableRestAccuracy < requiredRestAccuracy
        fprintf('REST/HOLD: %.1f %% (need %.1f %%)\n', stableRestAccuracy, requiredRestAccuracy);
    end

    if stableFlexAccuracy < requiredFlexAccuracy
        fprintf('FLEXION/CLOSE: %.1f %% (need %.1f %%)\n', stableFlexAccuracy, requiredFlexAccuracy);
    end

    if stableExtAccuracy < requiredExtAccuracy
        fprintf('EXTENSION/OPEN: %.1f %% (need %.1f %%)\n', stableExtAccuracy, requiredExtAccuracy);
    end

    if stableBalancedAccuracy < requiredBalancedAccuracy
        fprintf('Balanced: %.1f %% (need %.1f %%)\n', stableBalancedAccuracy, requiredBalancedAccuracy);
    end
end

%% =========================================================
% LOCAL FUNCTION
% SELECT AN INTERVAL
%% =========================================================

function interval = selectInterval(selectionFig, minimumDuration)
    
    while true
        figure(selectionFig);
        [x,~] = ginput(2);
        interval = sort(x);
        duration = interval(2) - interval(1);

        if duration >= minimumDuration
            break;
        end

        fprintf(['That interval was only %.0f ms. Please select at least %.0f ms.\n'], duration*1000, minimumDuration*1000);
    end
end


%% =========================================================
% LOCAL FUNCTION
% EXTRACT EMG FEATURES
%% =========================================================

function features = extractEMGfeatures(sig1, sig2, windowN, stepN)
    sig1 = double(sig1(:));
    sig2 = double(sig2(:));
    N= min(length(sig1), length(sig2));

    if N < windowN
        features = zeros(0,6);
        return;
    end

    sig1 = sig1(1:N);
    sig2 = sig2(1:N);
    starts = 1:stepN:(N-windowN+1);
    features = zeros(length(starts),6);

    for k = 1:length(starts)
        idx = starts(k):(starts(k)+windowN-1);
        x1 = sig1(idx);
        x2 = sig2(idx);

        %% MAV

        MAV1 = mean(abs(x1));
        MAV2 = mean(abs(x2));

        %% RMS

        RMS1 = sqrt(mean(x1.^2));
        RMS2 = sqrt(mean(x2.^2));

        %% WAVEFORM LENGTH

        WL1 = sum(abs(diff(x1)));
        WL2 = sum(abs(diff(x2)));

        %% FEATURE VECTOR

        features(k,:) = [MAV1; MAV2; RMS1; RMS2; WL1; WL2]';
    end
end


%% =========================================================
% LOCAL FUNCTION
% FIND BEST REST-vs-ACTIVE THRESHOLD
%% =========================================================

function bestThreshold = findBestActivityThreshold(restActivity, activeActivity)
    restActivity = restActivity(:);
    activeActivity = activeActivity(:);
    allValues = [restActivity; activeActivity];
    candidates = linspace(min(allValues), max(allValues), 500);
    bestScore =-Inf;
    bestThreshold = median(allValues);

    for threshold = candidates
        restCorrect = mean(restActivity < threshold);
        activeCorrect = mean(activeActivity >= threshold);
        score = (restCorrect + activeCorrect)/2;
        
        if score > bestScore
            bestScore = score;
            bestThreshold = threshold;
        end
    end
end