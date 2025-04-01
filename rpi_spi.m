% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi_fixed.m
% Create a Raspberry Pi object
rpi = raspi();

% Define data ready pin
dataReadyPin = 25;

% Configure data ready pin as digital input
configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI High-Speed Mode with Robust Handling');

% Create an SPI device object with faster clock
spiDev = spidev(rpi, 'CE0', 0, 8000000); % 8 MHz SPI clock

% Buffer size to match Teensy implementation
BUFFER_SIZE = 4096;

try
    % Set a timeout for the polling loop
    timeout = 120; % seconds
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
        
        % Check for data ready signal with debounce
        if readDigitalPin(rpi, dataReadyPin)
            % Double-check with delay for debounce
            pause(0.01);
            if readDigitalPin(rpi, dataReadyPin)
                transactionCount = transactionCount + 1;
                fprintf('\nTransaction #%d - Data ready detected\n', transactionCount);
                
                % Create dummy data array for bulk transfer
                dummyArray = uint8(zeros(1, BUFFER_SIZE));
                
                % Start timing the transfer
                txTime = tic;
                
                % Bulk transfer mode
                receivedData = writeRead(spiDev, dummyArray);
                
                % Calculate transfer rate
                elapsed = toc(txTime);
                transferRate = BUFFER_SIZE / elapsed;
                
                fprintf('Received %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                    length(receivedData), elapsed, transferRate);
                
                % Show sample of received data
                fprintf('First 16 bytes: ');
                for i = 1:min(16, length(receivedData))
                    fprintf('%d ', receivedData(i));
                end
                fprintf('\n');
                
                % Check if data looks valid
                uniqueValues = length(unique(receivedData));
                fprintf('Unique values in data: %d\n', uniqueValues);
                
                % Wait for data ready signal to go LOW with reliable detection
                disp('Waiting for data ready signal to go LOW...');
                waitTime = tic;
                lowDetected = false;
                
                % Improved waiting with timeout and multiple checks
                while toc(waitTime) < 5
                    if ~readDigitalPin(rpi, dataReadyPin)
                        % Confirm LOW state with double-check
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
                    disp('Check Teensy connections and code');
                    % Add a forced pause to let things recover
                    pause(1.0);
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