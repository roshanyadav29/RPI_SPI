% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi.m
% Create a Raspberry Pi object
rpi = raspi();

% Define data ready pin (connected to Teensy pin 14)
dataReadyPin = 25;  % Using GPIO 25 as mentioned earlier

configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI Transaction with Double Buffer');

% Create an SPI device object
spiDev = spidev(rpi, 'CE0', 0, 16000000); % 16 MHz SPI clock

% Buffer size to match Teensy implementation
BUFFER_SIZE = 4096;

try
    % Set a timeout for the polling loop
    timeout = 120; % seconds
    startTime = tic;
    transactionCount = 0;
    
    disp('Waiting for data ready signal...');
    
    % Polling loop with debounce logic improved for no pull-down
    while toc(startTime) < timeout
        % Read pin state
        pinState = readDigitalPin(rpi, dataReadyPin);
        
        if pinState
            % Debounce with multiple readings to confirm HIGH
            pause(0.005); % 5ms pause
            if readDigitalPin(rpi, dataReadyPin)  % Second reading
                pause(0.005); % 5ms pause
                if readDigitalPin(rpi, dataReadyPin)  % Third reading for certainty
                    transactionCount = transactionCount + 1;
                    disp(['Transaction #', num2str(transactionCount), ' - Data ready signal detected']);
                    
                    % Allocate buffer for received data
                    receivedData = uint8(zeros(1, BUFFER_SIZE));
                    
                    % Start time measurement
                    txTime = tic;
                    
                    % Read data in chunks
                    for i = 1:BUFFER_SIZE
                        % Send dummy byte to trigger the Teensy to send its data
                        receivedData(i) = writeRead(spiDev, uint8(0));
                    end
                    
                    % Calculate transfer rate
                    elapsed = toc(txTime);
                    transferRate = BUFFER_SIZE / elapsed;
                    
                    % Display statistics of received data
                    fprintf('Received %d bytes in %.3f seconds (%.2f bytes/sec)\n', ...
                        length(receivedData), elapsed, transferRate);
                    
                    fprintf('First 10 bytes: ');
                    for i = 1:min(10, length(receivedData))
                        fprintf('%d ', receivedData(i));
                    end
                    fprintf('\n');
                    
                    % Check that data ready signal went LOW before continuing
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
                    end
                end
            end
        end
        
        pause(0.01); % Add delay to reduce CPU usage
    end
    
    disp('Polling timeout reached');
    
catch exception
    disp(['Error: ', exception.message]);
end

% Clean up
clear spiDev;
clear rpi;
disp('SPI communication ended');