% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi.m
% Create a Raspberry Pi object with verbose output
rpi = raspi();

% Define data ready pin (connected to Teensy pin 14)
dataReadyPin = 25;  % Using GPIO 25 as mentioned earlier

% Configure data ready pin as digital input
configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI Debug Mode');

% Create an SPI device object - slower clock for debugging
spiDev = spidev(rpi, 'CE0', 0, 8000000); % 8 MHz SPI clock for stability

% Small test read to verify SPI functionality
disp('Testing SPI connection with small read...');
testByte = writeRead(spiDev, uint8(0));
fprintf('SPI test read returned: %d (0x%02X)\n', testByte, testByte);

% Buffer size to match Teensy implementation
BUFFER_SIZE = 4096;

try
    % Set a timeout for the polling loop
    timeout = 120; % seconds
    startTime = tic;
    
    disp('Checking initial data ready pin state...');
    initialState = readDigitalPin(rpi, dataReadyPin);
    fprintf('Initial data ready pin state: %d\n', initialState);
    
    disp('Waiting for data ready signal...');
    transactionCount = 0;
    
    % Polling loop with debug info
    while toc(startTime) < timeout
        % Print progress every 5 seconds
        if mod(floor(toc(startTime)), 5) == 0
            persistent lastReport
            if isempty(lastReport) || floor(toc(startTime)) > lastReport
                fprintf('Waiting... Time elapsed: %.1f seconds\n', toc(startTime));
                fprintf('Current data ready pin state: %d\n', readDigitalPin(rpi, dataReadyPin));
                lastReport = floor(toc(startTime));
            end
        end
        
        % Read pin state
        pinState = readDigitalPin(rpi, dataReadyPin);
        
        if pinState
            % Debounce with multiple readings to confirm HIGH
            pause(0.005); % 5ms pause
            if readDigitalPin(rpi, dataReadyPin)  % Second reading
                fprintf('Data ready pin detected HIGH at %.2f seconds\n', toc(startTime));
                pause(0.005); % 5ms pause
                if readDigitalPin(rpi, dataReadyPin)  % Third reading for certainty
                    transactionCount = transactionCount + 1;
                    disp(['Transaction #', num2str(transactionCount), ' - Data ready signal detected']);
                    
                    % Allocate buffer for received data
                    receivedData = uint8(zeros(1, BUFFER_SIZE));
                    
                    % Start time measurement
                    txTime = tic;
                    
                    % Read in smaller chunks with progress reporting
                    chunkSize = 128; 
                    for chunk = 1:chunkSize:BUFFER_SIZE
                        endIdx = min(chunk + chunkSize - 1, BUFFER_SIZE);
                        
                        % Read each byte within the chunk
                        for i = chunk:endIdx
                            receivedData(i) = writeRead(spiDev, uint8(0));
                        end
                        
                        % Progress report every 1024 bytes
                        if mod(chunk, 1024) == 1
                            fprintf('Read %d of %d bytes...\n', endIdx, BUFFER_SIZE);
                        end
                    end
                    
                    % Calculate transfer rate
                    elapsed = toc(txTime);
                    transferRate = BUFFER_SIZE / elapsed;
                    
                    % Display statistics of received data
                    fprintf('Received %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                        length(receivedData), elapsed, transferRate);
                    
                    fprintf('First 16 bytes: ');
                    for i = 1:min(16, length(receivedData))
                        fprintf('%d ', receivedData(i));
                    end
                    fprintf('\n');
                    
                    % Check that data ready signal went LOW
                    disp('Waiting for data ready signal to go LOW');
                    waitTime = tic;
                    
                    % Improved waiting logic with confirmation
                    while toc(waitTime) < 5
                        if readDigitalPin(rpi, dataReadyPin) == 0
                            pause(0.005); % Confirm it's truly LOW
                            if readDigitalPin(rpi, dataReadyPin) == 0
                                break;
                            end
                        end
                        pause(0.01);
                    end
                    
                    if toc(waitTime) < 5
                        disp('Data ready signal went LOW - Ready for next transaction');
                    else
                        disp('Warning: Data ready signal timed out waiting for LOW');
                        % Force a small delay before trying again
                        pause(1.0);
                    end
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