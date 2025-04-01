% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi.m
% Create a Raspberry Pi object
rpi = raspi();

% Define data ready pin
dataReadyPin = 25;

% Configure data ready pin as digital input
configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI High-Speed Mode');

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
    
    % Polling loop
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
            transactionCount = transactionCount + 1;
            fprintf('Transaction #%d - Data ready detected\n', transactionCount);
            
            % Create dummy data array for high-speed transfer
            dummyArray = uint8(zeros(1, BUFFER_SIZE));
            
            % Start timing the transfer
            txTime = tic;
            
            % OPTIMIZED: Use bulk transfer instead of byte-by-byte
            receivedData = writeRead(spiDev, dummyArray);
            
            % Calculate transfer rate
            elapsed = toc(txTime);
            transferRate = BUFFER_SIZE / elapsed;
            
            fprintf('Received %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                length(receivedData), elapsed, transferRate);
            
            % Show sample of data
            fprintf('First 16 bytes: ');
            for i = 1:min(16, length(receivedData))
                fprintf('%d ', receivedData(i));
            end
            fprintf('\n');
            
            % Wait for data ready to go LOW
            waitTime = tic;
            while readDigitalPin(rpi, dataReadyPin) && toc(waitTime) < 5
                pause(0.01);
            end
            
            if toc(waitTime) < 5
                disp('Data ready signal went LOW');
            else
                disp('Warning: Timeout waiting for data ready LOW');
            end
        end
        
        pause(0.01);
    end
    
    disp('Polling timeout reached');
    
catch exception
    disp(['Error: ', exception.message]);
end

% Clean up
clear spiDev;
clear rpi;
disp('SPI communication ended');