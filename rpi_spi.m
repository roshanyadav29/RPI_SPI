% filepath: e:\Roshan\aiCAS IIT Bombay\C2S\RPI_SPI\rpi_spi.m
% Create a Raspberry Pi object
rpi = raspi();

% Define data ready pin
dataReadyPin = 22;

% Configure data ready pin as digital input
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
    
    % Polling loop
    while toc(startTime) < timeout
        % Check if data is ready with debounce
        if readDigitalPin(rpi, dataReadyPin)
            pause(0.01); % Simple debounce 
            if readDigitalPin(rpi, dataReadyPin) % Double-check
                transactionCount = transactionCount + 1;
                disp(['Transaction #', num2str(transactionCount), ' - Data ready signal detected']);
                
                % Allocate buffer for received data
                receivedData = uint8(zeros(1, BUFFER_SIZE));
                
                % Read data in chunks
                for i = 1:BUFFER_SIZE
                    % Send dummy byte to trigger the Teensy to send its data
                    receivedData(i) = writeRead(spiDev, uint8(0));
                end
                
                % Display statistics of received data
                fprintf('Received %d bytes\n', length(receivedData));
                fprintf('First 10 bytes: ');
                for i = 1:min(10, length(receivedData))
                    fprintf('%d ', receivedData(i));
                end
                fprintf('\n');
                
                % Check that data ready signal went LOW before continuing
                disp('Waiting for data ready signal to go LOW');
                waitTime = tic;
                while readDigitalPin(rpi, dataReadyPin) && toc(waitTime) < 5
                    pause(0.01);
                end
                
                disp('Ready for next transaction');
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