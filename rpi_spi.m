% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi_32bit.m
% Create a Raspberry Pi object
rpi = raspi();

% Define data ready pin
dataReadyPin = 25;

% Configure data ready pin as digital input
configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI 32-bit Elements Transfer Mode');

% Create an SPI device object
spiDev = spidev(rpi, 'CE0', 0, 8000000); % 8 MHz SPI clock

% Buffer configuration - 4096 32-bit elements
ELEMENTS = 4096;                    % Total 32-bit elements in buffer
BYTES_PER_ELEMENT = 4;              % 4 bytes per 32-bit element
TOTAL_BYTES = ELEMENTS * BYTES_PER_ELEMENT;  % 16384 bytes total
CHUNK_SIZE = 256;                   % Maximum chunk size for MATLAB SPI

try
    % Set a timeout for the polling loop
    timeout = 300; % seconds (extended for larger buffers)
    startTime = tic;
    transactionCount = 0;
    
    % Use a local variable for status updates
    lastReport = 0;
    
    % Initial state check
    fprintf('Initial data ready pin state: %d\n', readDigitalPin(rpi, dataReadyPin));
    fprintf('Waiting for data ready signal (HIGH) from Teensy...\n');
    fprintf('Expected buffer: %d 32-bit elements (%d bytes total)\n', ELEMENTS, TOTAL_BYTES);
    
    % Main polling loop
    while toc(startTime) < timeout
        % Status update every 5 seconds
        if mod(floor(toc(startTime)), 5) == 0
            if floor(toc(startTime)) > lastReport
                fprintf('Waiting... Time elapsed: %.1f seconds\n', toc(startTime));
                fprintf('Data ready pin: %d\n', readDigitalPin(rpi, dataReadyPin));
                lastReport = floor(toc(startTime));
            end
        end
        
        % Check for data ready signal (HIGH)
        if readDigitalPin(rpi, dataReadyPin)
            % Double-check with delay for debounce
            pause(0.01);
            if readDigitalPin(rpi, dataReadyPin)
                transactionCount = transactionCount + 1;
                fprintf('\nTransaction #%d - Data ready HIGH detected\n', transactionCount);
                
                % Allocate buffer for raw bytes
                byteBuffer = uint8(zeros(1, TOTAL_BYTES));
                
                % Start timing the transfer
                txTime = tic;
                
                % Read in chunks of CHUNK_SIZE bytes
                numChunks = ceil(TOTAL_BYTES / CHUNK_SIZE);
                
                fprintf('Reading %d bytes in %d chunks of %d bytes each\n', ...
                    TOTAL_BYTES, numChunks, CHUNK_SIZE);
                
                % Initialize progress variables
                bytesReceived = 0;
                lastProgressReport = 0;
                
                for chunk = 1:numChunks
                    % Calculate start and end indices for this chunk
                    startIdx = (chunk-1) * CHUNK_SIZE + 1;
                    endIdx = min(chunk * CHUNK_SIZE, TOTAL_BYTES);
                    chunkLength = endIdx - startIdx + 1;
                    
                    % Create dummy data for this chunk
                    dummyChunk = uint8(zeros(1, chunkLength));
                    
                    % Read the chunk
                    chunkStart = tic;
                    receivedChunk = writeRead(spiDev, dummyChunk);
                    chunkTime = toc(chunkStart);
                    
                    % Store in byte buffer
                    byteBuffer(startIdx:endIdx) = receivedChunk;
                    
                    % Update progress
                    bytesReceived = bytesReceived + chunkLength;
                    progressPct = bytesReceived * 100 / TOTAL_BYTES;
                    
                    % Report progress at 10% intervals
                    currentProgress = floor(progressPct / 10);
                    if currentProgress > lastProgressReport
                        fprintf('Progress: %.1f%% (%d/%d bytes)\n', ...
                            progressPct, bytesReceived, TOTAL_BYTES);
                        lastProgressReport = currentProgress;
                    end
                    
                    % Report individual chunk details periodically
                    if mod(chunk, 16) == 0 || chunk == 1 || chunk == numChunks
                        fprintf('Chunk %d/%d: %d bytes in %.3f sec (%.2f bytes/sec)\n', ...
                            chunk, numChunks, chunkLength, chunkTime, chunkLength/chunkTime);
                    end
                    
                    % Short pause between chunks
                    pause(0.005);
                end
                
                % Calculate overall transfer rate for bytes
                elapsed = toc(txTime);
                transferRate = TOTAL_BYTES / elapsed;
                
                fprintf('\nTotal: Received %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                    TOTAL_BYTES, elapsed, transferRate);
                
                % Convert received bytes to 32-bit elements
                elementBuffer = zeros(1, ELEMENTS, 'uint32');
                
                % Start timing the conversion
                convStart = tic;
                
                % Convert bytes to 32-bit elements
                for i = 0:ELEMENTS-1
                    byteStartIdx = i * 4 + 1;
                    
                    % Combine 4 bytes into a 32-bit element
                    % Note: MATLAB uses 1-based indexing
                    b0 = uint32(byteBuffer(byteStartIdx));
                    b1 = uint32(byteBuffer(byteStartIdx + 1));
                    b2 = uint32(byteBuffer(byteStartIdx + 2));
                    b3 = uint32(byteBuffer(byteStartIdx + 3));
                    
                    % Combine using bitshift and bitwise OR
                    elementBuffer(i+1) = bitor(bitor(bitor(b0, bitshift(b1, 8)), ...
                        bitshift(b2, 16)), bitshift(b3, 24));
                end
                
                convTime = toc(convStart);
                fprintf('Converted %d bytes to %d 32-bit elements in %.3f seconds\n', ...
                    TOTAL_BYTES, ELEMENTS, convTime);
                
                % Display sample of 32-bit elements
                fprintf('First 8 32-bit elements: ');
                for i = 1:min(8, length(elementBuffer))
                    fprintf('%d ', elementBuffer(i));
                end
                fprintf('\n');
                
                % Verify if values match expected pattern (even or odd sequence)
                isEvenSequence = all(mod(elementBuffer(1:10), 2) == 0);
                isOddSequence = all(mod(elementBuffer(1:10), 2) == 1);
                
                if isEvenSequence
                    disp('Detected EVEN number sequence (Buffer A)');
                elseif isOddSequence
                    disp('Detected ODD number sequence (Buffer B)');
                else
                    disp('WARNING: Received data does not match expected pattern');
                    fprintf('First 20 values mod 2: ');
                    for i = 1:20
                        fprintf('%d ', mod(elementBuffer(i), 2));
                    end
                    fprintf('\n');
                end
                
                % Wait for data ready signal to go LOW
                fprintf('All data received. Waiting for Teensy to signal completion (data ready LOW)...\n');
                waitTime = tic;
                lowDetected = false;
                
                % Wait up to 10 seconds with frequent checking
                while toc(waitTime) < 10
                    if ~readDigitalPin(rpi, dataReadyPin)
                        % Confirm LOW state
                        pause(0.02);
                        if ~readDigitalPin(rpi, dataReadyPin)
                            lowDetected = true;
                            break;
                        end
                    end
                    pause(0.01);
                end
                
                if lowDetected
                    fprintf('Data ready signal went LOW after %.3f seconds\n', toc(waitTime));
                    disp('Teensy has completed buffer transmission');
                    disp('Ready for next transaction');
                    pause(0.1);
                else
                    disp('WARNING: Timeout waiting for data ready LOW signal');
                    disp('The Teensy should have set the data ready pin LOW');
                    disp('Continuing to next transaction...');
                    pause(0.5);
                end
                
                % Optional: Save the received data to a MAT file
                if transactionCount <= 10  % Limit to first 10 transactions to avoid filling disk
                    filename = sprintf('spi_data_transaction_%d.mat', transactionCount);
                    save(filename, 'elementBuffer', 'isEvenSequence', 'isOddSequence', 'elapsed');
                    fprintf('Saved data to %s\n', filename);
                end
            end
        end
        
        pause(0.01); % Add delay to reduce CPU usage
    end
    
    disp('Polling timeout reached');
    
catch exception
    disp(['Error: ', exception.message]);
    fprintf('Stack trace: %s\n', getReport(exception));
end

% Clean up
clear spiDev;
clear rpi;
disp('SPI communication ended');