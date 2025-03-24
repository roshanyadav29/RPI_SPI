% filepath: /home/admin/RPI_SPI/rpi_spi.m

% Create a Raspberry Pi object
rpi = raspi();

% Create an SPI device object
spiDev = spidev(rpi, 'CE1', 0, 32e6); % Using CE1 (chip select 1)

% Define the number of bytes to read
bytesToRead = 1024;  % Match BUFFER_SIZE from Teensy

% Create a buffer for dummy write data (required for SPI reads)
dummyData = zeros(1, bytesToRead, 'uint8');

% Read data from the Teensy
fprintf('Reading %d bytes from SPI...\n', bytesToRead);
receivedData = writeRead(spiDev, dummyData);

% Display the first few and last few bytes
fprintf('First 10 bytes: ');
disp(receivedData(1:10));
fprintf('Last 10 bytes: ');
disp(receivedData(end-9:end));

% Calculate timestamp from last 4 bytes (if using the format from Teensy)
timestamp = uint32(receivedData(end-3)) * 2^24 + ...
           uint32(receivedData(end-2)) * 2^16 + ...
           uint32(receivedData(end-1)) * 2^8 + ...
           uint32(receivedData(end));
fprintf('Timestamp: %d ms\n', timestamp);

% Plot the data
figure;
plot(1:length(receivedData), receivedData, 'b.-');
title('Data received from Teensy 4.1');
xlabel('Sample Index');
ylabel('Sample Value');
grid on;

% Clean up
clear spiDev;
clear rpi;