% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi_chunked.m
% Create a Raspberry Pi object
rpi = raspi();

% Define data ready pin
dataReadyPin = 25;

% Configure data ready pin as digital input
configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI with Chunked Transfer Mode');

% Create an SPI device object
spiDev = spidev(rpi, 'CE0', 0, 8000000); % 8 MHz SPI clock

% Buffer size to match Teensy implementation
TOTAL_BUFFER_SIZE = 4096;
CHUNK_SIZE = 256; % Maximum chunk size for Raspberry Pi MATLAB SPI

try
    % Set a timeout for the polling loop
    timeout = 180; % seconds (extended for multiple chunks)
    startTime = tic;
    transactionCount = 0;
    
    disp('Waiting for data ready signal...');
    
    % Main polling loop
    while toc(startTime) < timeout
        % Status update every 5 seconds
        if mod(floor(toc(startTime)), 5) == 0
            persistent lastReport
            if isempty(lastReport) || floor(toc(startTime)) > lastReport
                fprintf('Waiting... Time elapsed: %.1f seconds\n', toc(startTime));
                fprintf('Data ready pin: %d\n', readDigitalPin(rpi, dataReadyPin));
                lastReport = floor(toc(startTime));
            end
        end
        
        % Check for data ready signal
        if readDigitalPin(rpi, dataReadyPin)
            % Double-check with delay for debounce
            pause(0.01);
            if readDigitalPin(rpi, dataReadyPin)
                transactionCount = transactionCount + 1;
                fprintf('\nTransaction #%d - Data ready detected\n', transactionCount);
                
                % Allocate buffer for complete data
                fullBuffer = uint8(zeros(1, TOTAL_BUFFER_SIZE));
                
                % Start timing the transfer
                txTime = tic;
                
                % Read in chunks of CHUNK_SIZE
                numChunks = ceil(TOTAL_BUFFER_SIZE / CHUNK_SIZE);
                
                fprintf('Reading %d bytes in %d chunks of %d bytes each\n', ...
                    TOTAL_BUFFER_SIZE, numChunks, CHUNK_SIZE);
                
                for chunk = 1:numChunks
                    % Calculate start and end indices for this chunk
                    startIdx = (chunk-1) * CHUNK_SIZE + 1;
                    endIdx = min(chunk * CHUNK_SIZE, TOTAL_BUFFER_SIZE);
                    chunkLength = endIdx - startIdx + 1;
                    
                    % Create dummy data for this chunk
                    dummyChunk = uint8(zeros(1, chunkLength));
                    
                    % Read the chunk
                    chunkStart = tic;
                    receivedChunk = writeRead(spiDev, dummyChunk);
                    chunkTime = toc(chunkStart);
                    
                    % Store in full buffer
                    fullBuffer(startIdx:endIdx) = receivedChunk;
                    
                    % Report progress
                    fprintf('Chunk %d/%d: Read %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                        chunk, numChunks, chunkLength, chunkTime, chunkLength/chunkTime);
                    
                    % Short pause between chunks
                    pause(0.01);
                end
                
                % Calculate overall transfer rate
                elapsed = toc(txTime);
                transferRate = TOTAL_BUFFER_SIZE / elapsed;
                
                fprintf('\nTotal: Received %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                    TOTAL_BUFFER_SIZE, elapsed, transferRate);
                
                % Display data samples
                fprintf('First 16 bytes: ');
                for i = 1:min(16, length(fullBuffer))
                    fprintf('%d ', fullBuffer(i));
                end
                fprintf('\n');
                
                % Check data validity
                uniqueValues = length(unique(fullBuffer));
                fprintf('Unique values in data: %d\n', uniqueValues);
                
                % Wait for data ready signal to go LOW
                disp('Waiting for data ready signal to go LOW...');
                waitTime = tic;
                lowDetected = false;
                
                while toc(waitTime) < 5
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
                    disp('Ready for next transaction');
                else
                    disp('WARNING: Data ready signal timed out waiting for LOW');
                    disp('Forcing data ready LOW by software');
                    configurePin(rpi, dataReadyPin, 'DigitalOutput', 0);
                    pause(0.1);
                    configurePin(rpi, dataReadyPin, 'DigitalInput');
                    pause(0.5);
                end
            end
        end
        
        pause(0.01); % Add delay to reduce CPU usage
    end
    
    disp('Polling timeout reached');
    
catch exception
    disp(['Error: ', exception.message]);
    disp(['Stack: ', getReport(exception)]);
end

% Clean up
clear spiDev;
clear rpi;
disp('SPI communication ended');