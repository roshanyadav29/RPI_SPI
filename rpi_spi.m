% filepath: /home/admin/RPI_SPI/rpi_spi.m

% Create a Raspberry Pi object
%rpi = raspi();

% dataReadyPin = 22;

% configurePin(rpi, dataReadyPin, 'DigitalInput');
disp('Starting SPI Transaction');

% Create an SPI device object
spiDev = spidev(rpi, 'CE0',0,16000000); % Use 'CE0' for chip select 0

% while true
%     if readDigitalPin(rpi, dataReadyPin)
        sendData = uint8('ABCD');
        receivedData = writeRead(spiDev, sendData);

        fprintf('Received Response: %02X\n', hex2dec(receivedData));
        % end
    
    % Clean up
    clear spiDev;
% end
% fprintf('Sent Data : 0x%d ,Received data : 0x%d \n', sendData,receivedData);


%clear rpi;